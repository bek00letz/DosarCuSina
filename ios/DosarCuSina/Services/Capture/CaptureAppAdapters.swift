import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Adapters that connect the capture pipeline to services that already exist in the app.
// They live apart from the pure pipeline so the engine stays testable without them.

// MARK: - Utility invoices

/// Claims utility invoices from providers the existing `RomanianUtilityParser` knows exactly
/// (Digi, PPC/Enel, Hidroelectrica, E.ON, Engie, Orange, Vodafone).
public struct UtilityInvoiceParser: CaptureSpecializedParser {

    public init() {}

    public func parse(_ text: CaptureText) -> CaptureAnalyzer.SpecializedParse? {
        let bill = RomanianUtilityParser.shared.parseUtilityBill(text: text.joinedOriginal)
        guard bill.provider != .general else { return nil }

        var fields: [CaptureField] = [
            CaptureField(key: .provider, value: .text(bill.provider.displayName), confidence: 0.95, sourceText: nil, tier: .deterministic),
        ]
        func add(_ key: CaptureFieldKey, _ value: CaptureValue?, _ confidence: Double = 0.85) {
            guard let value else { return }
            fields.append(CaptureField(key: key, value: value, confidence: confidence, sourceText: nil, tier: .deterministic))
        }
        add(.clientCode, bill.clientCode.map(CaptureValue.text))
        add(.invoiceNumber, bill.invoiceNumber.map(CaptureValue.text))
        add(.podCode, bill.podCode.map(CaptureValue.text))
        add(.clcCode, bill.clcCode.map(CaptureValue.text))
        add(.paymentCode, bill.barcodeRaw.map(CaptureValue.text))
        add(.issueDate, bill.issueDate.map { .day(Self.utcDay($0)) })
        add(.dueDate, bill.dueDate.map { .day(Self.utcDay($0)) })
        if let index = bill.indexReading {
            add(.meterIndex, .number(Decimal(string: String(index)) ?? Decimal(index)))
        }
        if let total = bill.totalAmount, let amount = Decimal(string: String(total)) {
            add(.total, .money(CaptureMoney(amount: amount, currencyCode: bill.currency)))
        }
        return CaptureAnalyzer.SpecializedParse(kind: .utilityInvoice, fields: fields)
    }

    /// The utility parser returns dates at midnight UTC; read them back as calendar days.
    static func utcDay(_ date: Date) -> CaptureDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return CaptureDay(date: date, calendar: calendar)
    }
}

// MARK: - Gemini

#if canImport(UIKit)
/// The person's own Gemini key, used only when they ask for it on a specific capture.
/// The image leaves the device, so the engine never calls this on its own.
public struct GeminiCaptureExtractor: CaptureSemanticExtracting {

    public let tier: CaptureTier = .cloudModel
    let resolver: any CaptureComponentResolving

    public init(resolver: any CaptureComponentResolving = CatalogComponentResolver()) {
        self.resolver = resolver
    }

    public func availability() -> CaptureModelAvailability {
        KeychainManager.hasConfiguredAPIKey ? .available : .unavailable("noKey")
    }

    public func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
        guard let page = input.firstPage else {
            return SemanticExtraction(kind: nil, fields: [])
        }
        let response = try await GeminiService.shared.analyzeDocument(image: UIImage(cgImage: page))
        var answers = ModelAnswerMapper.Answers()
        answers.issuer = response.merchant
        answers.issueDate = response.issueDate
        answers.totalAmount = response.totalAmount > 0 ? String(describing: response.totalAmount) : nil
        answers.currency = response.currency
        answers.documentNumber = response.invoiceNumber
        // Gemini's single "due date" is an expiry for policies and documents, a payment date for bills.
        switch input.kind {
        case .rcaPolicy, .insurancePolicy, .passport, .identityCard, .drivingLicence, .itpReport:
            answers.expiryDate = response.dueDate
        default:
            answers.dueDate = response.dueDate
        }
        // Grounding needs text; when local recognition found none, trust the image-based answer as is.
        let source = input.text.isEmpty ? [response.merchant, response.invoiceNumber ?? "", String(describing: response.totalAmount)].joined(separator: " ") : input.text
        return ModelAnswerMapper.fields(from: answers, sourceText: source, tier: tier, resolver: resolver)
    }
}
#endif
