import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A bank card's front, with the Visa test number every payment provider publishes.
private let bankCardText = """
Banca Transilvania
DEBIT
4111 1111 1111 1111
VALID THRU 08/28
ION EXEMPLU
VISA
"""

/// A bank card is read only on the phone: never sent to the AI provider, not on "Citește
/// mai bine", not by "Citește automat", not by a reading again with added pages. Nor is a
/// page the phone can't be sure isn't one. Placeholder data only: the card numbers are
/// the networks' published test numbers.
@Suite("Bank cards stay on the phone")
@MainActor
struct PhoneOnlyReadingTests {
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    static let policy = """
    ASIGURARE OBLIGATORIE DE RĂSPUNDERE CIVILĂ AUTO (RCA)
    Asigurător: Exemplu Asigurări S.A.
    Nr. înmatriculare: B-123-ABC
    Valabilă de la 01.11.2026 până la 31.10.2027
    """
    static let bill = "ENGIE Romania S.A.\nTotal de plată 245,30 lei\nCod client 1234567890"

    // MARK: The rule is data

    @Test("Only a bank card is read only on the phone, by type and by kind")
    func onlyBankCards() {
        #expect(DocumentType.readOnPhoneOnly == [DocumentType.bankCard])
        for option in DocumentType.options {
            #expect(DocumentType.isReadOnPhoneOnly(option.key) == (option.key == DocumentType.bankCard), "\(option.key)")
        }
        #expect(DocumentType.isReadOnPhoneOnly("Card bancar"), "A label stored by an earlier version")
        #expect(!DocumentType.isReadOnPhoneOnly(nil))
        for kind in CaptureDocumentKind.allCases {
            #expect(PhoneOnlyReading.isPhoneOnly(kind) == (kind == .bankCard), "\(kind)")
        }
        #expect(PhoneOnlyReading.holdsOne(FieldValues([DocumentType.typeFieldKey: .text(DocumentType.bankCard)])))
        #expect(!PhoneOnlyReading.holdsOne(FieldValues([DocumentType.typeFieldKey: .text(DocumentType.idCard)])))
        #expect(!PhoneOnlyReading.holdsOne(FieldValues()))
    }

    @Test("When the phone can't be sure a page isn't a bank card, it is treated as one")
    func whenInDoubt() {
        func page(_ kind: CaptureDocumentKind, _ text: String, alternatives: [CaptureDocumentKind] = [], notices: [CaptureNotice] = []) -> CaptureResult {
            CaptureResult(kind: kind, kindConfidence: 0.5, fields: [], suggestions: [], reminder: nil, recognizedText: text,
                          barcodes: [], document: nil, notices: notices,
                          kindAlternatives: alternatives.map { CaptureAlternative($0, source: .phone) })
        }
        #expect(PhoneOnlyReading.mayBeOne(page(.bankCard, "")), "Read as a bank card")
        #expect(PhoneOnlyReading.mayBeOne(page(.other, "Plată 4111 1111 1111 1111")), "A whole card number")
        #expect(PhoneOnlyReading.mayBeOne(page(.other, "Plată •••• 1111")), "One already masked")
        #expect(PhoneOnlyReading.mayBeOne(page(.other, "VALID THRU 08/28")), "Words only a card prints")
        #expect(PhoneOnlyReading.mayBeOne(page(.other, "GOOD THRU 08/28")))
        #expect(PhoneOnlyReading.mayBeOne(page(.rcaPolicy, "", alternatives: [.bankCard])), "Another reader saw a card")
        #expect(PhoneOnlyReading.mayBeOne(page(.other, "", notices: [.readOnPhoneOnly])), "The engine kept it on the phone")
        #expect(PhoneOnlyReading.decisiveWords.contains("valid thru"))

        #expect(!PhoneOnlyReading.mayBeOne(page(.rcaPolicy, Self.policy)))
        #expect(!PhoneOnlyReading.mayBeOne(page(.utilityInvoice, Self.bill)))
        #expect(!PhoneOnlyReading.mayBeOne(page(.criminalRecord, "CNP 1800101990006")), "A CNP isn't a card number")
    }

    // MARK: The engine: nothing is sent, whoever asked

    final class PageRecognizer: CaptureRecognizing, @unchecked Sendable {
        /// The text of each page, by the page's width.
        let texts: [Int: String]
        init(_ texts: [Int: String]) { self.texts = texts }
        func recognize(_ image: CGImage) async throws -> RecognizedPage {
            RecognizedPage(lines: (texts[image.width] ?? "").components(separatedBy: "\n"), barcodes: [])
        }
    }

    private func engine(_ recognizer: any CaptureRecognizing, cloud: CaptureEngineTests.StubModel) -> CaptureEngine {
        CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: recognizer, normalizer: nil, onDeviceModel: nil, cloudModel: cloud, store: nil)
    }

    private func cloud() -> CaptureEngineTests.StubModel {
        CaptureEngineTests.StubModel(tier: .cloudModel, isAvailable: true, fields: [
            CaptureField(key: .claimsPhone, value: .text("0800123456"), confidence: 0.7, tier: .cloudModel),
        ])
    }

    private func options() -> CaptureOptions {
        CaptureOptions(useOnDeviceModel: false, useCloudModel: true, storeDocument: false, referenceDate: today)
    }

    @Test("Asked to read with the AI provider, the engine sends nothing that may be a bank card", arguments: [
        bankCardText,
        "Chitanță\nPlătit cu cardul 5555 5555 5555 4444",
        "BANCA EXEMPLU\nVALID THRU 08/28\nION EXEMPLU",
    ])
    func engineKeepsCardsOnThePhone(_ text: String) async throws {
        let model = cloud()
        let result = try await engine(CaptureEngineTests.FixedRecognizer(text: text), cloud: model)
            .capture(CaptureRequest(.text(text), options: options()))
        #expect(model.calls == 0, "Nothing was sent")
        #expect(!result.readWithCloudModel)
        #expect(result.notices.contains(.readOnPhoneOnly))
        #expect(!result.notices.contains { if case .cloudModelFailed = $0 { true } else { false } }, "Not a failure")
    }

    @Test("Anything else is still read by the AI provider when asked")
    func otherPagesAreSent() async throws {
        let model = cloud()
        let result = try await engine(CaptureEngineTests.FixedRecognizer(text: Self.policy), cloud: model)
            .capture(CaptureRequest(.text(Self.policy), options: options()))
        #expect(model.calls == 1)
        #expect(result.readWithCloudModel)
        #expect(!result.notices.contains(.readOnPhoneOnly))
    }

    @Test("Pages added after the AI provider read the first are checked before anything is sent")
    func addedPagesAreChecked() async throws {
        let first = CaptureImage(image: CaptureDocumentStoreTests.page(width: 400, height: 600, seed: 1))
        let card = CaptureImage(image: CaptureDocumentStoreTests.page(width: 401, height: 600, seed: 2))
        let recognizer = PageRecognizer([400: Self.policy, 401: bankCardText])
        let model = cloud()
        let reader = self.engine(recognizer, cloud: model)

        let alone = try await reader.capture(CaptureRequest(.images([first]), options: options()))
        #expect(alone.readWithCloudModel)
        #expect(model.calls == 1)

        let withCard = try await reader.capture(CaptureRequest(.images([first, card]), options: options()))
        #expect(model.calls == 1, "The pages with the card weren't sent")
        #expect(!withCard.readWithCloudModel)
        #expect(withCard.notices.contains(.readOnPhoneOnly))
    }

    // MARK: Citește automat

    private func weak(_ kind: CaptureDocumentKind, _ text: String = "") -> CaptureResult {
        CaptureResult(kind: kind, kindConfidence: 0.3, fields: [], suggestions: [], reminder: nil, recognizedText: text,
                      barcodes: [], document: nil, notices: [.littleTextRecognized])
    }

    @Test("Citește automat never sends a bank card, nor asks to")
    func automaticReadingNeverSendsACard() {
        let settings = AIProviderTests.settings()
        settings.saveKey(AIProviderTests.placeholderKey, for: .gemini)
        settings.readsAutomaticallyWhenUnsure = true
        defer { settings.deleteKey(for: .gemini) }
        #expect(settings.automaticReading(after: weak(.bankCard)) == .none)
        #expect(settings.automaticReading(after: weak(.other, "4111 1111 1111 1111")) == .none, "Not even asked")
        #expect(settings.automaticReading(after: weak(.other, "VALID THRU 08/28")) == .none)
        #expect(settings.automaticReading(after: weak(.other, Self.bill), headedForProtectedPlace: true, staysOnPhone: true) == .none,
                "The person is adding a bank card")
        #expect(!settings.readsAutomatically(after: weak(.bankCard)))
        // Everything else as before.
        #expect(settings.automaticReading(after: weak(.other, Self.bill)) == .read)
        #expect(settings.automaticReading(after: weak(.identityCard)) == .askFirst)
    }

    // MARK: The capture session

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _cloud: [Bool] = []
        var cloud: [Bool] { lock.withLock { _cloud } }
        func read(cloud: Bool) { lock.withLock { _cloud.append(cloud) } }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func reading(_ kind: CaptureDocumentKind) -> CaptureResult {
        CaptureResult(kind: kind, kindConfidence: 0.9, fields: [], suggestions: [], reminder: nil, recognizedText: "",
                      barcodes: [], document: nil, notices: [])
    }

    @Test("Adding a bank card: neither the tap nor added pages reach the AI provider")
    func addingACardStaysOnThePhone() async throws {
        let calls = Calls()
        let session = CaptureSession(payload: .text("Card"), reader: { _, cloud, _ in
            calls.read(cloud: cloud)
            return self.reading(.other)
        }, automaticReading: { _, _ in .none })
        session.destination = CaptureSession.Destination(isProtected: true, staysOnPhone: true)
        session.read()
        #expect(await eventually { session.result != nil })
        #expect(!session.providerMayRead(session.result))
        session.readAgain(.cloud)
        try await Task.sleep(for: .milliseconds(20))
        #expect(calls.cloud == [false], "The tap sends nothing")
        session.readAgain(.pages, payload: .text("Card, spatele"))
        #expect(await eventually { calls.cloud.count == 2 })
        #expect(calls.cloud == [false, false], "Added pages are read on the phone")
    }

    @Test("A reading that is a bank card is never read again by the AI provider; one that isn't still is")
    func aCardReadingIsNeverSent() async throws {
        let calls = Calls()
        let card = CaptureSession(payload: .text("Card"), reader: { _, cloud, _ in
            calls.read(cloud: cloud)
            return self.reading(.bankCard)
        }, automaticReading: { _, _ in .none })
        card.read()
        #expect(await eventually { card.result != nil })
        card.readAgain(.cloud)
        try await Task.sleep(for: .milliseconds(20))
        #expect(calls.cloud == [false])

        let policy = CaptureSession(payload: .text("RCA"), reader: { _, cloud, _ in
            calls.read(cloud: cloud)
            return self.reading(.rcaPolicy)
        }, automaticReading: { _, _ in .none })
        policy.read()
        #expect(await eventually { policy.result != nil })
        policy.readAgain(.cloud)
        #expect(await eventually { calls.cloud == [false, false, true] })
    }

    // MARK: The review

    @Test("The review offers Citește mai bine only for what may leave the phone")
    func reviewButton() throws {
        let context = try makeContext()
        let card = CaptureReview(result: reading(.bankCard), assets: [], context: context)
        #expect(!card.providerMayRead, "A bank card")

        var policy = CaptureReview(result: reading(.rcaPolicy), assets: [], context: context)
        #expect(policy.providerMayRead)
        policy.kind = .bankCard
        #expect(!policy.providerMayRead, "The person said it is a bank card")

        var started = CaptureReview(result: reading(.other), assets: [], context: context)
        started.staysOnPhone = true
        #expect(!started.providerMayRead, "Started from a bank card's page")
        let merged = CaptureReview(result: reading(.other), assets: [], context: context).carryingEdits(from: started, assets: [])
        #expect(!merged.providerMayRead, "Kept when the page is read again")

        let masked = CaptureResult(kind: .other, kindConfidence: 0.5, fields: [], suggestions: [], reminder: nil,
                                   recognizedText: "Plată •••• 1111", barcodes: [], document: nil, notices: [])
        #expect(!CaptureReview(result: masked, assets: [], context: context).providerMayRead, "A page that shows a card number")
    }
}
