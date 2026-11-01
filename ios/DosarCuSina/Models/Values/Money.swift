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

    public init?(amountString: String, currency: String) {
        guard let value = Money.parseAmount(amountString) else { return nil }
        self.init(value, currency: currency)
    }

    /// Parses `"1234.5"`, `"1.234,50"`, `"1 234,50"` and `"12,5"` into a decimal.
    /// The last `,` or `.` followed by one or two digits is treated as the decimal separator.
    public static func parseAmount(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }
        let separators: Set<Character> = [",", "."]
        if let last = text.lastIndex(where: { separators.contains($0) }) {
            let fraction = text[text.index(after: last)...]
            let whole = text[..<last].filter { !separators.contains($0) }
            if fraction.count <= 2 {
                text = whole + "." + fraction
            } else {
                text = whole + fraction
            }
        }
        guard text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Plain decimal string with a dot separator, as written to archives.
    public var amountString: String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .bankers)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    /// Localized display such as `1.234,50 RON`.
    public func formatted(locale: Locale = .dosarDefault) -> String {
        amount.formatted(.currency(code: currency).locale(locale))
    }

    /// Display without decimals when the amount is whole, such as `350 RON`.
    public func formattedCompact(locale: Locale = .dosarDefault) -> String {
        let isWhole = amount == amount.rounded(scale: 0)
        let style = Decimal.FormatStyle.Currency(code: currency, locale: locale)
            .precision(.fractionLength(isWhole ? 0 : 2))
        return amount.formatted(style)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case amount, currency }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try container.decode(String.self, forKey: .currency)
        let raw = try container.decode(String.self, forKey: .amount)
        guard let value = Money.parseAmount(raw) else {
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

extension Locale {
    /// The locale used for numbers, dates and money: the user's locale when it
    /// is Romanian, otherwise Romanian formatting so amounts read as on bills.
    public static var dosarDefault: Locale {
        let current = Locale.current
        return current.language.languageCode?.identifier == "ro" ? current : Locale(identifier: "ro_RO")
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
