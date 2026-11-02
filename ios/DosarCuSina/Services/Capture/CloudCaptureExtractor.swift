import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Tier 4: the person's own AI provider, when they tap to read a document with it or,
// when they turned it on, by itself after a weak phone reading. It is a full second
// opinion: it names the kind and reads every field from the page. Whoever answers, the
// request is built from the same field definitions the app reads with, the answer goes
// through the same checks, and `ReadingArbiter` ranks it against the phone's reading.

// MARK: - What is asked

/// How a field's value is written in the answer, and how it is checked.
enum CloudFieldFormat: Hashable, Sendable {
    case text
    case name
    case date
    case personalNumber
    case documentNumber
    case sex
    case country
    case categories
    case money
    case integer
    case lineItems
    case vin
    case plate
    case phone
    /// One of the service keys (`ServiceKind`).
    case serviceKind
    /// The machine-readable zone's lines, checked by their own digits.
    case machineReadableZone
}

/// One field a provider is asked for.
struct CloudField: Hashable, Sendable {
    /// The JSON property: the field key's raw value, or `machineReadableZone`.
    let name: String
    let key: CaptureFieldKey?
    let format: CloudFieldFormat
    let description: String
}

/// What a provider is asked, as a JSON Schema every provider accepts: what kind of
/// document it is, then every field any kind of document carries, every property listed
/// and required, `null` where nothing is printed. The phone's guess only orders the fields
/// and is the kind assumed when an answer names none; it is never told to the provider,
/// so a wrong guess can't steer its reading.
struct CloudSchema: Sendable {
    /// The phone's guess.
    let kind: CaptureDocumentKind
    let fields: [CloudField]

    static let zoneName = "machineReadableZone"
    static let kindName = "documentKind"

    init(kind: CaptureDocumentKind) {
        self.kind = kind
        var fields: [CloudField] = []
        for each in [kind] + CaptureDocumentKind.allCases.filter({ $0 != kind }) {
            for field in Self.fields(of: each) where !fields.contains(where: { $0.name == field.name }) {
                fields.append(field)
            }
        }
        self.fields = fields
    }

    /// The fields one kind of document carries.
    private static func fields(of kind: CaptureDocumentKind) -> [CloudField] {
        if kind.isIdentityDocument { return identityFields(kind) }
        return kind.expectedKeys.map { key in
            let format = format(of: key)
            return CloudField(name: key.rawValue, key: key, format: format, description: description(of: key, format: format))
        }
    }

    /// An identity document's fields, from its templates: the printed labels say where
    /// each value is, the formats how it's written.
    private static func identityFields(_ kind: CaptureDocumentKind) -> [CloudField] {
        var fields: [CloudField] = []
        func add(_ key: CaptureFieldKey, _ format: CloudFieldFormat, labels: [LabelWording]) {
            guard !fields.contains(where: { $0.key == key }) else { return }
            let printed = labels.compactMap { wording -> String? in
                switch wording {
                case .words(let words): "\"\(words)\""
                case .numbered(let number): "field \(number)."
                }
            }.prefix(2).joined(separator: " or ")
            let base = description(of: key, format: format)
            fields.append(CloudField(name: key.rawValue, key: key, format: format, description: printed.isEmpty ? base : base + " Printed at \(printed)."))
        }
        let templates = IdentityTemplates.all.filter { $0.kind == kind }
        for template in templates {
            for field in template.fields {
                switch field.format {
                case .name: add(field.key, .name, labels: field.labels)
                case .personalNumber: add(field.key, .personalNumber, labels: field.labels)
                case .documentNumber: add(field.key, .documentNumber, labels: field.labels)
                case .date: add(field.key, .date, labels: field.labels)
                case .dateRange(let start):
                    add(start, .date, labels: field.labels)
                    add(field.key, .date, labels: field.labels)
                case .sex: add(field.key, .sex, labels: field.labels)
                case .country: add(field.key, .country, labels: field.labels)
                case .text: add(field.key, .text, labels: field.labels)
                case .categories: add(field.key, .categories, labels: field.labels)
                }
            }
        }
        if templates.contains(where: { !$0.machineReadableFormats.isEmpty }) {
            fields.append(CloudField(name: zoneName, key: nil, format: .machineReadableZone,
                                     description: "Each line of the machine-readable zone at the bottom, exactly as printed, every < included. Empty when there is none."))
        }
        return fields
    }

    static func format(of key: CaptureFieldKey) -> CloudFieldFormat {
        switch key {
        case .issueDate, .startDate, .expiryDate, .dueDate, .purchaseDate, .warrantyUntil, .nextDoseDate, .firstRegistrationDate, .birthDate,
             .minimumPeriodEnd: .date
        case .total, .purchasePrice, .monthlyPrice: .money
        case .warrantyMonths, .odometer, .meterIndex, .minimumMonths: .integer
        case .serviceKind: .serviceKind
        case .lineItems: .lineItems
        case .vin: .vin
        case .licensePlate: .plate
        case .claimsPhone, .providerPhone, .phoneNumber: .phone
        case .personalNumber: .personalNumber
        default: .text
        }
    }

    static func description(of key: CaptureFieldKey, format: CloudFieldFormat) -> String {
        let what: String = switch key {
        case .provider: "The company, clinic or authority that issued the document, as printed (not the customer)."
        case .retailer: "The shop that sold the product, as printed."
        case .policyNumber: "The insurance policy series and number."
        case .invoiceNumber: "The invoice series and number."
        case .documentNumber: "The document number."
        case .issueDate: "The date of issue."
        case .startDate: "The first day of validity, coverage or of the contract."
        case .expiryDate: "The last day of validity."
        case .dueDate: "The payment due date."
        case .purchaseDate: "The date of purchase."
        case .warrantyUntil: "The last day of the warranty."
        case .nextDoseDate: "The date of the next vaccine or booster."
        case .firstRegistrationDate: "The date of first registration."
        case .birthDate: "The holder's date of birth."
        case .total: "The total amount to pay or paid."
        case .purchasePrice: "The price paid."
        case .claimsPhone: "The phone number for claims or assistance."
        case .licensePlate: "The Romanian registration plate, e.g. B 123 ABC."
        case .vin: "The 17-character vehicle identification number."
        case .make: "The vehicle make."
        case .model: "The vehicle model."
        case .odometer: "The odometer reading in kilometres."
        case .clientCode: "The client code."
        case .contractNumber: "The contract's number (or the addendum's), as printed."
        case .serviceKind: "What the service is: gas, electricity, water, fixed internet or TV, a mobile phone plan, or something else."
        case .phoneNumber: "The customer's own mobile phone number the plan is for (not the provider's support line)."
        case .minimumMonths: "The minimum contract period in months (perioada minimă), e.g. 24."
        case .minimumPeriodEnd: "The last day of the minimum contract period."
        case .monthlyPrice: "The monthly price of the subscription or plan."
        case .podCode: "The POD code of the consumption point."
        case .clcCode: "The CLC code of the consumption point."
        case .meterIndex: "The meter reading."
        case .productName: "The product bought."
        case .serialNumber: "The product's serial number or IMEI."
        case .warrantyMonths: "The warranty length in months."
        case .petName: "The animal's name."
        case .microchip: "The 15-digit microchip number."
        case .vaccineName: "The vaccine given."
        case .bonusMalusClass: "The bonus-malus class."
        case .lineItems: "Each part, service or labour line with its amount."
        case .surname: "The holder's surname."
        case .givenNames: "The holder's given names."
        case .personalNumber: "The holder's personal numeric code (CNP), 13 digits."
        case .sex: "The holder's sex."
        case .nationality: "The nationality, as a three-letter code when printed so."
        case .issuer: "The issuing authority."
        case .licenceCategories: "The driving licence categories."
        default: "As printed."
        }
        let how: String = switch format {
        case .date: " As YYYY-MM-DD."
        case .sex: " M or F."
        case .personalNumber: " Digits only."
        case .categories: " Separated by commas, e.g. A, B, C."
        case .money: " Amount with a dot for decimals; currency as RON, EUR or USD."
        default: ""
        }
        return what + how
    }

    /// The fields as a JSON Schema: strict, so every provider answers in one shape.
    var json: JSONValue {
        let kinds = CaptureDocumentKind.allCases.map { "\($0.rawValue) (\(Self.documentName($0)))" }.joined(separator: ", ")
        var properties: [String: JSONValue] = [
            Self.kindName: [
                "type": "string",
                "enum": .array(CaptureDocumentKind.allCases.map { .string($0.rawValue) }),
                "description": .string("What the document is: \(kinds)."),
            ],
        ]
        for field in fields {
            properties[field.name] = Self.schema(for: field)
        }
        return .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array([.string(Self.kindName)] + fields.map { .string($0.name) }),
            "additionalProperties": false,
        ])
    }

    private static func schema(for field: CloudField) -> JSONValue {
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

    static func documentName(_ kind: CaptureDocumentKind) -> String {
        switch kind {
        case .passport: "passport data page"
        case .identityCard: "identity card"
        case .drivingLicence: "EU driving licence"
        case .vehicleRegistration: "vehicle registration certificate"
        case .rcaPolicy: "compulsory motor insurance (RCA) policy"
        case .insurancePolicy: "insurance policy"
        case .utilityInvoice: "utility, internet, TV or phone bill"
        case .contract: "contract or addendum for gas, electricity, water, internet, TV or a mobile plan"
        case .serviceInvoice: "car service invoice"
        case .fiscalReceipt: "fiscal receipt"
        case .warrantyCertificate: "warranty certificate"
        case .itpReport: "periodic technical inspection (ITP) report"
        case .veterinaryRecord: "veterinary record"
        case .medicalResult: "medical test result"
        case .other: "household document"
        }
    }
}

// MARK: - What is kept

/// Turns a provider's answer into its kind and fields, the same way whoever answered.
///
/// Every value it read is kept: what it is worth decides only whether the review marks
/// it. A value passing its own check (a CNP's control digit, a VIN's check digit, the
/// machine-readable zone's check digits) is certain; one that agrees with what the phone
/// recognised, or a date inside its plausibility window, needs no look; anything else is
/// marked "Verifică". Being missing from the phone's text is never a reason to drop or
/// demote it: the phone may have misread. `ReadingArbiter` ranks it against the phone's.
enum CloudAnswerMapper {

    /// A value proven by its own check digits.
    static let checked = 0.95
    /// A value the phone's recognised text agrees with, or a date inside its window.
    static let grounded = 0.8
    /// A value only the model saw: kept, marked "Verifică".
    static let candidate = 0.5

    /// The kind the answer names, if it names one.
    static func kind(from answer: JSONValue) -> CaptureDocumentKind? {
        answer[CloudSchema.kindName]?.string.flatMap(CaptureDocumentKind.init(rawValue:))
    }

    static func fields(from answer: JSONValue, schema: CloudSchema, recognizedText: String, today: CaptureDay,
                       resolver: any CaptureComponentResolving) -> [CaptureField] {
        // Dates and the holder follow the kind the provider saw.
        let kind = Self.kind(from: answer) ?? schema.kind
        let compactText = ModelAnswerMapper.compact(recognizedText)
        let printed = CaptureText(recognizedText)
        var fields: [CaptureField] = []
        func add(_ key: CaptureFieldKey, _ value: CaptureValue, _ confidence: Double, source: String? = nil) {
            guard !fields.contains(where: { $0.key == key }) else { return }
            fields.append(CaptureField(key: key, value: value, confidence: confidence, sourceText: source, tier: .cloudModel))
        }
        func groundedText(_ value: String) -> Double {
            let compact = ModelAnswerMapper.compact(value)
            return !compact.isEmpty && compactText.contains(compact) ? grounded : candidate
        }

        // The zone first: when its check digits pass, its values are the ones kept.
        if let zone = schema.fields.first(where: { $0.format == .machineReadableZone }),
           let lines = answer[zone.name]?.array?.compactMap(\.string), !lines.isEmpty,
           let mrz = MRZParser.parse(text: lines.joined(separator: "\n"), referenceDate: today.date() ?? Date()),
           mrz.allChecksValid {
            for field in CaptureAnalyzer.machineReadableFields(mrz) {
                add(field.key, field.value, field.confidence, source: CaptureField.machineReadableSource)
            }
        }

        for field in schema.fields {
            guard let key = field.key, let raw = answer[field.name], raw != .null else { continue }
            switch field.format {
            case .machineReadableZone:
                continue
            case .date:
                guard let text = raw.string, let day = ModelAnswerMapper.isoDay(text) else { continue }
                let window = CaptureConsistency.window(for: key, kind: kind, today: today)
                let inText = RomanianFieldExtractor.allDates(in: printed, window: window).contains { $0.day == day }
                let hasWindow = CaptureConsistency.rules(for: kind).contains { rule in
                    if case .within(key, _, _) = rule { return true }
                    return false
                }
                let inWindow = hasWindow && CaptureConsistency.isPlausible(day, for: key, kind: kind, today: today)
                add(key, .day(day), inText || inWindow ? grounded : candidate)
            case .personalNumber:
                guard let digits = raw.string?.filter(\.isNumber), digits.count == 13 else { continue }
                add(key, .text(digits), RomanianFieldExtractor.isValidCNP(digits) ? checked : candidate)
            case .vin:
                guard let vin = raw.string?.uppercased().filter({ $0.isLetter || $0.isNumber }), vin.count == 17 else { continue }
                add(key, .text(vin), RomanianFieldExtractor.vinChecksumValid(vin) ? checked : groundedText(vin))
            case .sex:
                guard let letter = raw.string?.uppercased().first(where: { $0 == "M" || $0 == "F" }) else { continue }
                add(key, .text(String(letter)), grounded)
            case .name:
                guard let text = raw.string, let name = RomanianFieldExtractor.personName(text.uppercased()) else { continue }
                add(key, .text(name), groundedText(name))
            case .categories:
                guard let text = raw.string, let parsed = IdentityDocumentReader.parse(text, as: .categories) else { continue }
                add(key, parsed.value, groundedText(text))
            case .money:
                guard let amount = raw["amount"]?.double, amount > 0, let decimal = Decimal(string: String(amount)) else { continue }
                let currency = ModelAnswerMapper.normalizedCurrency(raw["currency"]?.string)
                let amounts = Set(printed.folded.flatMap { RomanianFieldExtractor.amounts(inLine: $0).map(\.amount) })
                add(key, .money(CaptureMoney(amount: decimal, currencyCode: currency)), amounts.contains(decimal) ? grounded : candidate)
            case .integer:
                guard let number = raw.double, number >= 0, number < 10_000_000 else { continue }
                let value = Int(number)
                if key == .minimumMonths, !ContractReader.plausibleMonths.contains(value) { continue }
                let typed: CaptureValue = key == .odometer ? .metric(value: Decimal(value), unit: "km") : .number(Decimal(value))
                add(key, typed, compactText.contains(String(value)) ? grounded : candidate)
            case .lineItems:
                let currency = ModelAnswerMapper.normalizedCurrency(nil)
                let items = (raw.array ?? []).compactMap { item -> CaptureLineItem? in
                    guard let description = item["description"]?.string?.trimmingCharacters(in: .whitespaces), !description.isEmpty else { return nil }
                    let money = item["amount"]?.double.flatMap { Decimal(string: String($0)) }.map { CaptureMoney(amount: $0, currencyCode: currency) }
                    return CaptureLineItem(description: description, amount: money, componentKey: resolver.componentKey(for: description))
                }
                guard !items.isEmpty else { continue }
                let allPrinted = items.allSatisfy { compactText.contains(ModelAnswerMapper.compact($0.description)) }
                add(key, .lineItems(items), allPrinted ? grounded : candidate)
            case .serviceKind:
                // A judgement about the page, not text copied from it: kept when it names a known service.
                guard let service = raw.string, ServiceKind.all.contains(service) else { continue }
                add(key, .text(service), grounded)
            case .text, .documentNumber, .country, .plate, .phone:
                guard let text = raw.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.lowercased() != "null" else { continue }
                var value = field.format == .documentNumber || field.format == .plate ? text.uppercased() : text
                if key == .phoneNumber {
                    // The person's own number, written the way the phone reads it: "0700 000 000".
                    guard ContractReader.isMobileNumber(value) else { continue }
                    value = ContractReader.displayPhone(value)
                }
                add(key, .text(value), groundedText(value))
            }
        }

        // The holder, as the identity readers name them.
        if kind.isIdentityDocument, !fields.contains(where: { $0.key == .holderName }),
           let surname = fields.first(where: { $0.key == .surname }) {
            let given = fields.first { $0.key == .givenNames }
            let full = [given?.value.text, surname.value.text].compactMap { $0 }.joined(separator: " ")
            add(.holderName, .text(full), min(surname.confidence, given?.confidence ?? surname.confidence))
        }
        return fields
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
        let answer = try await client.read(CloudReadingRequest(instructions: schema.instructions, schema: schema.json, jpeg: jpeg), config: config)
        let fields = CloudAnswerMapper.fields(from: answer, schema: schema, recognizedText: input.text, today: input.today, resolver: resolver)
        return SemanticExtraction(kind: CloudAnswerMapper.kind(from: answer), fields: fields)
    }

    /// The page as a JPEG, no larger than `sentLongEdge`.
    static func jpeg(_ image: CGImage) -> Data? {
        let long = max(image.width, image.height)
        var source = image
        if long > sentLongEdge {
            let scale = Double(sentLongEdge) / Double(long)
            let width = Int(Double(image.width) * scale), height = Int(Double(image.height) * scale)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return nil }
            source = scaled
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, source, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
