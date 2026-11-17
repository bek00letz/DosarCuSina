import Foundation

/// An amount of money in one currency. Amounts in different currencies are
/// never added together; use `MoneyTotals` to sum a mixed list.
///
/// Archive and storage encoding: `{"amount": "12.50", "currency": "RON"}`.
/// The amount is a decimal string so no platform loses precision on the way.
public struct Money: Hashable, Sendable, Codable {
    public var amount: Decimal
    /// ISO 4217 code, uppercase, such as `RON`, `EUR` or `USD`.
    public var currency: String

    public static let defaultCurrency = "RON"
    /// Currencies offered first in pickers. Any ISO 4217 code is accepted.
    public static let commonCurrencies = ["RON", "EUR", "USD"]

    public init(_ amount: Decimal, currency: String = Money.defaultCurrency) {
        self.amount = amount
        self.currency = currency.uppercased()
    }

    /// An amount in the machine form archives and stored JSON use ("12.50").
    public init?(amountString: String, currency: String) {
        guard let value = RomanianNumber.canonical(amountString) else { return nil }
        self.init(value, currency: currency)
    }

    /// Plain decimal string with a dot separator, as written to archives.
    public var amountString: String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .bankers)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    /// Localized display such as `1.234,50 lei`.
    public func formatted(locale: Locale = .dosarDefault) -> String {
        written(fractionDigits: 2, locale: locale)
    }

    /// Display without decimals when the amount is whole, such as `350 lei`.
    public func formattedCompact(locale: Locale = .dosarDefault) -> String {
        let isWhole = amount == amount.rounded(scale: 0)
        return written(fractionDigits: isWhole ? 0 : 2, locale: locale)
    }

    /// The one way an amount is written: in lei for the leu, as docs/COPY_GUIDE.md says
    /// („1.250,50 lei”, never „RON”), with the number and its unit kept on one line; any other
    /// currency by its code („1.250,50 EUR”). A whole number of lei takes the leu's plural from
    /// the String Catalog (`wholeLei`): „1 leu”, „2 lei”, „20 de lei”; with decimals it is
    /// always „lei” („1,50 lei”).
    private func written(fractionDigits: Int, locale: Locale) -> String {
        guard currency == Money.defaultCurrency else {
            return amount.formatted(Decimal.FormatStyle.Currency(code: currency, locale: locale).precision(.fractionLength(fractionDigits)))
        }
        let number = amount.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(fractionDigits)))
        if fractionDigits == 0, let count = Self.count(amount) {
            return Self.wholeLei(number, count: count)
        }
        return String(localized: "\(number)\u{00A0}lei", comment: "An amount of money in lei with decimals, e.g. „1.250,50 lei”. Keep the no-break space.")
    }

    /// A whole number of lei, written as `number` („1.250”): the leu's plural forms in the
    /// String Catalog pick „leu”, „lei” or „de lei” by `count`, the amount without its sign.
    static func wholeLei(_ number: String, count: Int) -> String {
        String(localized: "\(number)\u{00A0}\(count) lei",
               locale: .dosarDefault, comment: "A whole amount of money in lei: the first argument is the amount as written („1.250”), the second only chooses the plural („1 leu”, „2 lei”, „20 de lei”). Keep the no-break space.")
    }

    /// The whole number of lei an amount is, without its sign; nil when it doesn't fit.
    private static func count(_ amount: Decimal) -> Int? {
        let whole = NSDecimalNumber(decimal: amount.magnitude.rounded(scale: 0))
        guard whole.compare(NSDecimalNumber(value: Int.max)) == .orderedAscending else { return nil }
        return whole.intValue
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case amount, currency }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try container.decode(String.self, forKey: .currency)
        let raw = try container.decode(String.self, forKey: .amount)
        guard let value = RomanianNumber.canonical(raw) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: "Not a decimal: \(raw)")
        }
        self.init(value, currency: currency)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amountString, forKey: .amount)
        try container.encode(currency, forKey: .currency)
    }
}

/// Sums of money kept apart per currency.
public struct MoneyTotals: Hashable, Sendable {
    public private(set) var byCurrency: [String: Decimal] = [:]

    public init() {}

    public init<S: Sequence>(_ values: S) where S.Element == Money {
        for value in values { add(value) }
    }

    public mutating func add(_ value: Money) {
        byCurrency[value.currency, default: 0] += value.amount
    }

    public var isEmpty: Bool { byCurrency.values.allSatisfy { $0 == 0 } }

    /// One `Money` per currency, the default currency first, then by code.
    public var amounts: [Money] {
        byCurrency
            .filter { $0.value != 0 }
            .map { Money($0.value, currency: $0.key) }
            .sorted { lhs, rhs in
                if lhs.currency == Money.defaultCurrency { return rhs.currency != Money.defaultCurrency }
                if rhs.currency == Money.defaultCurrency { return false }
                return lhs.currency < rhs.currency
            }
    }

    public func amount(in currency: String) -> Decimal {
        byCurrency[currency.uppercased()] ?? 0
    }

    /// Localized display such as `1.200 RON · 15 EUR`.
    public func formatted(locale: Locale = .dosarDefault) -> String {
        amounts.map { $0.formattedCompact(locale: locale) }.joined(separator: " · ")
    }
}

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
