import CoreGraphics
import Foundation

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

