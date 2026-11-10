import CoreGraphics
import Foundation
import FoundationModels

// MARK: - Protocol

/// What a language-model tier receives: the recognized text, the first page, and what the
/// deterministic tiers already concluded.
public struct SemanticInput: Sendable {
    /// The text a model may read, the only text any tier puts in front of one: what the phone
    /// recognised with its card numbers masked by the rule capture's result goes through
    /// (`CaptureCardMask`): strictly when the phone takes the page for a bank card, else
    /// keeping whole what the phone read for a field whose type tells it apart (a microchip).
    /// A card's last four digits, its network, expiry and bank stay, so its questions can be
    /// answered.
    public let text: String
    /// The text as recognised, only for checking that an answer is printed on the page
    /// (`ModelAnswerMapper`); never put in a question.
    public let recognizedText: String
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
        self.text = CaptureCardMask(kind: kind, read: knownFields.map { (key: $0.key, value: $0.value) }).text(text)
        self.recognizedText = text
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
/// It reads the text the phone recognised with its card numbers masked (`SemanticInput.text`),
/// never the picture, one question per session, so
/// no question carries another's exchange in the model's small context:
/// 1. **What the document is**, asked only while the kind is still open
///    (`ReadingArbiter.kindIsOpen`: the classifier is unsure and nothing deterministic backs
///    it); otherwise the phone's kind stands and the question would change nothing.
/// 2. **The kind's facts**: exactly the fields its profile lists (`ModelQuestions`), as a
///    generation schema built for that kind (`OnDeviceSchema`), answered through the same
///    mapper and checks as the AI provider's (`ModelAnswerMapper`), each value kept only
///    when it is printed in the text.
///
/// Each question carries as much of the text as its budget leaves (`OnDevicePromptBudget`:
/// the model's context, less the instructions, the schema, the question and room for the
/// answer). A question with no room for text isn't asked; one that still runs out of room
/// is asked once more with half the text, and then gives up calmly: the phone's reading stands.
public struct OnDeviceModelExtractor: CaptureSemanticExtracting {

    public let tier: CaptureTier = .onDeviceModel
    let resolver: any CaptureComponentResolving

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
        let model = SystemLanguageModel.default

        // 1. What the document is, only while the model's view can still change it.
        var named: CaptureDocumentKind?
        if input.kindIsOpen {
            let schema = try OnDeviceSchema.kindQuestion()
            let question = { (text: String) in Self.kindPrompt(text: text, guess: input.kind) }
            if let answer = try await ask(model, question, about: input.text, schema: schema,
                                          answerTokens: OnDevicePromptBudget.kindAnswerTokens) {
                named = ModelAnswerMapper.kind(from: answer)
            }
        }
        let kind = input.kindIsOpen ? ReadingArbiter.openKind(input.kind, onDeviceModel: named) : input.kind

        // 2. The facts that kind carries, and nothing else, in a session of their own.
        let questions = ModelQuestions(kind: kind, reader: .text)
        guard !questions.fields.isEmpty else { return SemanticExtraction(kind: named, fields: []) }
        let schema = try OnDeviceSchema.facts(questions)
        let question = { (text: String) in Self.factsPrompt(kind, text: text) }
        guard let answer = try await ask(model, question, about: input.text, schema: schema,
                                         answerTokens: OnDevicePromptBudget.answerTokens(for: questions)) else {
            return SemanticExtraction(kind: named, fields: [])
        }
        let fields = ModelAnswerMapper.fields(from: answer, asked: questions,
                                              recognizedText: input.recognizedText, today: input.today, resolver: resolver)
        return SemanticExtraction(kind: named, fields: fields)
    }

    /// One question in a fresh session, with as much of `text` as its budget leaves. Nil when
    /// there is no room for any text at all.
    private func ask(_ model: SystemLanguageModel, _ question: (String) -> String, about text: String, schema: GenerationSchema,
                     answerTokens: Int) async throws -> JSONValue? {
        let counter = OnDeviceTokenCounter(model: model)
        let fixed = try await counter.tokens(instructions: Self.instructions, schema: schema, question: question(""))
        let budget = OnDevicePromptBudget(contextSize: model.contextSize, questionTokens: fixed, answerTokens: answerTokens)
        var length = try await counter.characters(of: text, fitting: budget)
        guard length > 0 else { return nil }
        let options = GenerationOptions(samplingMode: .greedy)
        var retried = false
        while true {
            try Task.checkCancellation()
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            do {
                let answer = try await session.respond(to: question(OnDevicePromptBudget.cut(text, to: length)), schema: schema, options: options)
                return OnDeviceSchema.json(answer.content)
            } catch where !retried && Self.ranOutOfRoom(error) && length > OnDevicePromptBudget.retryBelow {
                // The count was short (or only estimated): once more, with half the text.
                retried = true
                length = OnDevicePromptBudget.retryLength(after: length)
            }
        }
    }

    /// Whether the model stopped because the question and its answer didn't fit its context.
    static func ranOutOfRoom(_ error: any Error) -> Bool {
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError, case .contextSizeExceeded = error { return true }
        if let error = error as? LanguageModelSession.GenerationError, case .exceededContextWindowSize = error { return true }
        return false
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

    /// The facts question, with the text it is about: each question has a session of its own.
    static func factsPrompt(_ kind: CaptureDocumentKind, text: String) -> String {
        textBlock(text) + "\nThis is a \(kind.profile.modelDescription). Fill in each field it prints, exactly as printed."
    }
}

// MARK: - The prompt's budget

/// How much of a document's text fits one question to Apple's on-device model: its context
/// (`SystemLanguageModel.contextSize`), less a margin, what the question takes besides the
/// text (the instructions, the schema and the question's own words) and room for the answer.
/// Pure arithmetic, so it is pinned by tests; the extractor fills it with counts from the
/// model when the system can count (iOS 26.4 and later), else with the estimate here.
struct OnDevicePromptBudget: Equatable, Sendable {
    /// The model's context, in tokens.
    let contextSize: Int
    /// What the question takes besides the document's text.
    let questionTokens: Int
    /// Room kept for the answer.
    let answerTokens: Int

    /// Kept free for what a count can't see (the transcript's own markers) and an estimate that's short.
    static let marginShare = 0.1
    /// Below this, too little text is left to read anything from, and the question isn't asked.
    static let minimumTextTokens = 128
    /// The most text a question carries, whatever room there is: the first pages hold what
    /// matters, and a long prompt is slow on the phone.
    static let maxCharacters = 6_000
    /// Characters per token when the system can't count: Romanian with its diacritics,
    /// digits and recognition errors takes about three; two and a half keeps it under.
    static let estimatedCharactersPerToken = 2.5
    /// Room for one field's answer, its name and its value (an address is the longest).
    static let tokensPerField = 40
    /// Room for one line of an invoice: what it is for and its amount.
    static let tokensPerLine = 24
    /// The answer's own braces and separators.
    static let answerOverhead = 16
    /// Room for the kind question's answer: one of the app's kinds.
    static let kindAnswerTokens = 32
    /// A question that ran out of room with less text than this isn't asked again.
    static let retryBelow = 400

    /// Tokens left for the document's text; never below zero.
    var textTokens: Int {
        let margin = Int((Double(contextSize) * Self.marginShare).rounded(.up))
        return max(0, contextSize - margin - questionTokens - answerTokens)
    }

    /// Whether there is room for enough text to ask at all.
    var fits: Bool { textTokens >= Self.minimumTextTokens }

    /// How many characters of text fit, at `charactersPerToken`: none when it doesn't fit,
    /// never more than `maxCharacters`.
    func characters(charactersPerToken: Double = estimatedCharactersPerToken) -> Int {
        guard fits, charactersPerToken > 0 else { return 0 }
        return min(Self.maxCharacters, Int((Double(textTokens) * charactersPerToken).rounded(.down)))
    }

    /// How many characters fit, from a count of `measuredTokens` for `measuredCharacters` of
    /// the text: all of them when they fit, else a share in proportion, 5% under it.
    func characters(measuredCharacters: Int, measuredTokens: Int) -> Int {
        guard fits, measuredCharacters > 0 else { return 0 }
        guard measuredTokens > textTokens else { return min(measuredCharacters, Self.maxCharacters) }
        let share = Double(textTokens) / Double(measuredTokens) * 0.95
        return min(Self.maxCharacters, Int((Double(measuredCharacters) * share).rounded(.down)))
    }

    /// The room an answer to `questions` is kept: each field, and each line a list of lines can hold.
    static func answerTokens(for questions: ModelQuestions) -> Int {
        answerOverhead + questions.fields.reduce(0) { total, field in
            total + (field.format == .lineItems ? OnDeviceSchema.maximumLines * tokensPerLine : tokensPerField)
        }
    }

    /// An estimate of what `characters` of text take, rounded up.
    static func estimatedTokens(characters: Int) -> Int {
        Int((Double(characters) / estimatedCharactersPerToken).rounded(.up))
    }

    /// The length asked with after running out of room: half.
    static func retryLength(after length: Int) -> Int { length / 2 }

    /// The first `length` characters of `text`, ending at the last line break inside them
    /// when one is near the end, so a value is never cut in half.
    static func cut(_ text: String, to length: Int) -> String {
        guard text.count > length else { return text }
        let head = text.prefix(length)
        if let lineEnd = head.lastIndex(of: "\n"), head.distance(from: lineEnd, to: head.endIndex) <= 200 {
            return String(head[..<lineEnd])
        }
        return String(head)
    }
}

/// Counts what a question takes with the model's own tokenizer where the system offers it
/// (iOS 26.4 and later), else estimates it (`OnDevicePromptBudget.estimatedCharactersPerToken`,
/// and the schema by its JSON encoding, which is longer than what the model is shown).
struct OnDeviceTokenCounter {
    let model: SystemLanguageModel

    /// The instructions, the schema and the question's own words.
    func tokens(instructions: String, schema: GenerationSchema, question: String) async throws -> Int {
        if #available(iOS 26.4, macOS 26.4, *) {
            return try await model.tokenCount(for: Instructions(instructions))
                + model.tokenCount(for: schema)
                + model.tokenCount(for: question)
        }
        return Self.estimatedTokens(instructions: instructions, schema: schema, question: question)
    }

    /// The estimate, when the system can't count.
    static func estimatedTokens(instructions: String, schema: GenerationSchema, question: String) -> Int {
        let schemaCharacters = (try? JSONEncoder().encode(schema).count) ?? OnDevicePromptBudget.maxCharacters
        return OnDevicePromptBudget.estimatedTokens(characters: instructions.count + schemaCharacters + question.count)
    }

    /// How many characters of `text` fit `budget`: counted where the system can, else estimated.
    func characters(of text: String, fitting budget: OnDevicePromptBudget) async throws -> Int {
        guard budget.fits else { return 0 }
        let candidate = String(text.prefix(OnDevicePromptBudget.maxCharacters))
        if #available(iOS 26.4, macOS 26.4, *) {
            let measured = try await model.tokenCount(for: candidate)
            return budget.characters(measuredCharacters: candidate.count, measuredTokens: measured)
        }
        return min(candidate.count, budget.characters())
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
