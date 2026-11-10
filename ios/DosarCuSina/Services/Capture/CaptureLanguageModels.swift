import CoreGraphics
import Foundation
import FoundationModels

// MARK: - Protocol

/// What a language-model tier receives: the recognized text, the first page, and what the
/// deterministic tiers already concluded.
public struct SemanticInput: Sendable {
    public let text: String
    public let firstPage: CGImage?
    public let kind: CaptureDocumentKind
    public let knownFields: [CaptureField]
    /// "Today", for checking dates against their plausibility windows.
    public let today: CalendarDay
    /// Whether a model's view of the kind can still change it (`ReadingArbiter.kindIsOpen`).
    /// Apple's model is asked what the document is only then.
    public let kindIsOpen: Bool

    public init(text: String, firstPage: CGImage?, kind: CaptureDocumentKind, knownFields: [CaptureField], today: CalendarDay = CalendarDay(Date()),
                kindIsOpen: Bool = false) {
        self.text = text
        self.firstPage = firstPage
        self.kind = kind
        self.knownFields = knownFields
        self.today = today
        self.kindIsOpen = kindIsOpen
    }
}

public struct SemanticExtraction: Sendable {
    /// The model's view of the document kind, when it's confident enough to offer one.
    public let kind: CaptureDocumentKind?
    public let fields: [CaptureField]
}

public enum CaptureModelAvailability: Sendable, Equatable {
    case available
    /// A short, stable reason code: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`, `noKey`, `unsupportedLanguage`.
    case unavailable(String)
}

/// A language-model tier that reads meaning the patterns can't: who issued it, what was done, which date matters.
public protocol CaptureSemanticExtracting: Sendable {
    var tier: CaptureTier { get }
    func availability() -> CaptureModelAvailability
    func extract(_ input: SemanticInput) async throws -> SemanticExtraction
}

// MARK: - On-device model

/// Apple's on-device language model (iOS 26 and later). Private, offline and free; needs a
/// device with Apple Intelligence turned on. When it isn't available the engine carries on
/// with the deterministic and heuristic tiers and says so in the result.
///
/// It reads the text the phone recognised, never the picture, in one session:
/// 1. **What the document is**, asked only while the kind is still open
///    (`ReadingArbiter.kindIsOpen`: the classifier is unsure and nothing deterministic backs
///    it); otherwise the phone's kind stands and the question would change nothing.
/// 2. **The kind's facts**: exactly the fields its profile lists (`ModelQuestions`), as a
///    generation schema built for that kind (`OnDeviceSchema`), answered through the same
///    mapper and checks as the AI provider's (`ModelAnswerMapper`), each value kept only
///    when it is printed in the text.
public struct OnDeviceModelExtractor: CaptureSemanticExtracting {

    public let tier: CaptureTier = .onDeviceModel
    let resolver: any CaptureComponentResolving
    /// The on-device model's context is small; long documents are cut to their first part.
    static let maxCharacters = 6_000

    public init(resolver: any CaptureComponentResolving = CatalogComponentResolver()) {
        self.resolver = resolver
    }

    public func availability() -> CaptureModelAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("deviceNotEligible")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("appleIntelligenceNotEnabled")
        case .unavailable(.modelNotReady):
            return .unavailable("modelNotReady")
        case .unavailable:
            return .unavailable("unavailable")
        }
    }

    public func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
        let session = LanguageModelSession(instructions: Self.instructions)
        let text = String(input.text.prefix(Self.maxCharacters))
        let options = GenerationOptions(samplingMode: .greedy)

        // 1. What the document is, only while the model's view can still change it.
        var named: CaptureDocumentKind?
        if input.kindIsOpen {
            let schema = try OnDeviceSchema.kindQuestion()
            try Task.checkCancellation()
            let answer = try await session.respond(to: Self.kindPrompt(text: text, guess: input.kind), schema: schema, options: options)
            named = ModelAnswerMapper.kind(from: OnDeviceSchema.json(answer.content))
        }
        let kind = input.kindIsOpen ? ReadingArbiter.openKind(input.kind, onDeviceModel: named) : input.kind

        // 2. The facts that kind carries, and nothing else.
        let questions = ModelQuestions(kind: kind, reader: .text)
        guard !questions.fields.isEmpty else { return SemanticExtraction(kind: named, fields: []) }
        let schema = try OnDeviceSchema.facts(questions)
        // The text was given with the kind question; otherwise it comes with this one.
        let prompt = input.kindIsOpen ? Self.factsPrompt(kind) : Self.textBlock(text) + "\n" + Self.factsPrompt(kind)
        try Task.checkCancellation()
        let answer = try await session.respond(to: prompt, schema: schema, options: options)
        let fields = ModelAnswerMapper.fields(from: OnDeviceSchema.json(answer.content), asked: questions,
                                              recognizedText: input.text, today: input.today, resolver: resolver)
        return SemanticExtraction(kind: named, fields: fields)
    }

    static let instructions = """
    You read the text recognised from a photo or PDF of a Romanian household document; it may contain recognition errors. \
    Answer only with what is printed in it. Never invent, guess or complete a value: leave a field out when it isn't in the text. \
    Write dates as YYYY-MM-DD. Write amounts with a dot as the decimal separator and no thousands separator. \
    Copy names, numbers and codes character for character.
    """

    static func textBlock(_ text: String) -> String {
        """
        Document text:
        ---
        \(text)
        ---
        """
    }

    static func kindPrompt(text: String, guess: CaptureDocumentKind) -> String {
        textBlock(text) + "\nWhat kind of document is this? Our first guess is \"\(guess.rawValue)\". Correct it if it's wrong."
    }

    static func factsPrompt(_ kind: CaptureDocumentKind) -> String {
        "This is a \(kind.profile.modelDescription). Fill in each field it prints, exactly as printed."
    }
}

// MARK: - The generation schema

/// The questions as Foundation Models' generation schema, built for each kind at the
/// moment it is asked: one optional property per field, its type from the field's format,
/// its description the shared one (`ModelQuestions`). Choices (a service, a cover, a card
/// network, the kind) are the app's own keys, so the answer can only name one of them.
enum OnDeviceSchema {

    /// The kind question: one of the app's kinds, each described by its profile.
    static func kindQuestion() throws -> GenerationSchema {
        let kinds = DynamicGenerationSchema(name: "DocumentKindChoice", anyOf: CaptureDocumentKind.allCases.map(\.rawValue))
        let root = DynamicGenerationSchema(name: "DocumentKind", description: "What a Romanian household document is", properties: [
            .init(name: ModelQuestions.kindName, description: ModelQuestions.kindDescription, schema: kinds),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The facts of one kind, exactly its questions.
    static func facts(_ questions: ModelQuestions) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(
            name: "DocumentFacts",
            description: "Facts printed on a \(questions.kind.profile.modelDescription)",
            properties: questions.fields.map { field in
                DynamicGenerationSchema.Property(name: field.name, description: field.description, schema: value(of: field), isOptional: true)
            }
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The shape of one field's value, from its format. Nested shapes are named after their
    /// field, so no two share a name.
    static func value(of field: ModelField) -> DynamicGenerationSchema {
        switch field.format {
        case .date:
            return DynamicGenerationSchema(type: String.self, guides: [.pattern(#/\d{4}-\d{2}-\d{2}/#)])
        case .integer:
            return DynamicGenerationSchema(type: Int.self)
        case .money:
            return DynamicGenerationSchema(name: "\(field.name)Amount", properties: [
                .init(name: "amount", schema: DynamicGenerationSchema(type: Double.self)),
                .init(name: "currency", schema: DynamicGenerationSchema(name: "\(field.name)Currency", anyOf: ModelQuestions.currencies)),
            ])
        case .sex:
            return DynamicGenerationSchema(name: "\(field.name)Choice", anyOf: ["M", "F"])
        case .serviceKind:
            return DynamicGenerationSchema(name: "\(field.name)Choice", anyOf: ServiceKind.all)
        case .coverage:
            return DynamicGenerationSchema(name: "\(field.name)Choice", anyOf: InsuranceCover.all)
        case .cardNetwork:
            return DynamicGenerationSchema(name: "\(field.name)Choice", anyOf: PaymentCardNetwork.all)
        case .lineItems:
            let line = DynamicGenerationSchema(name: "\(field.name)Line", properties: [
                .init(name: "description", description: "What the line is for, as printed", schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "amount", description: "The line's amount", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            ])
            return DynamicGenerationSchema(arrayOf: line, maximumElements: maximumLines)
        case .machineReadableZone:
            return DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self))
        case .text, .name, .personalNumber, .documentNumber, .country, .categories, .meterIndex, .vin, .plate, .phone, .cardLastFour:
            return DynamicGenerationSchema(type: String.self)
        }
    }

    /// The most lines an invoice is read for.
    static let maximumLines = 30

    /// An answer as the plain value every model's answer is read from (`ModelAnswerMapper`).
    static func json(_ content: GeneratedContent) -> JSONValue {
        switch content.kind {
        case .null: .null
        case .bool(let value): .bool(value)
        case .number(let value): .number(value)
        case .string(let value): .string(value)
        case .array(let items): .array(items.map(json))
        case .structure(let properties, _): .object(properties.mapValues(json))
        @unknown default: .null
        }
    }
}
