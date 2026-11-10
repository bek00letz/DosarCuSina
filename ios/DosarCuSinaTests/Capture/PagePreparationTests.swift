import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import DosarCuSina

/// Finding the card, the machine-readable band, and the one retry for photos that read
/// poorly. Placeholder data only.
@Suite("Page preparation and retry")
struct PagePreparationTests {

    let now = Date(timeIntervalSince1970: 1_793_577_600)

    // MARK: The card

    @Test("The card-shaped rectangle wins over smaller or squarer ones; tiny ones are ignored")
    func bestCard() {
        let size = CGSize(width: 4000, height: 3000)
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> [CGPoint] {
            [CGPoint(x: x, y: y + height), CGPoint(x: x + width, y: y + height), CGPoint(x: x + width, y: y), CGPoint(x: x, y: y)]
        }
        let card = rect(800, 600, 2378, 1500)    // 1.585 : 1
        let square = rect(500, 500, 2400, 2300)  // almost square, larger
        let tiny = rect(10, 10, 300, 190)        // a card far away
        #expect(DocumentImageNormalizer.bestCard([square, card, tiny], imageSize: size) == card)
        #expect(DocumentImageNormalizer.bestCard([tiny], imageSize: size) == nil)
        #expect(abs(DocumentImageNormalizer.aspect(card) - 1 / 1.585) < 0.01)

        let passportPage = rect(400, 400, 2840, 2000) // 1.42 : 1
        #expect(DocumentImageNormalizer.bestCard([square, passportPage], imageSize: size) == passportPage)
    }

    @Test("Small pages are enlarged up to three times; large ones are left alone; quarter turns swap the sides")
    func scaling() throws {
        let small = CaptureDocumentStoreTests.page(width: 400, height: 250)
        let enlarged = try #require(ImageScaling.scaled(small, toLongEdge: 2000, .up))
        #expect(enlarged.width == 1200)
        let large = CaptureDocumentStoreTests.page(width: 2400, height: 1500)
        #expect(ImageScaling.scaled(large, toLongEdge: 2000, .up) === large)

        let turned = try #require(DocumentPicture.turned(small, quarterTurns: 1))
        #expect(turned.width == 250)
        #expect(turned.height == 400)
    }

    // MARK: The band

    @Test("The machine-readable band is found from filler-dense lines at the bottom, padded by a line")
    func band() throws {
        let lines = [
            RecognizedLine("PAȘAPORT / PASSPORT", box: TextBox(x: 0.1, y: 0.05, width: 0.5, height: 0.04)),
            RecognizedLine("EXEMPLU", box: TextBox(x: 0.3, y: 0.30, width: 0.2, height: 0.04)),
            RecognizedLine("P<UTOEXEMPLU<<ANA<<<<<<<<<<<<<<<<<<<<<<<<<<", box: TextBox(x: 0.04, y: 0.82, width: 0.92, height: 0.045)),
            RecognizedLine("X045123785UTO9005209F3104127180010199000654", box: TextBox(x: 0.04, y: 0.89, width: 0.92, height: 0.045)),
        ]
        let band = try #require(MachineReadableBand.find(in: lines))
        #expect(band.minX == 0 && band.width == 1)
        #expect(band.minY < 0.82 && band.minY > 0.7)
        #expect(band.maxY > 0.935)
        #expect(band.contains(lines[3].box!))
        #expect(!band.contains(lines[1].box!))
        #expect(!MachineReadableBand.looksLikeZone(lines[1]))
        #expect(MachineReadableBand.find(in: Array(lines.prefix(2))) == nil)
    }

    @Test("A zone reading is scored by its passing check digits")
    func bandScore() {
        let good = MRZFixtures.passport().components(separatedBy: "\n")
        let damaged = MRZFixtures.replacing(MRZFixtures.passport(), line: 1, at: 15, with: "7").components(separatedBy: "\n")
        #expect(MachineReadableBand.score(good) > MachineReadableBand.score(damaged))
        #expect(MachineReadableBand.score(["Factura nr. 123"]) == 0)
    }

    // MARK: Retry

    /// Prepares pages to a fixed landscape image and offers a portrait one, a quarter turn, as the retry.
    struct TurningPreparer: CapturePagePreparing {
        var offersVariant = true
        func prepare(_ image: CGImage) async -> PreparedPage { PreparedPage(image: CaptureDocumentStoreTests.page(width: 856, height: 540)) }
        func retryVariant(of prepared: PreparedPage, original: CGImage) async -> PreparedPage? {
            offersVariant ? PreparedPage(image: CaptureDocumentStoreTests.page(width: 540, height: 856), framing: PageFraming(quarterTurns: 1)) : nil
        }
    }

    /// Reads almost nothing from landscape images and a passport from portrait ones.
    struct SidewaysRecognizer: CaptureRecognizing {
        func recognize(_ image: CGImage) async throws -> RecognizedPage {
            image.height > image.width
                ? RecognizedPage(lines: ["PAȘAPORT"] + MRZFixtures.passport().components(separatedBy: "\n"), barcodes: [])
                : RecognizedPage(lines: ["ㅁ ㅁ", "1 1"], barcodes: [])
        }
    }

    /// Remembers the page it was given.
    final class RecordingModel: CaptureSemanticExtracting, @unchecked Sendable {
        let tier: CaptureTier = .cloudModel
        private(set) var page: CGImage?
        func availability() -> CaptureModelAvailability { .available }
        func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
            page = input.firstPage
            return SemanticExtraction(kind: nil, fields: [])
        }
    }

    @Test("A page that reads poorly is read once more the other way up, and the better reading is kept")
    func retriesOnce() async throws {
        let model = RecordingModel()
        let store = CaptureDocumentStore()
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: SidewaysRecognizer(), normalizer: TurningPreparer(),
                                   onDeviceModel: nil, cloudModel: model, store: store)
        let photo = CaptureDocumentStoreTests.page(width: 3000, height: 4000)
        let result = try await engine.capture(CaptureRequest(.images([CaptureImage(image: photo)]),
                                                             options: CaptureOptions(useCloudModel: true, referenceDate: now)))
        #expect(result.kind == .passport)
        #expect(result.field(.expiryDate)?.value.day == CalendarDay(printedYear: 2031, month: 4, day: 12))
        #expect(!result.notices.contains(.littleTextRecognized))
        // The model is shown the page as it was read; the photo as taken is what's kept.
        #expect(model.page?.width == 540)
        let id = try #require(result.document?.pendingID)
        let kept = try #require(await store.processed(id: id)?.pageData.first)
        let source = try #require(CGImageSourceCreateWithData(kept as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        #expect(height > width)
        // The way up that read better is the way the page is shown and shared.
        #expect(await store.processed(id: id)?.framing[page: 0].shownQuarterTurns == 1)
    }

    @Test("When the retry can't help, a calm notice says the photo is hard to read")
    func hardToRead() async throws {
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: SidewaysRecognizer(), normalizer: TurningPreparer(offersVariant: false),
                                   onDeviceModel: nil, cloudModel: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.images([CaptureImage(image: CaptureDocumentStoreTests.page(width: 400, height: 300))]),
                                                             options: CaptureOptions(referenceDate: now)))
        #expect(result.notices.filter { $0 == .littleTextRecognized }.count == 1)
    }

    @Test("An identity document without any of its fields counts as a poor reading")
    func identityWithoutFields() {
        #expect(CaptureDocumentKind.passport.lacksExpectedFields([
            CaptureField(key: .nationality, value: .text("ROU"), confidence: 0.8, tier: .heuristic),
        ]))
        #expect(!CaptureDocumentKind.passport.lacksExpectedFields([
            CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.8, tier: .heuristic),
        ]))
        #expect(!CaptureDocumentKind.utilityInvoice.lacksExpectedFields([]))
    }
}
