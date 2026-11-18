import CoreGraphics
import Foundation

/// Whether a PDF page's own text says what the page shows, or the page is a picture of a paper
/// (a scan) whose text layer holds only a little of it: a scanner app's footer, a page number, a
/// stamp. Such a page is read like a photo, by text recognition (`CaptureEngine`).
///
/// Decided by how much of the page the text covers against how much of it its pictures cover,
/// never by whether any text is there: a page whose pictures cover at least `picturedAtLeast` of
/// it, and whose text lines cover less than `textShareOfPictures` of what those pictures cover,
/// is a scan. A digital page (text drawn as text, a logo beside it) keeps its own text; a scan
/// whose text layer a scanner made from the whole page keeps it too.
enum PDFTextCoverage {
    /// The least share of a page its pictures cover for the page to be a picture of a paper,
    /// not a page with a logo or a photo beside its text.
    static let picturedAtLeast = 0.25
    /// Below this share of what the pictures cover, the page's text is only a part of what it
    /// shows (one footer line covers about a hundredth of a page).
    static let textShareOfPictures = 0.04

    /// Whether a page whose text is `lines` (as `PDFTextLines` read them, in shares of the page)
    /// and whose pictures cover `pictureShare` of it is read by text recognition.
    static func isScanned(lines: [RecognizedLine], pictureShare: Double) -> Bool {
        guard pictureShare >= picturedAtLeast else { return false }
        let textShare = lines.compactMap(\.box).reduce(0) { $0 + min(max($1.width, 0), 1) * min(max($1.height, 0), 1) }
        return textShare < textShareOfPictures * pictureShare
    }

    /// The pages of `data`, by index, that are read by text recognition: those whose text
    /// `lines` (one list per page, as `PDFTextLines.pages` gives them) covers only a little of
    /// what their pictures show.
    static func scannedPages(of data: Data, lines: [[RecognizedLine]]) -> Set<Int> {
        guard let document = PDFPageRendering.document(data) else { return [] }
        return Set(lines.indices.filter { index in
            guard let page = document.page(at: index + 1) else { return false }
            return isScanned(lines: lines[index], pictureShare: PDFPagePictures.share(of: page))
        })
    }
}

/// How much of a PDF page its pictures cover: every image the page's content draws, where it
/// draws it (its own drawings and the forms they draw, a few levels deep), as a share of the
/// page's crop box. Overlapping pictures count once each, capped at the whole page.
enum PDFPagePictures {
    /// How many forms inside forms are followed: more than any scanner writes.
    static let deepestForm = 4

    static func share(of page: CGPDFPage) -> Double {
        let crop = page.getBoxRect(.cropBox)
        guard crop.width > 0, crop.height > 0, let table = operators() else { return 0 }
        defer { CGPDFOperatorTableRelease(table) }
        let state = State(crop: crop, table: table)
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        state.scan(stream)
        return min(state.area / Double(crop.width * crop.height), 1)
    }

    /// What scanning one page keeps: where drawing is placed now, the placements saved, and the
    /// area the pictures cover so far, in points.
    private final class State {
        let crop: CGRect
        let table: CGPDFOperatorTableRef
        var transform = CGAffineTransform.identity
        var saved: [CGAffineTransform] = []
        var area: Double = 0
        /// The content streams being scanned, the innermost last: whose resources name a picture.
        var streams: [CGPDFContentStreamRef] = []

        init(crop: CGRect, table: CGPDFOperatorTableRef) {
            self.crop = crop
            self.table = table
        }

        func scan(_ stream: CGPDFContentStreamRef) {
            streams.append(stream)
            let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(self).toOpaque())
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
            streams.removeLast()
        }

        /// The object `name` drawn where drawing is placed now: a picture adds the part of the
        /// page it covers; a form is scanned in its own placement.
        func draw(_ name: UnsafePointer<CChar>) {
            guard let stream = streams.last, let object = CGPDFContentStreamGetResource(stream, "XObject", name) else { return }
            var drawn: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &drawn), let drawn, let dictionary = CGPDFStreamGetDictionary(drawn) else { return }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
            switch String(cString: subtype) {
            case "Image":
                let covered = CGRect(x: 0, y: 0, width: 1, height: 1).applying(transform).intersection(crop)
                if !covered.isNull { area += Double(covered.width * covered.height) }
            case "Form" where streams.count <= PDFPagePictures.deepestForm:
                // A form without resources of its own reads its parent's.
                var resources: CGPDFDictionaryRef?
                _ = CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
                let around = transform, aroundSaved = saved
                transform = Self.matrix(in: dictionary).concatenating(transform)
                let form = CGPDFContentStreamCreateWithStream(drawn, resources ?? dictionary, stream)
                scan(form)
                CGPDFContentStreamRelease(form)
                transform = around
                saved = aroundSaved
            default:
                break
            }
        }

        /// A form's own placement (`/Matrix`), the identity when it states none.
        static func matrix(in dictionary: CGPDFDictionaryRef) -> CGAffineTransform {
            var array: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(dictionary, "Matrix", &array), let array, CGPDFArrayGetCount(array) == 6 else { return .identity }
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in 0..<6 {
                guard CGPDFArrayGetNumber(array, index, &values[index]) else { return .identity }
            }
            return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
        }
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> State? {
        info.map { Unmanaged<State>.fromOpaque($0).takeUnretainedValue() }
    }

    /// The operators that place drawing and draw pictures: save (`q`), restore (`Q`), place
    /// (`cm`) and draw an object (`Do`).
    private static func operators() -> CGPDFOperatorTableRef? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let state = PDFPagePictures.state(info) else { return }
            state.saved.append(state.transform)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let state = PDFPagePictures.state(info), let last = state.saved.popLast() else { return }
            state.transform = last
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let state = PDFPagePictures.state(info) else { return }
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0..<6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]) else { return }
            }
            let placed = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            state.transform = placed.concatenating(state.transform)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            guard let state = PDFPagePictures.state(info) else { return }
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            state.draw(name)
        }
        return table
    }
}
