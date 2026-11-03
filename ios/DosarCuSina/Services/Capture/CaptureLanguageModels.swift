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
    public let today: CaptureDay

    public init(text: String, firstPage: CGImage?, kind: CaptureDocumentKind, knownFields: [CaptureField], today: CaptureDay = CaptureDay(date: Date())) {
        self.text = text
        self.firstPage = firstPage
        self.kind = kind
        self.knownFields = knownFields
        self.today = today
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

// MARK: - Shared mapping

/// Turns the plain answers a model gives into typed fields, dropping anything that isn't
/// grounded in the recognized text.
///
/// Models can invent plausible policy numbers or plates. An identifier is kept only if its
/// letters and digits appear in the text; dates and amounts must parse.
enum ModelAnswerMapper {
    struct Answers {
        var kind: String?
        var issuer: String?
        var documentNumber: String?
        var issueDate: String?
        var expiryDate: String?
        var dueDate: String?
        var startDate: String?
        var totalAmount: String?
        var currency: String?
        var policyNumber: String?
        var claimsPhone: String?
        var licensePlate: String?
        var vin: String?
        var productName: String?
        var serialNumber: String?
        var purchaseDate: String?
        var warrantyMonths: Int?
        var odometerKm: Int?
        var nextDoseDate: String?
        var lineItems: [(description: String, amount: String?)] = []
    }

    static func fields(from answers: Answers, sourceText: String, tier: CaptureTier, resolver: any CaptureComponentResolving) -> SemanticExtraction {
        let compactSource = compact(sourceText)
        var fields: [CaptureField] = []
        let confidence = 0.72

        func addText(_ key: CaptureFieldKey, _ value: String?, mustBeGrounded: Bool) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.lowercased() != "null" else { return }
            if mustBeGrounded, !compactSource.contains(compact(value)) { return }
            fields.append(CaptureField(key: key, value: .text(value), confidence: confidence, sourceText: nil, tier: tier))
        }
        func addDay(_ key: CaptureFieldKey, _ value: String?) {
            guard let value, let day = isoDay(value) else { return }
            fields.append(CaptureField(key: key, value: .day(day), confidence: confidence - 0.07, sourceText: nil, tier: tier))
        }

        addText(.provider, answers.issuer, mustBeGrounded: false)
        addText(.documentNumber, answers.documentNumber, mustBeGrounded: true)
        addText(.policyNumber, answers.policyNumber, mustBeGrounded: true)
        addText(.claimsPhone, answers.claimsPhone, mustBeGrounded: true)
        addText(.licensePlate, answers.licensePlate.map { $0.uppercased() }, mustBeGrounded: true)
        if let vin = answers.vin?.uppercased().filter({ !$0.isWhitespace }), vin.count == 17 {
            addText(.vin, vin, mustBeGrounded: true)
        }
        addText(.productName, answers.productName, mustBeGrounded: false)
        addText(.serialNumber, answers.serialNumber, mustBeGrounded: true)
        addDay(.issueDate, answers.issueDate)
        addDay(.expiryDate, answers.expiryDate)
        addDay(.dueDate, answers.dueDate)
        addDay(.startDate, answers.startDate)
        addDay(.purchaseDate, answers.purchaseDate)
        addDay(.nextDoseDate, answers.nextDoseDate)

        let currency = normalizedCurrency(answers.currency)
        let printedAmounts = Set(CaptureText(sourceText).folded.flatMap { RomanianFieldExtractor.amounts(inLine: $0).map(\.amount) })
        if let raw = answers.totalAmount, let amount = RomanianFieldExtractor.amount(raw)?.value, amount > 0,
           printedAmounts.contains(amount) {
            fields.append(CaptureField(key: .total, value: .money(CaptureMoney(amount: amount, currencyCode: currency)), confidence: confidence, sourceText: nil, tier: tier))
        }
        if let months = answers.warrantyMonths, (1...240).contains(months) {
            fields.append(CaptureField(key: .warrantyMonths, value: .number(Decimal(months)), confidence: confidence - 0.05, sourceText: nil, tier: tier))
        }
        if let km = answers.odometerKm, km > 0, compactSource.contains(String(km)) {
            fields.append(CaptureField(key: .odometer, value: .metric(value: Decimal(km), unit: "km"), confidence: confidence, sourceText: nil, tier: tier))
        }
        let items = answers.lineItems.compactMap { item -> CaptureLineItem? in
            let description = item.description.trimmingCharacters(in: .whitespaces)
            guard !description.isEmpty else { return nil }
            let money = item.amount.flatMap { RomanianFieldExtractor.amount($0)?.value }.map { CaptureMoney(amount: $0, currencyCode: currency) }
            return CaptureLineItem(description: description, amount: money, componentKey: resolver.componentKey(for: description))
        }
        if !items.isEmpty {
            fields.append(CaptureField(key: .lineItems, value: .lineItems(items), confidence: confidence - 0.05, sourceText: nil, tier: tier))
        }

        let kind = answers.kind.flatMap(CaptureDocumentKind.init(rawValue:)).flatMap { $0 == .other ? nil : $0 }
        return SemanticExtraction(kind: kind, fields: fields)
    }

    /// Letters and digits only, uppercased, so "B-123 ABC" and "B 123 ABC" compare equal.
    static func compact(_ text: String) -> String {
        CaptureText.fold(text).uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isoDay(_ value: String) -> CaptureDay? {
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return CaptureDay(year: parts[0], month: parts[1], day: parts[2])
    }

    static func normalizedCurrency(_ value: String?) -> String {
        switch CaptureText.fold(value ?? "") {
        case "eur", "euro", "€": "EUR"
        case "usd", "$": "USD"
        default: "RON"
        }
    }
}

// MARK: - On-device model

/// Apple's on-device language model (iOS 26 and later). Private, offline and free; needs a
/// device with Apple Intelligence turned on. When it isn't available the engine carries on
/// with the deterministic and heuristic tiers and says so in the result.
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
        let prompt = """
        Document text (recognized from a photo or PDF, may contain recognition errors):
        ---
        \(text)
        ---
        Our first guess for the document kind is "\(input.kind.rawValue)". Correct it if it's wrong.
        """
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedDocumentFacts.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return ModelAnswerMapper.fields(from: response.content.answers, sourceText: input.text, tier: tier, resolver: resolver)
    }

    static let instructions = """
    You read Romanian household documents: ID cards, passports, driving licences, car registration \
    certificates, insurance policies (RCA, CASCO, home), utility invoices, car service invoices, \
    fiscal receipts, warranty certificates, ITP inspection reports, veterinary and medical records. \
    Extract only what is printed. Never invent values: leave a field empty when it isn't in the text. \
    Write dates as YYYY-MM-DD. Write amounts with a dot as the decimal separator and no thousands separator. \
    The issuer is the company or clinic that issued the document, not the customer.
    """
}

@Generable(description: "Facts printed on a Romanian household document")
struct GeneratedDocumentFacts {
    @Guide(description: "The kind of document", .anyOf(CaptureDocumentKind.allCases.map(\.rawValue)))
    var documentKind: String

    @Guide(description: "Company, clinic or authority that issued the document, as printed")
    var issuer: String?

    @Guide(description: "Document, invoice or certificate number, as printed")
    var documentNumber: String?

    @Guide(description: "Issue or invoice date, YYYY-MM-DD")
    var issueDate: String?

    @Guide(description: "Expiry date or end of validity, YYYY-MM-DD")
    var expiryDate: String?

    @Guide(description: "Payment due date, YYYY-MM-DD")
    var dueDate: String?

    @Guide(description: "Start of validity or coverage, YYYY-MM-DD")
    var startDate: String?

    @Guide(description: "Total amount to pay or paid, digits with a dot for decimals")
    var totalAmount: String?

    @Guide(description: "Currency code: RON, EUR or USD")
    var currency: String?

    @Guide(description: "Insurance policy series and number")
    var policyNumber: String?

    @Guide(description: "Phone number for claims or assistance")
    var claimsPhone: String?

    @Guide(description: "Romanian registration plate, e.g. B 123 ABC")
    var licensePlate: String?

    @Guide(description: "17-character vehicle identification number")
    var vin: String?

    @Guide(description: "Product bought, for receipts and warranties")
    var productName: String?

    @Guide(description: "Product serial number or IMEI")
    var serialNumber: String?

    @Guide(description: "Purchase date, YYYY-MM-DD")
    var purchaseDate: String?

    @Guide(description: "Warranty length in months")
    var warrantyMonths: Int?

    @Guide(description: "Odometer reading in kilometres")
    var odometerKm: Int?

    @Guide(description: "Date of the next vaccine or booster, YYYY-MM-DD")
    var nextDoseDate: String?

    @Guide(description: "Parts, services and labour listed with their amounts", .maximumCount(30))
    var lineItems: [GeneratedLineItem]

    var answers: ModelAnswerMapper.Answers {
        ModelAnswerMapper.Answers(
            kind: documentKind, issuer: issuer, documentNumber: documentNumber, issueDate: issueDate,
            expiryDate: expiryDate, dueDate: dueDate, startDate: startDate, totalAmount: totalAmount,
            currency: currency, policyNumber: policyNumber, claimsPhone: claimsPhone, licensePlate: licensePlate,
            vin: vin, productName: productName, serialNumber: serialNumber, purchaseDate: purchaseDate,
            warrantyMonths: warrantyMonths, odometerKm: odometerKm, nextDoseDate: nextDoseDate,
            lineItems: lineItems.map { ($0.itemDescription, $0.amount) }
        )
    }
}

@Generable(description: "One line of an invoice or receipt")
struct GeneratedLineItem {
    @Guide(description: "What the line is for, as printed")
    var itemDescription: String

    @Guide(description: "Line amount, digits with a dot for decimals")
    var amount: String?
}
