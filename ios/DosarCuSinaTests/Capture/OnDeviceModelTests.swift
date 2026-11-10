import CoreGraphics
import Foundation
import FoundationModels
import Testing
@testable import DosarCuSina

/// Apple's on-device model asks what each kind's profile lists, through the questions the
/// AI provider is asked too, and its answers go through the same mapper and checks. The
/// model itself doesn't run in tests: the generation schema it is given is pinned through
/// Foundation Models' own encoding, and answers are `GeneratedContent` built by hand. Data
/// is placeholders only.
@Suite("On-device model")
struct OnDeviceModelTests {

    static let today = CaptureDay(year: 2026, month: 11, day: 10)!

    // MARK: The schema, kind by kind

    /// The generation schema as the JSON Schema Foundation Models encodes it.
    private func encoded(_ schema: GenerationSchema) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(schema))
    }

    /// A property's shape, in a word: what its value is asked as.
    private func shape(_ property: JSONValue, in root: JSONValue) -> String {
        var property = property
        if let reference = property["$ref"]?.string, let name = reference.split(separator: "/").last,
           let definition = root["$defs"]?[String(name)] {
            property = definition
        }
        if let choices = property["enum"]?.array?.compactMap(\.string) { return "choice:" + choices.joined(separator: ",") }
        switch property["type"]?.string {
        case "string": return property["pattern"] == nil ? "string" : "date"
        case "integer": return "integer"
        case "object":
            let keys = Set(property["properties"]?.object?.keys.map { $0 } ?? [])
            return keys == ["amount", "currency"] ? "money" : "object"
        case "array":
            return property["items"]?["$ref"] != nil ? "lines" : "strings"
        default: return "unknown"
        }
    }

    /// What each format must be asked as.
    private func expectedShape(_ format: ModelFieldFormat) -> String {
        switch format {
        case .date: "date"
        case .integer: "integer"
        case .money: "money"
        case .sex: "choice:M,F"
        case .serviceKind: "choice:" + ServiceKind.all.joined(separator: ",")
        case .coverage: "choice:" + InsuranceCover.all.joined(separator: ",")
        case .cardNetwork: "choice:" + PaymentCardNetwork.all.joined(separator: ",")
        case .lineItems: "lines"
        case .machineReadableZone: "strings"
        case .text, .name, .personalNumber, .documentNumber, .country, .categories, .meterIndex, .vin, .plate, .phone, .cardLastFour: "string"
        }
    }

    @Test("Each kind is asked exactly its profile's fields, with their types, and nothing else", arguments: CaptureDocumentKind.allCases)
    func schemaFollowsTheProfile(kind: CaptureDocumentKind) throws {
        let questions = ModelQuestions(kind: kind, reader: .text)
        let schema = try encoded(try OnDeviceSchema.facts(questions))
        let properties = try #require(schema["properties"]?.object, "\(kind)")

        #expect(Set(properties.keys) == Set(kind.expectedKeys.map(\.rawValue)), "\(kind): exactly the profile's keys")
        #expect(schema["x-order"]?.array?.compactMap(\.string) == kind.expectedKeys.map(\.rawValue), "\(kind): in the profile's order")
        #expect(schema["required"]?.array?.isEmpty ?? true, "\(kind): a field not printed is left out")
        #expect(properties[ModelQuestions.kindName] == nil, "\(kind): the kind is its own question")
        #expect(properties[ModelQuestions.zoneName] == nil, "\(kind): the phone reads the zone itself")

        for key in kind.expectedKeys {
            let property = try #require(properties[key.rawValue])
            let format = ModelQuestions.format(of: key)
            #expect(shape(property, in: schema) == expectedShape(format), "\(kind).\(key.rawValue)")
            #expect(property["description"]?.string == questions.fields.first { $0.key == key }?.description, "\(kind).\(key.rawValue)")
        }
    }

    @Test("Both models are asked each kind's fields from one description", arguments: CaptureDocumentKind.allCases)
    func oneDescriptionForBothModels(kind: CaptureDocumentKind) {
        let onDevice = ModelQuestions(kind: kind, reader: .text).fields
        let provider = CloudSchema(kind: kind).fields
        #expect(Array(provider.prefix(onDevice.count)) == onDevice, "\(kind): the provider is asked the same fields first, described the same")
        #expect(onDevice.compactMap(\.key) == kind.expectedKeys)
    }

    @Test("A personal document's fields are written the way its templates read them")
    func templateFormatsAgree() {
        func format(_ printed: IdentityFormat) -> ModelFieldFormat {
            switch printed {
            case .name: .name
            case .personalNumber: .personalNumber
            case .documentNumber, .composite: .documentNumber
            case .date, .dateRange, .cardExpiry: .date
            case .sex: .sex
            case .country: .country
            case .text, .bankName, .recordResult: .text
            case .categories: .categories
            case .cardLastFour: .cardLastFour
            case .cardNetwork: .cardNetwork
            }
        }
        for template in IdentityTemplates.all {
            for field in template.fields {
                #expect(ModelQuestions.format(of: field.key) == format(field.format), "\(template.kind).\(field.key.rawValue)")
                if case .dateRange(let start) = field.format { #expect(ModelQuestions.format(of: start) == .date) }
            }
            #expect(Set(template.kind.expectedKeys).isSuperset(of: IdentityTemplates.fieldKeys(for: template.kind)), "\(template.kind): every value its templates read is asked")
        }
    }

    @Test("The kind question names every kind and nothing else")
    func kindQuestion() throws {
        let schema = try encoded(try OnDeviceSchema.kindQuestion())
        let properties = try #require(schema["properties"]?.object)
        #expect(Set(properties.keys) == [ModelQuestions.kindName])
        #expect(properties[ModelQuestions.kindName]?["enum"]?.array?.compactMap(\.string) == CaptureDocumentKind.allCases.map(\.rawValue))
        #expect(schema["required"]?.array?.compactMap(\.string) == [ModelQuestions.kindName])
    }

    // MARK: The answers

    private func map(_ json: String, kind: CaptureDocumentKind, text: String) throws -> [CaptureFieldKey: CaptureField] {
        let answer = OnDeviceSchema.json(try GeneratedContent(json: json))
        let fields = ModelAnswerMapper.fields(from: answer, asked: ModelQuestions(kind: kind, reader: .text), recognizedText: text,
                                              today: Self.today, resolver: CatalogComponentResolver())
        #expect(fields.allSatisfy { $0.tier == .onDeviceModel && $0.needsCheck }, "Every value Apple's model gives is marked for a look")
        return Dictionary(fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static let policy = """
    EXEMPLU ASIGURĂRI S.A.
    Poliță RCA Seria RO/00/X00/XX nr. 012345678
    Valabilă de la 07.11.2026 până la 06.11.2027
    Nr. înmatriculare B 123 ABC
    Avizare daune: 0800 123 456
    Prima: 1.240,00 lei
    """

    @Test("What is printed in the text is kept, typed by its format")
    func printedValuesAreKept() throws {
        let fields = try map("""
        {"provider":"Exemplu Asigurări S.A.","policyNumber":"RO/00/X00/XX 012345678","startDate":"2026-11-07","expiryDate":"2027-11-06",
         "licensePlate":"b 123 abc","claimsPhone":"0800 123 456","total":{"amount":1240,"currency":"RON"},"coverageType":"\(InsuranceCover.rca)"}
        """, kind: .rcaPolicy, text: Self.policy)
        #expect(fields[.provider]?.value.text == "Exemplu Asigurări S.A.")
        #expect(fields[.policyNumber] != nil)
        #expect(fields[.expiryDate]?.value.day == CaptureDay(year: 2027, month: 11, day: 6))
        #expect(fields[.startDate]?.value.day == CaptureDay(year: 2026, month: 11, day: 7))
        #expect(fields[.licensePlate]?.value.text == "B 123 ABC")
        #expect(fields[.claimsPhone] != nil)
        #expect(fields[.total]?.value == .money(CaptureMoney(amount: 1240, currencyCode: "RON")))
        #expect(fields[.coverageType]?.value.text == InsuranceCover.rca)
        #expect(fields.values.allSatisfy { $0.confidence == ModelAnswerMapper.printedInText })
    }

    @Test("What isn't printed in the text is dropped: the model saw nothing else")
    func inventedValuesAreDropped() throws {
        let fields = try map("""
        {"provider":"Altă Firmă S.A.","policyNumber":"XY 999999999","licensePlate":"B 999 ZZZ","total":{"amount":5000,"currency":"RON"},
         "expiryDate":"2027-12-31","vin":"WVWZZZ1KZAW000001"}
        """, kind: .rcaPolicy, text: Self.policy)
        #expect(fields.isEmpty)
    }

    @Test("A field the kind's profile doesn't list is never kept")
    func unaskedKeysAreDropped() throws {
        let fields = try map("""
        {"expiryDate":"2027-11-06","productName":"Poliță","serialNumber":"012345678","invoiceNumber":"012345678","documentKind":"rcaPolicy"}
        """, kind: .rcaPolicy, text: Self.policy)
        #expect(Set(fields.keys) == [.expiryDate])
    }

    @Test("Only the invoice lines printed in the text are kept")
    func printedLinesOnly() throws {
        let text = """
        EXEMPLU SERVICE AUTO S.R.L.
        Plăcuțe frână față 320,00
        Manoperă 150,00
        Total de plată: 470,00 lei
        """
        let fields = try map("""
        {"lineItems":[{"description":"Plăcuțe frână față","amount":320},{"description":"Manoperă","amount":150},{"description":"Ulei motor","amount":90}]}
        """, kind: .serviceInvoice, text: text)
        let lines = try #require(fields[.lineItems]?.value.lineItems)
        #expect(lines.map(\.description) == ["Plăcuțe frână față", "Manoperă"])
    }

    @Test("A personal number is kept only when printed, and ranks as checked when its control digit passes")
    func personalNumber() throws {
        let text = """
        ROMÂNIA CARTE DE IDENTITATE
        CNP 1800101990006
        Nume EXEMPLU
        Prenume ANA
        """
        let fields = try map(#"{"personalNumber":"1800101990006","surname":"EXEMPLU","givenNames":"ANA","birthDate":"1980-01-01"}"#,
                             kind: .identityCard, text: text)
        let cnp = try #require(fields[.personalNumber])
        #expect(ReadingArbiter.standing(cnp) == .checked)
        #expect(fields[.holderName]?.value.text == "ANA EXEMPLU")
        #expect(fields[.birthDate] == nil, "Not printed as a date: the phone works it out from the CNP")

        let other = try map(#"{"personalNumber":"1800101990006"}"#, kind: .identityCard, text: "CARTE DE IDENTITATE\nNume EXEMPLU")
        #expect(other[.personalNumber] == nil)
    }

    @Test("From a bank card, only the last four digits, whatever the model answers")
    func bankCardKeepsLastFour() throws {
        let text = """
        EXEMPLU BANK
        4111 1111 1111 1111
        VALID THRU 08/28
        ANA EXEMPLU
        """
        let fields = try map(#"{"cardLastFour":"4111 1111 1111 1111","holderName":"ANA EXEMPLU"}"#, kind: .bankCard, text: text)
        #expect(fields[.cardLastFour]?.value.text == "1111")
        #expect(!fields.values.contains { ($0.value.text ?? "").filter(\.isNumber).count > 4 })
        #expect(!ModelQuestions(kind: .bankCard, reader: .text).fields.contains { $0.key == .documentNumber || $0.key == .serialNumber },
                "Nothing else that could hold the number is asked")
    }

    // MARK: The kind

    @Test("The model's kind is asked only while the phone is unsure, and 'other' is no opinion")
    func kindStaysOpenOnlyWhileUnsure() throws {
        let unsure = ReadingArbiter.KindReading(kind: .serviceInvoice, confidence: 0.4, evidence: .classifier)
        let sure = ReadingArbiter.KindReading(kind: .serviceInvoice, confidence: 0.9, evidence: .classifier)
        let checked = ReadingArbiter.KindReading(kind: .passport, confidence: 0.5, evidence: .machineReadableZone)
        #expect(ReadingArbiter.kindIsOpen(unsure))
        #expect(!ReadingArbiter.kindIsOpen(sure))
        #expect(!ReadingArbiter.kindIsOpen(checked))

        #expect(ReadingArbiter.openKind(.serviceInvoice, onDeviceModel: .fiscalReceipt) == .fiscalReceipt)
        #expect(ReadingArbiter.openKind(.serviceInvoice, onDeviceModel: .other) == .serviceInvoice)
        #expect(ReadingArbiter.openKind(.serviceInvoice, onDeviceModel: nil) == .serviceInvoice)
        #expect(ReadingArbiter.kind(unsure, onDeviceModel: .fiscalReceipt).kind == .fiscalReceipt)
        #expect(ReadingArbiter.kind(sure, onDeviceModel: .fiscalReceipt).kind == .serviceInvoice)

        let answer = OnDeviceSchema.json(try GeneratedContent(json: #"{"documentKind":"fiscalReceipt"}"#))
        #expect(ModelAnswerMapper.kind(from: answer) == .fiscalReceipt)
        #expect(ModelAnswerMapper.kind(from: OnDeviceSchema.json(try GeneratedContent(json: #"{"documentKind":"spaceship"}"#))) == nil)
    }

    final class RecordingModel: CaptureSemanticExtracting, @unchecked Sendable {
        let tier: CaptureTier = .onDeviceModel
        private(set) var inputs: [SemanticInput] = []
        func availability() -> CaptureModelAvailability { .available }
        func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
            inputs.append(input)
            return SemanticExtraction(kind: nil, fields: [])
        }
    }

    @Test("The engine tells the model whether the kind is still open", arguments: [
        "Document\nceva scris de mână",
        CaptureEngineTests.invoiceText,
    ])
    func engineSaysWhetherTheKindIsOpen(text: String) async throws {
        let model = RecordingModel()
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text), normalizer: nil,
                                   onDeviceModel: model, cloudModel: nil, store: nil)
        _ = try await engine.capture(CaptureRequest(.text(text), options: CaptureOptions(storeDocument: false, referenceDate: Self.today.date() ?? Date())))
        let input = try #require(model.inputs.first)
        let analysis = CaptureAnalyzer().analyze(text: text, barcodes: [], referenceDate: Self.today.date() ?? Date())
        let reading = ReadingArbiter.KindReading(kind: analysis.kind, confidence: analysis.kindConfidence, evidence: analysis.kindEvidence)
        #expect(input.kindIsOpen == ReadingArbiter.kindIsOpen(reading))
        #expect(input.kind == analysis.kind)
    }
}
