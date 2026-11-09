import CoreGraphics
import Foundation
import ImageIO

// MARK: - A page to draw

/// One page of a document, ready to be drawn: the photo as kept (or the PDF and the page's
/// number) and how it is framed. A value, so it can be drawn away from the main thread.
public struct DocumentPageSource: Sendable, Identifiable {
    public enum Content: Sendable {
        /// A page image (HEIC or JPEG), as taken.
        case image(Data)
        /// Page `page` (from 0) of a PDF kept whole.
        case pdf(Data, page: Int)
    }

    /// The page's place in the document, from 0.
    public let index: Int
    public let content: Content
    public let framing: PageFraming

    public init(index: Int, content: Content, framing: PageFraming) {
        self.index = index
        self.content = content
        self.framing = framing
    }

    public var id: Int { index }

    public var isPDF: Bool {
        if case .pdf = content { return true }
        return false
    }

    /// What decides how the page looks, for redrawing only when it changes.
    public var drawingKey: DrawingKey {
        switch content {
        case .image(let data): DrawingKey(index: index, bytes: data.count, isPDF: false, framing: framing)
        case .pdf(let data, let page): DrawingKey(index: page, bytes: data.count, isPDF: true, framing: framing)
        }
    }

    public struct DrawingKey: Hashable, Sendable {
        let index: Int
        let bytes: Int
        let isPDF: Bool
        let framing: PageFraming
    }
}

/// The pages of a document as they are shown: the one place that says what a document's
/// pages are, for the viewer, the document page, the review and sharing.
public enum DocumentPages {
    /// A filed document's pages: its page images, else its PDF's pages, else the image it
    /// keeps whole, else (nothing else readable) its thumbnail.
    @MainActor
    public static func sources(of attachment: Attachment) -> [DocumentPageSource] {
        sources(
            pageImages: attachment.orderedPages.compactMap(\.imageData),
            original: attachment.fileData,
            thumbnail: attachment.thumbnailData,
            framing: attachment.framing
        )
    }

    /// A capture's pages, with what the person chose in the review on top.
    public static func sources(of processed: ProcessedDocument, choices: [Int: PageChoice] = [:]) -> [DocumentPageSource] {
        sources(pageImages: processed.pageData, original: processed.originalPDF, thumbnail: processed.thumbnailData,
                framing: processed.framing.applying(choices))
    }

    static func sources(pageImages: [Data], original: Data?, thumbnail: Data?, framing: DocumentFraming) -> [DocumentPageSource] {
        if !pageImages.isEmpty {
            return pageImages.enumerated().map { DocumentPageSource(index: $0, content: .image($1), framing: framing[page: $0]) }
        }
        if let original {
            let count = PDFPageRendering.pageCount(original)
            if count > 0 {
                return (0..<count).map { DocumentPageSource(index: $0, content: .pdf(original, page: $0), framing: framing[page: $0]) }
            }
            if PageImageDecoding.size(of: original) != nil {
                return [DocumentPageSource(index: 0, content: .image(original), framing: framing[page: 0])]
            }
        }
        // The thumbnail was drawn as the page was shown: it is never framed again.
        if let thumbnail, PageImageDecoding.size(of: thumbnail) != nil {
            return [DocumentPageSource(index: 0, content: .image(thumbnail), framing: .plain)]
        }
        return []
    }
}

// MARK: - Drawing a page

/// Draws a page as it is shown: cut out of its photo and flattened when it is, turned the
/// way it goes. The one way every screen, share and thumbnail draws a page, so what the
/// person sees is what they send.
public enum DocumentPicture {

    /// The page as shown. `maxLongEdge` limits its size in pixels; a PDF page is drawn at
    /// `pdfPixelsPerPoint` (sharp enough to print) unless that limit is smaller.
    public static func image(of source: DocumentPageSource, maxLongEdge: Int? = nil,
                             pdfPixelsPerPoint: CGFloat = PDFPageRendering.sharingPixelsPerPoint) -> CGImage? {
        switch source.content {
        case .image(let data):
            // A cut-out is a part of the photo: decode the photo whole so the part stays sharp.
            guard let photo = PageImageDecoding.decode(data, maxLongEdge: source.framing.showsCrop ? nil : maxLongEdge) else { return nil }
            let picture = shown(photo, framing: source.framing)
            return maxLongEdge.flatMap { ImageEncoding.scaled(picture, maxLongEdge: $0) } ?? picture
        case .pdf(let data, let index):
            guard let document = PDFPageRendering.document(data), let page = document.page(at: index + 1) else { return nil }
            let turns = source.framing.shownQuarterTurns
            let size = PDFPageRendering.shownSize(of: page, quarterTurns: turns)
            var scale = pdfPixelsPerPoint
            if let maxLongEdge, max(size.width, size.height) > 0 {
                scale = min(scale, CGFloat(maxLongEdge) / max(size.width, size.height))
            }
            return PDFPageRendering.render(page, quarterTurns: turns, pixelsPerPoint: scale)
        }
    }

    /// Part of a PDF page as shown (`rect` in points from its top-left) at `pixelsPerPoint`:
    /// what a zoomed-in screen shows, one drawn pixel for each pixel of the screen. Nil for a photo.
    public static func region(of source: DocumentPageSource, rect: CGRect, pixelsPerPoint: CGFloat) -> CGImage? {
        guard case .pdf(let data, let index) = source.content,
              let page = PDFPageRendering.document(data)?.page(at: index + 1) else { return nil }
        return PDFPageRendering.render(page, quarterTurns: source.framing.shownQuarterTurns, rect: rect, pixelsPerPoint: pixelsPerPoint)
    }

    /// A photo as its framing shows it: the document cut out and flattened (when it is
    /// shown cut out), then turned.
    public static func shown(_ photo: CGImage, framing: PageFraming) -> CGImage {
        var image = photo
        if framing.showsCrop, let crop = framing.crop,
           let flattened = ImageScaling.flattened(photo, corners: imageCorners(crop, width: photo.width, height: photo.height)) {
            image = flattened
        }
        return turned(image, quarterTurns: framing.shownQuarterTurns) ?? image
    }

    /// The image turned `quarterTurns` quarter turns clockwise.
    public static func turned(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = PageFraming.normalized(quarterTurns)
        guard turns != 0 else { return image }
        let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let size = PageTurn.size(box.size, quarterTurns: turns)
        guard let context = PageTurn.canvas(width: Int(size.width), height: Int(size.height)) else { return nil }
        context.interpolationQuality = .high
        context.concatenate(PageTurn.transform(box: box, quarterTurns: turns))
        context.draw(image, in: box)
        return context.makeImage()
    }

    /// The page's size as shown, without drawing it: pixels for a photo, points for a PDF
    /// page. For keeping the page's space while it is drawn.
    public static func shownSize(of source: DocumentPageSource) -> CGSize? {
        switch source.content {
        case .image(let data):
            guard let photo = PageImageDecoding.size(of: data) else { return nil }
            var size = photo
            if source.framing.showsCrop, let crop = source.framing.crop {
                size = cutOutSize(imageCorners(crop, width: Int(photo.width), height: Int(photo.height)))
            }
            return PageTurn.size(size, quarterTurns: source.framing.shownQuarterTurns)
        case .pdf(let data, let index):
            guard let page = PDFPageRendering.document(data)?.page(at: index + 1) else { return nil }
            return PDFPageRendering.shownSize(of: page, quarterTurns: source.framing.shownQuarterTurns)
        }
    }

    /// A document's thumbnail, from its first page as shown.
    public static func thumbnailData(of source: DocumentPageSource) -> Data? {
        image(of: source, maxLongEdge: CaptureDocumentStore.thumbnailMaxLongEdge).flatMap(thumbnailData(of:))
    }

    /// A thumbnail encoded from a page already drawn as shown.
    public static func thumbnailData(of image: CGImage) -> Data? {
        try? ImageEncoding.encode(image, maxLongEdge: CaptureDocumentStore.thumbnailMaxLongEdge, quality: CaptureDocumentStore.thumbnailQuality).data
    }

    // MARK: Corners

    /// Corners kept as fractions from the top-left, as Core Image wants them: pixels from the bottom-left.
    static func imageCorners(_ crop: [PagePoint], width: Int, height: Int) -> [CGPoint] {
        crop.map { CGPoint(x: $0.x * Double(width), y: (1 - $0.y) * Double(height)) }
    }

    /// Corners found in a photo (pixels from the bottom-left), as kept: fractions from the
    /// top-left, inside the photo.
    static func pagePoints(_ corners: [CGPoint], width: Int, height: Int) -> [PagePoint]? {
        guard corners.count == 4, width > 0, height > 0 else { return nil }
        return corners.map { point in
            PagePoint(x: min(max(Double(point.x) / Double(width), 0), 1),
                      y: min(max(1 - Double(point.y) / Double(height), 0), 1))
        }
    }

    /// About the size a cut-out comes out at: its longer top or bottom edge by its longer side.
    static func cutOutSize(_ corners: [CGPoint]) -> CGSize {
        guard corners.count == 4 else { return .zero }
        func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        return CGSize(width: max(length(corners[0], corners[1]), length(corners[3], corners[2])),
                      height: max(length(corners[0], corners[3]), length(corners[1], corners[2])))
    }
}

// MARK: - Turning

/// Quarter turns clockwise, for photos and PDF pages alike.
enum PageTurn {
    /// The size of a page turned `quarterTurns` times: a quarter or three swap its sides.
    static func size(_ size: CGSize, quarterTurns: Int) -> CGSize {
        PageFraming.normalized(quarterTurns) % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    }

    /// From a page's own space (its box, y up) to the space it is shown in (from the
    /// bottom-left corner, y up), turned `quarterTurns` times clockwise.
    static func transform(box: CGRect, quarterTurns: Int) -> CGAffineTransform {
        let width = box.width, height = box.height, minX = box.minX, minY = box.minY
        switch PageFraming.normalized(quarterTurns) {
        case 1: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: -minY, ty: width + minX)
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width + minX, ty: height + minY)
        case 3: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height + minY, ty: -minX)
        default: return CGAffineTransform(translationX: -minX, y: -minY)
        }
    }

    /// A white canvas of this many pixels, ready to draw on.
    static func canvas(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }
}

// MARK: - PDF pages

/// Draws PDF pages at the sharpness asked for: a screen's pixels at the zoom shown, or
/// enough to print. The one PDF renderer, for reading, thumbnails, the viewer and sharing.
public enum PDFPageRendering {
    /// Sharing and printing: 300 pixels per inch.
    public static let sharingPixelsPerPoint: CGFloat = 300 / 72
    /// The most pixels one drawing may take (about 160 MB), whatever is asked.
    static let maxPixels = 40_000_000

    static func document(_ data: Data) -> CGPDFDocument? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGPDFDocument(provider)
    }

    /// How many pages the PDF has; 0 when it isn't one.
    public static func pageCount(_ data: Data) -> Int {
        guard data.starts(with: Array("%PDF".utf8)) || data.prefix(1024).range(of: Data("%PDF".utf8)) != nil,
              let document = document(data) else { return 0 }
        return document.numberOfPages
    }

    /// The turns a page is shown with: its own (`/Rotate`), then the framing's.
    static func turns(of page: CGPDFPage, quarterTurns: Int) -> Int {
        PageFraming.normalized(Int(page.rotationAngle) / 90 + quarterTurns)
    }

    /// The page's size as shown, in points.
    public static func shownSize(of page: CGPDFPage, quarterTurns: Int) -> CGSize {
        PageTurn.size(page.getBoxRect(.cropBox).size, quarterTurns: turns(of: page, quarterTurns: quarterTurns))
    }

    /// The pixels per point that keep a page sharp in a view `viewWidth` points wide that
    /// fits the page's width, zoomed `zoom` times, on a screen of `screenScale`: one drawn
    /// pixel for every pixel on the screen.
    public static func pixelsPerPoint(pageWidth: CGFloat, viewWidth: CGFloat, zoom: CGFloat, screenScale: CGFloat) -> CGFloat {
        guard pageWidth > 0, viewWidth > 0 else { return screenScale }
        return viewWidth / pageWidth * max(zoom, 1) * screenScale
    }

    /// Draws `rect` of the page as shown (points from its top-left; the whole page when nil)
    /// at `pixelsPerPoint`, on white. Asked for more than `maxPixels`, it draws as sharp as fits.
    public static func render(_ page: CGPDFPage, quarterTurns: Int, rect: CGRect? = nil, pixelsPerPoint: CGFloat) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0, pixelsPerPoint > 0 else { return nil }
        let pageTurns = turns(of: page, quarterTurns: quarterTurns)
        let shown = PageTurn.size(box.size, quarterTurns: pageTurns)
        let area = (rect ?? CGRect(origin: .zero, size: shown)).intersection(CGRect(origin: .zero, size: shown))
        guard !area.isNull, area.width > 0, area.height > 0 else { return nil }
        var scale = pixelsPerPoint
        let asked = Double(area.width * scale) * Double(area.height * scale)
        if asked > Double(maxPixels) { scale *= CGFloat((Double(maxPixels) / asked).squareRoot()) }
        let width = max(1, Int((area.width * scale).rounded()))
        let height = max(1, Int((area.height * scale).rounded()))
        guard let context = PageTurn.canvas(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(width) / area.width, y: CGFloat(height) / area.height)
        context.translateBy(x: -area.minX, y: -(shown.height - area.maxY))
        context.concatenate(PageTurn.transform(box: box, quarterTurns: pageTurns))
        context.clip(to: box)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    /// The first `maxPages` pages, each drawn so its long edge is `longEdge` pixels: for reading.
    static func render(_ data: Data, maxPages: Int, longEdge: CGFloat) -> [CGImage] {
        guard let document = document(data) else { return [] }
        let count = min(document.numberOfPages, maxPages)
        guard count > 0 else { return [] }
        return (1...count).compactMap { number in
            guard let page = document.page(at: number) else { return nil }
            let size = shownSize(of: page, quarterTurns: 0)
            guard max(size.width, size.height) > 0 else { return nil }
            return render(page, quarterTurns: 0, pixelsPerPoint: longEdge / max(size.width, size.height))
        }
    }
}

// MARK: - Page images

/// Reading kept page images: their size, and the image itself, upright, as large as asked.
enum PageImageDecoding {
    static func size(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        let sideways: Set<CGImagePropertyOrientation> = [.left, .leftMirrored, .right, .rightMirrored]
        return sideways.contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// The image upright, its long edge at most `maxLongEdge` (as stored when nil).
    static func decode(_ data: Data, maxLongEdge: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxLongEdge { options[kCGImageSourceThumbnailMaxPixelSize] = maxLongEdge }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
