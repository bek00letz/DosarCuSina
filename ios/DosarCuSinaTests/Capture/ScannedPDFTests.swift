import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import DosarCuSina

/// A PDF page that is a picture of a paper is read by what it shows, even when a scanner app
/// added a line of text of its own; a digital PDF keeps its own text. Placeholder text only.
@Suite("A scanned PDF is read by what its pages show")
struct ScannedPDFTests {
    static let pageBox = CGRect(x: 0, y: 0, width: 595.32, height: 841.92)

    /// A grey picture, standing for a photo of a paper.
    static func picture() -> CGImage? {
        guard let context = CGContext(data: nil, width: 60, height: 84, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 84))
        return context.makeImage()
    }

    /// One page: a picture over `pictured` of the page's height (from its top), and `lines` of
    /// text, each at its distance from the page's top.
    static func pdf(pictured: CGFloat?, lines: [(String, CGFloat)]) -> Data {
        let data = NSMutableData()
        var box = pageBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        if let pictured, let picture = picture() {
            let height = box.height * pictured
            context.draw(picture, in: CGRect(x: 0, y: box.height - height, width: box.width, height: height))
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 8, nil)
        for (text, top) in lines {
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: 40, y: box.height - top - CTFontGetAscent(font))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// A scan of a whole paper, with the scanner app's footer as its only text.
    static let scanWithFooter = pdf(pictured: 1, lines: [("Scanat cu Aplicația Exemplu Scanner · pagina 1 din 1", 825)])

    static let bill = """
        ENGIE Romania S.A.
        CUI: RO12345674
        FACTURĂ GAZE NATURALE
        Data emiterii: 01.11.2026
        Total de plată: 123,45 lei
        """

    @Test("A scanned page whose only text is a scanner app's footer is read by text recognition")
    func aScanWithAFooterIsRecognized() async throws {
        let lines = PDFTextLines.pages(of: Self.scanWithFooter, maxPages: CaptureEngine.maxPDFPages)
        #expect(lines.first?.isEmpty == false, "The footer is a text layer")
        #expect(PDFTextCoverage.scannedPages(of: Self.scanWithFooter, lines: lines) == [0])

        let engine = CaptureEngine(analyzer: .standard(), recognizer: CaptureEngineTests.FixedRecognizer(text: Self.bill), normalizer: nil,
                                   onDeviceModel: nil, cloudModel: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.pdf(Self.scanWithFooter), options: CaptureOptions(
            useOnDeviceModel: false, useCloudModel: false, storeDocument: false, referenceDate: noon("2026-11-02"))))
        #expect(result.kind == .utilityInvoice, "Read by what the page shows")
        #expect(result.field(.total)?.value == .money(Money(Decimal(string: "123.45")!, currency: "RON")))
    }

    @Test("A digital page keeps its own text, a logo beside it or not")
    func aDigitalPageKeepsItsText() {
        let text = (0..<30).map { ("Rândul \($0) al facturii, cu textul ei, așa cum îl scrie firma", CGFloat(60 + $0 * 20)) }
        let digital = Self.pdf(pictured: nil, lines: text)
        let withLogo = Self.pdf(pictured: 0.08, lines: text)
        for data in [digital, withLogo, PADPolicyFixture.pdf()] {
            let lines = PDFTextLines.pages(of: data, maxPages: CaptureEngine.maxPDFPages)
            #expect(PDFTextCoverage.scannedPages(of: data, lines: lines).isEmpty)
        }
    }

    @Test("A scan whose text layer covers the paper keeps that text")
    func aScanWithItsOwnTextKeepsIt() {
        let text = (0..<30).map { ("Rândul \($0) al facturii, cu textul ei, așa cum îl scrie firma", CGFloat(60 + $0 * 20)) }
        let searchable = Self.pdf(pictured: 1, lines: text)
        let lines = PDFTextLines.pages(of: searchable, maxPages: CaptureEngine.maxPDFPages)
        #expect(PDFTextCoverage.scannedPages(of: searchable, lines: lines).isEmpty)
    }

    @Test("The rule: a page mostly a picture, whose text covers little of it")
    func theRule() throws {
        let footer = [RecognizedLine("Scanat cu Aplicația Exemplu", box: TextBox(x: 0.05, y: 0.97, width: 0.6, height: 0.012))]
        #expect(PDFTextCoverage.isScanned(lines: footer, pictureShare: 1))
        #expect(!PDFTextCoverage.isScanned(lines: footer, pictureShare: 0.1), "A logo is no scan")
        let page = try #require(PDFPageRendering.document(Self.scanWithFooter)?.page(at: 1))
        #expect(PDFPagePictures.share(of: page) > 0.99)
    }
}
