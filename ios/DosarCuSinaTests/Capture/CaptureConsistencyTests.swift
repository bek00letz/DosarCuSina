import CoreGraphics
import Foundation
import Testing
@testable import DosarCuSina

/// Dates checked against each other after every tier, and the trust order that settles
/// a disagreement. CNPs are fabricated with county code 99 and a valid control digit.
@Suite("Consistency after all tiers")
struct CaptureConsistencyTests {

    let today = CaptureDay(year: 2026, month: 11, day: 1)!
    let birth = CaptureDay(year: 1990, month: 5, day: 20)!

    private func field(_ key: CaptureFieldKey, _ day: CaptureDay, _ tier: CaptureTier, source: String? = nil) -> CaptureField {
        CaptureField(key: key, value: .day(day), confidence: tier == .heuristic ? 0.8 : 0.72, sourceText: source, tier: tier)
    }

    private func keys(_ fields: [CaptureField]) -> Set<CaptureFieldKey> { Set(fields.map(\.key)) }

    @Test("The birth date taken by the model as the issue date is dropped")
    func birthDateIsNotAnIssueDate() {
        let resolved = CaptureConsistency.resolve([
            field(.birthDate, birth, .heuristic),
            field(.issueDate, birth, .onDeviceModel),
        ], kind: .identityCard, today: today)
        #expect(keys(resolved.fields) == [.birthDate])
        #expect(resolved.dropped == [.issueDate])
    }

    @Test("Passport: the birth date read as the expiry can't make it expired for decades")
    func passportExpiryIsNotTheBirthDate() {
        let resolved = CaptureConsistency.resolve([
            field(.birthDate, birth, .heuristic),
            field(.expiryDate, birth, .onDeviceModel),
            field(.issueDate, CaptureDay(year: 2022, month: 3, day: 1)!, .heuristic),
        ], kind: .passport, today: today)
        #expect(resolved.fields.first { $0.key == .expiryDate } == nil)

        // An expiry before the issue date: the less trusted of the two goes.
        let before = CaptureConsistency.resolve([
            field(.issueDate, CaptureDay(year: 2022, month: 3, day: 1)!, .heuristic),
            field(.expiryDate, CaptureDay(year: 2012, month: 3, day: 1)!, .onDeviceModel),
        ], kind: .passport, today: today)
        #expect(keys(before.fields) == [.issueDate])
        // The AI provider is trusted above the phone's labels (`ReadingArbiter`).
        let secondOpinion = CaptureConsistency.resolve([
            field(.issueDate, CaptureDay(year: 2022, month: 3, day: 1)!, .heuristic),
            field(.expiryDate, CaptureDay(year: 2021, month: 3, day: 1)!, .cloudModel),
        ], kind: .passport, today: today)
        #expect(keys(secondOpinion.fields) == [.expiryDate])
    }

    @Test("An issue date in the future, or before the holder turned 14, isn't an identity card's")
    func issueDateBounds() {
        let future = CaptureConsistency.resolve([field(.issueDate, CaptureDay(year: 2027, month: 1, day: 1)!, .heuristic)], kind: .identityCard, today: today)
        #expect(future.fields.isEmpty)

        let child = CaptureConsistency.resolve([
            field(.birthDate, birth, .deterministic),
            field(.issueDate, CaptureDay(year: 2000, month: 1, day: 1)!, .onDeviceModel),
        ], kind: .identityCard, today: today)
        #expect(keys(child.fields) == [.birthDate])

        // Children get passports: the same dates stand on one.
        let passport = CaptureConsistency.resolve([
            field(.birthDate, birth, .deterministic),
            field(.issueDate, CaptureDay(year: 2000, month: 1, day: 1)!, .heuristic),
        ], kind: .passport, today: today)
        #expect(keys(passport.fields) == [.birthDate, .issueDate])
    }

    @Test("A valid CNP decides the birth date, unless a checked MRZ already did")
    func personalNumberDecidesBirthDate() {
        let cnp = CaptureField(key: .personalNumber, value: .text("2900520990015"), confidence: 0.97, tier: .deterministic)
        let printed = field(.birthDate, CaptureDay(year: 1990, month: 5, day: 2)!, .heuristic)
        let resolved = CaptureConsistency.resolve([cnp, printed], kind: .identityCard, today: today)
        #expect(resolved.fields.first { $0.key == .birthDate }?.value.day == birth)
        #expect(resolved.fields.first { $0.key == .birthDate }?.tier == .deterministic)

        let zone = field(.birthDate, CaptureDay(year: 1990, month: 5, day: 21)!, .deterministic, source: CaptureField.machineReadableSource)
        let withZone = CaptureConsistency.resolve([cnp, zone], kind: .identityCard, today: today)
        #expect(withZone.fields.first { $0.key == .birthDate }?.value.day == CaptureDay(year: 1990, month: 5, day: 21))
    }

    @Test("When two printed values disagree, the other one is marked for a look")
    func tiesMarkTheAnchor() {
        let resolved = CaptureConsistency.resolve([
            field(.birthDate, birth, .heuristic),
            field(.issueDate, birth, .heuristic),
        ], kind: .identityCard, today: today)
        #expect(keys(resolved.fields) == [.birthDate])
        #expect(resolved.fields.first?.needsCheck == true)
    }

    @Test("Only doubtful values are marked: failed checks, or a model alone")
    func whatNeedsACheck() {
        #expect(!CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.8, tier: .heuristic).needsCheck)
        #expect(CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.45, tier: .heuristic).needsCheck)
        #expect(CaptureField(key: .issuer, value: .text("SPCLEP"), confidence: 0.72, tier: .onDeviceModel).needsCheck)
        #expect(!CaptureField(key: .expiryDate, value: .day(today), confidence: 0.99, tier: .deterministic).needsCheck)
    }

    // MARK: Through the engine

    struct PositionedRecognizer: CaptureRecognizing {
        let lines: [RecognizedLine]
        func recognize(_ image: CGImage) async throws -> RecognizedPage {
            RecognizedPage(items: TextLayout.arrange(lines), barcodes: [])
        }
    }

    @Test("Engine: the specimen front reads by column, the model's issue date is dropped, and the back is asked for")
    func engineSpecimen() async throws {
        // A second opinion reads the whole card: the birth date where it is, and again as the issue date.
        let cloud = CaptureEngineTests.StubModel(tier: .cloudModel, isAvailable: true, fields: [
            CaptureField(key: .birthDate, value: .day(CaptureDay(year: 1983, month: 7, day: 3)!), confidence: 0.8, tier: .cloudModel),
            CaptureField(key: .issueDate, value: .day(CaptureDay(year: 1983, month: 7, day: 3)!), confidence: 0.65, tier: .cloudModel),
        ])
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: PositionedRecognizer(lines: Card.electronicFront),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: cloud, store: nil)
        let image = CaptureDocumentStoreTests.page(width: 856, height: 540)
        let result = try await engine.capture(CaptureRequest(.images([CaptureImage(image: image)]),
                                                             options: CaptureOptions(useCloudModel: true, referenceDate: Date(timeIntervalSince1970: 1_793_577_600))))
        #expect(cloud.calls == 1)
        #expect(result.field(.birthDate)?.value.day == CaptureDay(year: 1983, month: 7, day: 3))
        #expect(result.field(.issueDate) == nil)
        #expect(result.field(.givenNames)?.value.text == "CORINA IOANA")
        #expect(result.notices.contains(.identityBackMissing))
        #expect(result.recognizedText.hasPrefix("ROMÂNIA CARTE DE IDENTITATE\nROMANIA\nIDENTITY CARD\nNume\nSurname\nMANOLE"))
    }

    @Test("Engine: a passport whose printed dates were flattened keeps a real expiry")
    func enginePassportExpiry() async throws {
        let text = """
        PAȘAPORT / PASSPORT
        Nume / Surname
        EXEMPLU
        Data nașterii / Date of birth
        20.05.1990
        Data expirării / Date of expiry
        """
        let model = CaptureEngineTests.StubModel(tier: .onDeviceModel, isAvailable: true, fields: [
            CaptureField(key: .expiryDate, value: .day(birth), confidence: 0.65, tier: .onDeviceModel),
        ])
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                                   normalizer: nil, onDeviceModel: model, cloudModel: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.text(text), options: CaptureOptions(referenceDate: Date(timeIntervalSince1970: 1_793_577_600))))
        #expect(result.kind == .passport)
        #expect(result.field(.expiryDate)?.value.day != birth)
        #expect(result.reminder?.day != birth)
    }
}
