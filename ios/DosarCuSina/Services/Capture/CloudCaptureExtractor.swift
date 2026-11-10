import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Tier 4: the person's own AI provider, when they tap to read a document with it or,
// when they turned it on, by itself after a weak phone reading. It is a full second
// opinion: it names the kind and reads every field from the page. Whoever answers, the
// request is built from the same questions Apple's on-device model is asked
// (`ModelQuestions`), the answer goes through the same mapper and checks
// (`ModelAnswerMapper`), and `ReadingArbiter` ranks it against the phone's reading.

// MARK: - What is asked

/// What a provider is asked, as a JSON Schema every provider accepts: what kind of
/// document it is, then every field any kind of document carries (each kind's own
/// questions, `ModelQuestions`), every property listed and required, `null` where nothing
/// is printed. The phone's guess only orders the fields and is the kind assumed when an
/// answer names none; it is never told to the provider, so a wrong guess can't steer its
/// reading.
struct CloudSchema: Sendable {
    /// Every kind's fields, the phone's guess first, for a reader that sees the page.
    let questions: ModelQuestions

    /// The phone's guess.
    var kind: CaptureDocumentKind { questions.kind }
    var fields: [ModelField] { questions.fields }

    init(kind: CaptureDocumentKind) {
        var fields: [ModelField] = []
        for each in [kind] + CaptureDocumentKind.allCases.filter({ $0 != kind }) {
            for field in ModelQuestions.fields(of: each, reader: .page) where !fields.contains(where: { $0.name == field.name }) {
                fields.append(field)
            }
        }
        questions = ModelQuestions(kind: kind, fields: fields, reader: .page)
    }

    /// The fields as a JSON Schema: strict, so every provider answers in one shape.
    var json: JSONValue {
        var properties: [String: JSONValue] = [
            ModelQuestions.kindName: [
                "type": "string",
                "enum": .array(CaptureDocumentKind.allCases.map { .string($0.rawValue) }),
                "description": .string(ModelQuestions.kindDescription),
            ],
        ]
        for field in fields {
            properties[field.name] = Self.schema(for: field)
        }
        return .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array([.string(ModelQuestions.kindName)] + fields.map { .string($0.name) }),
            "additionalProperties": false,
        ])
    }

    private static func schema(for field: ModelField) -> JSONValue {
        let description = JSONValue.string(field.description)
        switch field.format {
        case .money:
            return [
                "type": ["object", "null"], "description": description,
                "properties": ["amount": ["type": "number"], "currency": ["type": "string"]],
                "required": ["amount", "currency"], "additionalProperties": false,
            ]
        case .integer:
            return ["type": ["integer", "null"], "description": description]
        case .serviceKind:
            return ["type": ["string", "null"], "description": description,
                    "enum": .array(ServiceKind.all.map(JSONValue.string) + [.null])]
        case .coverage:
            return ["type": ["string", "null"], "description": description,
                    "enum": .array(InsuranceCover.all.map(JSONValue.string) + [.null])]
        case .cardNetwork:
            return ["type": ["string", "null"], "description": description,
                    "enum": .array(PaymentCardNetwork.all.map(JSONValue.string) + [.null])]
        case .lineItems:
            return [
                "type": "array", "description": description,
                "items": [
                    "type": "object",
                    "properties": ["description": ["type": "string"], "amount": ["type": ["number", "null"]]],
                    "required": ["description", "amount"], "additionalProperties": false,
                ],
            ]
        case .machineReadableZone:
            return ["type": "array", "description": description, "items": ["type": "string"]]
        default:
            return ["type": ["string", "null"], "description": description]
        }
    }

    /// What every provider is told.
    var instructions: String {
        var text = """
        You read a photo of a Romanian household document. First decide what kind of document it is, from the page itself, \
        and give it as documentKind. Then fill in each field with exactly what is printed on it; fields that don't belong \
        on this kind of document are null. Use null for a field that isn't printed or that you can't read with confidence; \
        never guess or complete a value. Write dates as YYYY-MM-DD. Copy names, numbers and codes character for character.
        """
        if fields.contains(where: { $0.format == .machineReadableZone }) {
            text += " Copy the machine-readable zone line by line, exactly, with every < character."
        }
        return text
    }
}

// MARK: - The tier

/// Reads the first page with the provider the person set up in Settings, with their own
/// key. The page leaves the phone, so the engine calls this only when the person asks, or
/// when they turned on the automatic reading and the phone's reading is weak.
public struct CloudCaptureExtractor: CaptureSemanticExtracting {

    public let tier: CaptureTier = .cloudModel
    let settings: AIProviderSettings
    let client: AIClient
    let resolver: any CaptureComponentResolving

    /// The long edge of the page sent: enough for small print, and a modest upload.
    static let sentLongEdge = 2400

    public init(settings: AIProviderSettings = .standard, client: AIClient = AIClient(), resolver: any CaptureComponentResolving = CatalogComponentResolver()) {
        self.settings = settings
        self.client = client
        self.resolver = resolver
    }

    public func availability() -> CaptureModelAvailability {
        settings.isReady ? .available : .unavailable(AIProviderError.notConfigured.code)
    }

    public func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
        guard let config = settings.current else { throw AIProviderError.notConfigured }
        guard let page = input.firstPage, let jpeg = Self.jpeg(page) else { return SemanticExtraction(kind: nil, fields: []) }
        let schema = CloudSchema(kind: input.kind)
        CaptureLog.engine.info("Reading with \(config.provider.rawValue, privacy: .public), \(schema.fields.count) fields")
        // A capture closed by now sends nothing.
        try Task.checkCancellation()
        let answer = try await client.read(CloudReadingRequest(instructions: schema.instructions, schema: schema.json, jpeg: jpeg), config: config)
        let fields = ModelAnswerMapper.fields(from: answer, asked: schema.questions, recognizedText: input.text, today: input.today, resolver: resolver)
        return SemanticExtraction(kind: ModelAnswerMapper.kind(from: answer), fields: fields)
    }

    /// The page as a JPEG, no larger than `sentLongEdge`.
    static func jpeg(_ image: CGImage) -> Data? {
        guard let source = ImageScaling.scaled(image, toLongEdge: sentLongEdge, .down) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, source, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
