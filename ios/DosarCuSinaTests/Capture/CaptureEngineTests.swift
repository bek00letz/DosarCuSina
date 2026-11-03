import CoreGraphics
import Foundation
import Testing
@testable import DosarCuSina

/// The engine's orchestration: tiers in order, the cloud only on request, pages kept, nothing else saved.
@Suite("Capture engine")
struct CaptureEngineTests {

    struct FixedRecognizer: CaptureRecognizing {
        let text: String
        var barcodes: [CaptureBarcode] = []
        func recognize(_ image: CGImage) async throws -> RecognizedPage {
            RecognizedPage(lines: text.components(separatedBy: "\n"), barcodes: barcodes)
        }
    }

    final class StubModel: CaptureSemanticExtracting, @unchecked Sendable {
        let tier: CaptureTier
        let isAvailable: Bool
        let fields: [CaptureField]
        private(set) var calls = 0

        init(tier: CaptureTier, isAvailable: Bool, fields: [CaptureField] = []) {
            self.tier = tier
            self.isAvailable = isAvailable
            self.fields = fields
        }

        func availability() -> CaptureModelAvailability { isAvailable ? .available : .unavailable("deviceNotEligible") }

        func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
            calls += 1
            return SemanticExtraction(kind: nil, fields: fields)
        }
    }

    static let passportText = """
    PAȘAPORT
    P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
    L898902C36UTO7408122F3104150ZE184226B<<<<<16
    """
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    private func makeEngine(text: String, onDevice: StubModel?, cloud: StubModel?, store: CaptureDocumentStore?) -> CaptureEngine {
        CaptureEngine(
            analyzer: CaptureAnalyzer(),
            recognizer: FixedRecognizer(text: text),
            normalizer: nil,
            onDeviceModel: onDevice,
            cloudModel: cloud,
            store: store
        )
    }

    @Test("A passport photo becomes a draft with a deterministic expiry and a stored page")
    func passportPhoto() async throws {
        let store = CaptureDocumentStore()
        let engine = makeEngine(text: Self.passportText, onDevice: nil, cloud: nil, store: store)

        let image = CaptureDocumentStoreTests.page(width: 800, height: 560)
        let result = try await engine.capture(CaptureRequest(.images([CaptureImage(image: image)]), options: CaptureOptions(referenceDate: today)))

        #expect(result.kind == .passport)
        #expect(result.field(.expiryDate)?.value.day == CaptureDay(year: 2031, month: 4, day: 15))
        #expect(result.reminder?.blueprintKey == BuiltInBlueprints.documentRenew)
        let documentID = try #require(result.document?.pendingID)
        #expect(await store.processed(id: documentID)?.document.kind == .passport)
    }

    static let invoiceText = """
    EXEMPLU SERVICE AUTO S.R.L.
    FACTURĂ FISCALĂ seria AUT nr. 004512
    Data facturii: 14.03.2025
    Plăcuțe frână față 320,00
    Manoperă 150,00
    Total de plată: 470,00 lei
    """

    @Test("When the on-device model is unavailable the result says so and patterns still work")
    func modelUnavailable() async throws {
        let model = StubModel(tier: .onDeviceModel, isAvailable: false)
        let engine = makeEngine(text: Self.invoiceText, onDevice: model, cloud: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.text(Self.invoiceText), options: CaptureOptions(referenceDate: today)))

        #expect(model.calls == 0)
        #expect(result.notices.contains(.onDeviceModelUnavailable(reason: "deviceNotEligible")))
        #expect(result.field(.total) != nil)
    }

    @Test("A document the patterns read completely doesn't wait for the on-device model")
    func completeDocumentSkipsTheModel() async throws {
        let model = StubModel(tier: .onDeviceModel, isAvailable: true)
        let engine = makeEngine(text: Self.passportText, onDevice: model, cloud: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.text(Self.passportText), options: CaptureOptions(referenceDate: today)))

        #expect(model.calls == 0)
        #expect(result.field(.expiryDate) != nil)
        #expect(result.tiersUsed == [.deterministic, .heuristic] || result.tiersUsed == [.deterministic])
    }

    @Test("The cloud model never runs unless the person asks for it")
    func cloudOnlyOnRequest() async throws {
        let cloud = StubModel(tier: .cloudModel, isAvailable: true, fields: [
            CaptureField(key: .claimsPhone, value: .text("0800123456"), confidence: 0.7, tier: .cloudModel),
        ])
        let engine = makeEngine(text: "", onDevice: nil, cloud: cloud, store: nil)

        _ = try await engine.capture(CaptureRequest(.text("Polița casco"), options: CaptureOptions(referenceDate: today)))
        #expect(cloud.calls == 0)

        let asked = try await engine.capture(CaptureRequest(.text("Polița casco"), options: CaptureOptions(useCloudModel: true, referenceDate: today)))
        #expect(cloud.calls == 1)
        #expect(asked.field(.claimsPhone)?.tier == .cloudModel)
    }

    @Test("Pasted text isn't stored as a document")
    func pastedText() async throws {
        let store = CaptureDocumentStore()
        let engine = makeEngine(text: "", onDevice: nil, cloud: nil, store: store)

        let result = try await engine.capture(CaptureRequest(.text("Total de plată 210,40 lei"), options: CaptureOptions(referenceDate: today)))
        #expect(result.document == nil)
        #expect(await store.pendingCount == 0)
    }

    @Test("Warranty end is derived from purchase date and length when no tier gave it")
    func derivedWarranty() {
        let fields = CaptureEngine.derived([
            CaptureField(key: .purchaseDate, value: .day(CaptureDay(year: 2025, month: 1, day: 31)!), confidence: 0.8, tier: .heuristic),
            CaptureField(key: .warrantyMonths, value: .number(25), confidence: 0.7, tier: .onDeviceModel),
        ])
        #expect(fields.first { $0.key == .warrantyUntil }?.value.day == CaptureDay(year: 2027, month: 2, day: 28))
    }
}
