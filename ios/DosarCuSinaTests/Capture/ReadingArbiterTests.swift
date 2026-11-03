import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Deciding between readers by evidence: a confident wrong reading on the phone never
/// stops the person's AI provider from doing better, checked values and the person's own
/// edits win over every reader, and what one reader read differently is offered, never
/// applied. Every AI answer is canned; nothing touches the network. Data are placeholders.
@Suite("Reading arbiter")
@MainActor
struct ReadingArbiterTests {

    static let referenceDate = Date(timeIntervalSince1970: 1_793_577_600)
    static let today = CaptureDay(date: referenceDate)

    /// An RCA policy whose words leave the classifier unsure (it also mentions a subscription
    /// and consumption), so a provider-specific reader can claim it.
    static let policyText = """
    POLIȚĂ RCA
    Asigurător: Exemplu Asigurări S.A.
    Polița seria RO/25/X25/AB nr. 000123458
    Nr. înmatriculare B 123 ABC
    Valabilă de la 01.11.2026 până la 31.10.2027
    Plata în abonament, fără consum de puncte bonus
    """

    /// A bill reader that takes every page for a utility bill, as a misreading would.
    struct MisreadingBillParser: CaptureSpecializedParser {
        func parse(_ text: CaptureText) -> CaptureAnalyzer.SpecializedParse? {
            CaptureAnalyzer.SpecializedParse(kind: .utilityInvoice, fields: [
                CaptureField(key: .provider, value: .text("Digi România S.A."), confidence: 0.95, tier: .deterministic),
            ])
        }
    }

    /// A Gemini client that answers every reading with `answer`, as the provider would.
    static func gemini(_ answer: String) -> (AIProviderSettings, AIClient) {
        let settings = AIProviderTests.settings()
        settings.saveKey(AIProviderTests.placeholderKey, for: .gemini)
        let escaped = answer.replacingOccurrences(of: "\"", with: "\\\"")
        let client = AIClient { request in
            let body = #"{"candidates":[{"content":{"parts":[{"text":""# + escaped + #""}]},"finishReason":"STOP"}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return (settings, client)
    }

    /// Reads `text` from a photo, with the phone alone or with a canned AI answer too.
    static func read(_ text: String, parsers: [any CaptureSpecializedParser] = [], answer: String? = nil) async throws -> CaptureResult {
        let cloud = answer.map { answer in
            let (settings, client) = gemini(answer)
            return CloudCaptureExtractor(settings: settings, client: client)
        }
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(specializedParsers: parsers), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: cloud, store: nil)
        let image = CaptureImage(image: CaptureDocumentStoreTests.page(width: 600, height: 800))
        return try await engine.capture(CaptureRequest(.images([image]), options: CaptureOptions(useCloudModel: answer != nil, referenceDate: referenceDate)))
    }

    private func car(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        return try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
    }

    static let policyAnswer = #"{"documentKind":"rcaPolicy","provider":"Exemplu Asigurări S.A.","policyNumber":"RO/25/X25/AB NR 000123456","licensePlate":"B 123 ABC","startDate":"2026-11-01","expiryDate":"2027-10-31","total":null}"#

    // MARK: The kind

    @Test("A policy a bill reader took for a bill is corrected by the AI, and the RCA deadline follows")
    func aiCorrectsAConfidentWrongKind() async throws {
        let phone = try await Self.read(Self.policyText, parsers: [MisreadingBillParser()])
        #expect(phone.kind == .utilityInvoice, "The phone is confidently wrong")
        #expect(phone.kindConfidence >= 0.9)
        #expect(phone.kindEvidence == .providerFormatAlone)
        #expect(ReadingArbiter.weaknesses(of: phone).contains(.providerFormatAlone))

        let read = try await Self.read(Self.policyText, parsers: [MisreadingBillParser()], answer: Self.policyAnswer)
        #expect(read.kind == .rcaPolicy)
        #expect(read.kindEvidence == .secondOpinion)
        #expect(read.kindAlternatives == [CaptureAlternative(.utilityInvoice, source: .phone)])
        #expect(read.readWithCloudModel)
        let expiry = try #require(CaptureDay(year: 2027, month: 10, day: 31))
        #expect(read.field(.expiryDate)?.value.day == expiry)
        #expect(read.reminder?.blueprintKey == BuiltInBlueprints.vehicleRCA)
        #expect(read.field(.provider)?.value.text == "Exemplu Asigurări S.A.", "The bill reader's provider is not the policy's")

        // The review follows the corrected kind: routing, blueprint, reminder, place and title.
        let context = try makeContext()
        let car = try car(context)
        var review = CaptureReview(result: read, assets: [car], context: context)
        #expect(review.kind == .rcaPolicy)
        #expect(review.blueprintKey == "vehicle.rca")
        #expect(review.reminderDay == CaptureMapping.calendarDay(expiry))
        #expect(!review.remindsToPay)
        #expect(review.destination == .asset(car.id))
        #expect(review.kindAlternatives == [CaptureAlternative(.utilityInvoice, source: .phone)], "Pe telefon părea: …")

        // Switching back to the phone's kind is one tap, and the AI's kind is then offered.
        review.useKind(CaptureAlternative(.utilityInvoice, source: .phone))
        review.kindChanged(assets: [car])
        #expect(review.kind == .utilityInvoice)
        #expect(review.kindAlternatives == [CaptureAlternative(.rcaPolicy, source: .cloudModel)])
        #expect(review.blueprintKey == nil)
    }

    @Test("A checked zone keeps its kind against the AI's, which is offered")
    func deterministicKindStays() {
        let phone = ReadingArbiter.KindReading(kind: .passport, confidence: 0.98, evidence: .machineReadableZone)
        let decided = ReadingArbiter.kind(phone, secondOpinion: .identityCard)
        #expect(decided.reading == phone)
        #expect(decided.alternatives == [CaptureAlternative(.identityCard, source: .cloudModel)])

        let unsure = ReadingArbiter.KindReading(kind: .insurancePolicy, confidence: 0.95, evidence: .classifier)
        #expect(ReadingArbiter.kind(unsure, secondOpinion: .rcaPolicy).reading.kind == .rcaPolicy, "Confidence alone doesn't hold the AI back")
        #expect(ReadingArbiter.kind(unsure, secondOpinion: .other).reading == unsure, "'Other' is no opinion")
    }

    // MARK: Values

    @Test("An AI value missing from a misread phone text is kept, marked, and the phone's is offered")
    func aiValueNotInTheTextIsKept() async throws {
        let phone = try await Self.read(Self.policyText)
        let misread = try #require(phone.field(.policyNumber)?.value.text)
        #expect(!misread.contains("000123456"), "The phone misread a digit")

        let read = try await Self.read(Self.policyText, answer: Self.policyAnswer)
        let policy = try #require(read.field(.policyNumber))
        #expect(policy.value.text == "RO/25/X25/AB NR 000123456")
        #expect(policy.tier == .cloudModel)
        #expect(policy.needsCheck, "Two readers disagree: Verifică")
        #expect(read.alternatives(for: .policyNumber) == [CaptureAlternative(.text(misread), source: .phone)])

        let context = try makeContext()
        let review = CaptureReview(result: read, assets: [], context: context)
        let field = try #require(review.fields.first { $0.key == .policyNumber })
        #expect(field.alternatives == [CaptureAlternative(.text(misread), source: .phone)], "Pe telefon am citit: …")
        // Values the AI and the phone agree on need no look.
        #expect(review.fields.first { $0.key == .licensePlate }?.needsCheck == false)
    }

    @Test("An AI value nobody else read is kept for a look; a checked one is certain")
    func aiValuesAloneAreKept() throws {
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"documentKind":"rcaPolicy","claimsPhone":"0800 000 000","vin":"1M8GDM9AXKP042788"}"#.utf8))
        let fields = CloudAnswerMapper.fields(from: answer, schema: CloudSchema(kind: .utilityInvoice), recognizedText: "", today: Self.today, resolver: CatalogComponentResolver())
        #expect(fields.first { $0.key == .claimsPhone }?.needsCheck == true)
        #expect(fields.first { $0.key == .vin }?.needsCheck == false)
        #expect(CloudAnswerMapper.kind(from: answer) == .rcaPolicy)
    }

    @Test("A document number checked by the zone beats a differing AI value")
    func checkedZoneBeatsTheAI() async throws {
        let text = "PAȘAPORT\n" + MRZFixtures.passport()
        let read = try await Self.read(text, answer: #"{"documentKind":"passport","surname":"EXEMPLU","documentNumber":"X99999999","machineReadableZone":[]}"#)
        let number = try #require(read.field(.documentNumber))
        #expect(number.value.text == "X04512378")
        #expect(!number.needsCheck, "A check settles it")
        #expect(read.kind == .passport)

        let context = try makeContext()
        let review = CaptureReview(result: read, assets: [], context: context)
        #expect(review.fields.first { $0.key == .documentNumber }?.alternatives.isEmpty == true, "Nothing is offered beside a checked value")
    }

    @Test("The order: checked values, then the AI, then the phone's patterns, then Apple's model")
    func order() {
        func field(_ tier: CaptureTier, _ value: String, confidence: Double = 0.7, key: CaptureFieldKey = .policyNumber) -> CaptureField {
            CaptureField(key: key, value: .text(value), confidence: confidence, tier: tier)
        }
        #expect(ReadingArbiter.prefers(field(.cloudModel, "A", confidence: 0.5), over: field(.heuristic, "B", confidence: 0.9)))
        #expect(ReadingArbiter.prefers(field(.cloudModel, "A", confidence: 0.5), over: field(.deterministic, "B", confidence: 0.95)), "A provider's format proves nothing")
        #expect(!ReadingArbiter.prefers(field(.cloudModel, "1800101990007", key: .personalNumber), over: field(.heuristic, "1800101990006", key: .personalNumber)))
        #expect(ReadingArbiter.prefers(field(.heuristic, "A"), over: field(.onDeviceModel, "B")), "On a tie the pattern beats the model")
        #expect(ReadingArbiter.standing(CaptureField(key: .documentNumber, value: .text("X"), confidence: 0.99, sourceText: CaptureField.machineReadableSource, tier: .cloudModel)) == .machineReadableZone)
    }

    // MARK: The person's edits

    @Test("An edit survives an AI reading")
    func editSurvivesTheAI() async throws {
        let context = try makeContext()
        var before = CaptureReview(result: try await Self.read(Self.policyText), assets: [], context: context)
        let index = try #require(before.fields.firstIndex { $0.key == .policyNumber })
        before.fields[index].confirm(.text("RO/25/X25/AB NR 000123457"))

        let read = try await Self.read(Self.policyText, answer: Self.policyAnswer)
        let after = CaptureReview(result: read, assets: [], context: context).carryingEdits(from: before, assets: [])
        let field = try #require(after.fields.first { $0.key == .policyNumber })
        #expect(field.value == .text("RO/25/X25/AB NR 000123457"), "The person's value stays")
        #expect(field.alternatives == [CaptureAlternative(.text("RO/25/X25/AB NR 000123456"), source: .cloudModel)], "The AI's is offered beside it")
        #expect(after.usedCloudModel)
    }

    @Test("An edit survives an AI reading and a checked zone that both differ, and both are offered")
    func editSurvivesTheAIAndTheZone() async throws {
        let context = try makeContext()
        let printed = "PAȘAPORT\nNume / Surname\nEXEMPLU\nNr. pașaport / Passport No.\nX04512378"
        var before = CaptureReview(result: try await Self.read(printed), assets: [], context: context)
        if let index = before.fields.firstIndex(where: { $0.key == .documentNumber }) {
            before.fields[index].confirm(.text("X04512379"))
        } else {
            var typed = CaptureReview.Field(key: .documentNumber, value: nil, confidence: 1, sourceText: nil, tier: .deterministic)
            typed.confirm(.text("X04512379"))
            before.fields.append(typed)
        }

        let withZone = printed + "\n" + MRZFixtures.passport()
        let read = try await Self.read(withZone, answer: #"{"documentKind":"passport","documentNumber":"X99999999","machineReadableZone":[]}"#)
        #expect(read.field(.documentNumber)?.value.text == "X04512378")
        let after = CaptureReview(result: read, assets: [], context: context).carryingEdits(from: before, assets: [])
        let field = try #require(after.fields.first { $0.key == .documentNumber })
        #expect(field.value == .text("X04512379"), "The person's value stays")
        #expect(Set(field.alternatives) == [
            CaptureAlternative(.text("X04512378"), source: .checked(machineReadable: true)),
            CaptureAlternative(.text("X99999999"), source: .cloudModel),
        ])
    }

    @Test("A kind the person changed survives an AI reading that says otherwise")
    func kindEditSurvivesTheAI() async throws {
        let context = try makeContext()
        let car = try car(context)
        var before = CaptureReview(result: try await Self.read(Self.policyText, parsers: [MisreadingBillParser()]), assets: [car], context: context)
        before.kind = .insurancePolicy
        before.kindChanged(assets: [car])
        before.title = "Polița mașinii"

        let read = try await Self.read(Self.policyText, parsers: [MisreadingBillParser()], answer: Self.policyAnswer)
        #expect(read.kind == .rcaPolicy)
        let after = CaptureReview(result: read, assets: [car], context: context).carryingEdits(from: before, assets: [car])
        #expect(after.kind == .insurancePolicy, "Their kind stays")
        #expect(after.kindAlternatives == [CaptureAlternative(.rcaPolicy, source: .cloudModel)], "The AI's is offered beside it")
        #expect(after.title == "Polița mașinii")
        #expect(after.blueprintKey != "vehicle.rca", "What depends on the kind follows theirs")
        #expect(after.blueprintKey == BuiltInBlueprints.vehicleCASCO)
    }

    // MARK: A weak reading

    private func result(_ kind: CaptureDocumentKind = .rcaPolicy, confidence: Double = 0.9, evidence: CaptureKindEvidence = .classifier,
                        fields: [CaptureField] = [], notices: [CaptureNotice] = []) -> CaptureResult {
        CaptureResult(kind: kind, kindConfidence: confidence, fields: fields, suggestions: [], reminder: nil, recognizedText: "",
                      barcodes: [], document: nil, notices: notices, kindEvidence: evidence)
    }

    @Test("A weak reading: unsure kind, missing essentials, a failed check, little text, a provider's format alone")
    func weakReading() throws {
        let expiry = try #require(CaptureDay(year: 2031, month: 4, day: 12))
        #expect(ReadingArbiter.weaknesses(of: result()).isEmpty)
        #expect(!ReadingArbiter.isWeak(result()))

        #expect(ReadingArbiter.weaknesses(of: result(confidence: 0.55)) == [.unsureKind])

        let partial = result(.passport, confidence: 0.98, evidence: .machineReadableZone, fields: [
            CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.9, tier: .heuristic),
        ])
        #expect(ReadingArbiter.weaknesses(of: partial) == [.identityEssentialsMissing])

        let wrongCNP = result(.identityCard, confidence: 0.9, fields: [
            CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .documentNumber, value: .text("XT1234567"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .personalNumber, value: .text("1800101990007"), confidence: 0.5, tier: .heuristic),
        ])
        #expect(ReadingArbiter.weaknesses(of: wrongCNP) == [.failedCheck])
        #expect(ReadingArbiter.weaknesses(of: result(notices: [.machineReadableZoneUnverified])) == [.failedCheck])
        #expect(ReadingArbiter.weaknesses(of: result(notices: [.valueFailedCheck])) == [.failedCheck])
        #expect(ReadingArbiter.weaknesses(of: result(notices: [.littleTextRecognized])) == [.littleText])
        #expect(ReadingArbiter.weaknesses(of: result(.utilityInvoice, confidence: 0.95, evidence: .providerFormatAlone)) == [.providerFormatAlone])
        #expect(ReadingArbiter.weaknesses(of: result(.utilityInvoice, confidence: 0.95, evidence: .providerFormat)).isEmpty)
    }

    @Test("The automatic reading is off until the person turns it on, and runs only after a weak reading")
    func automaticReadingIsOffByDefault() {
        let settings = AIProviderTests.settings()
        #expect(!settings.readsAutomaticallyWhenUnsure)
        settings.saveKey(AIProviderTests.placeholderKey, for: .gemini)
        let weak = result(confidence: 0.5)
        #expect(!settings.readsAutomatically(after: weak), "Off by default")

        settings.readsAutomaticallyWhenUnsure = true
        #expect(settings.readsAutomatically(after: weak))
        #expect(!settings.readsAutomatically(after: result()), "A sound reading isn't sent")
        settings.deleteKey(for: .gemini)
        #expect(!settings.readsAutomatically(after: weak), "Not without a provider")
    }

    @Test("An identity document's photo is never sent by itself: the review asks first", arguments: [
        CaptureDocumentKind.identityCard, .passport, .drivingLicence,
    ])
    func identityDocumentsAskBeforeSending(_ kind: CaptureDocumentKind) {
        let settings = AIProviderTests.settings()
        settings.saveKey(AIProviderTests.placeholderKey, for: .gemini)
        settings.readsAutomaticallyWhenUnsure = true
        #expect(settings.automaticReading(after: result(kind, confidence: 0.5)) == .askFirst)
        #expect(!settings.readsAutomatically(after: result(kind, confidence: 0.5)))
        #expect(settings.automaticReading(after: result(.rcaPolicy, confidence: 0.5)) == .read, "A policy still reads by itself")
        #expect(settings.automaticReading(after: result(.utilityInvoice, confidence: 0.5)) == .read, "A bill too")
        #expect(settings.automaticReading(after: result(.rcaPolicy, confidence: 0.5), headedForProtectedPlace: true) == .askFirst,
                "Headed for a locked section or a person's documents: ask first")
        settings.deleteKey(for: .gemini)
    }

    @Test("A glared identity card the phone read as something else still asks before it is sent")
    func unrecognisedIdentityAsks() {
        let settings = AIProviderTests.settings()
        settings.saveKey(AIProviderTests.placeholderKey, for: .gemini)
        settings.readsAutomaticallyWhenUnsure = true
        defer { settings.deleteKey(for: .gemini) }
        func page(_ text: String) -> CaptureResult {
            CaptureResult(kind: .other, kindConfidence: 0.3, fields: [], suggestions: [], reminder: nil, recognizedText: text,
                          barcodes: [], document: nil, notices: [.littleTextRecognized])
        }
        // Glare hid the title; what's left still says what it is.
        #expect(settings.automaticReading(after: page("ROMANIA\nIDROUEXEMPLU<<ION<<<<<<<<<<<<<<<<<<<<<<")) == .askFirst, "A zone's fillers")
        #expect(settings.automaticReading(after: page("CNP 1800101990006\nEXEMPLU")) == .askFirst, "A CNP-shaped number")
        #expect(settings.automaticReading(after: page("Data nașterii 01.01.1980\nEXEMPLU ION")) == .askFirst, "Identity words")
        #expect(settings.automaticReading(after: page("ENGIE Romania S.A.\nTotal de plată 245,30 lei")) == .read, "A bill reads by itself")
    }
}
