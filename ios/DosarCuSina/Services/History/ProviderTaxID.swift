import Foundation

/// A firm's tax ID (CUI or CIF) as the binder keeps it: digits only, without the "RO"
/// a VAT payer prints in front, so "RO 12345678" and "12345678" are the same firm.
public enum ProviderTaxID {
    /// The stored form of a CUI as read or typed, or nil when it isn't one (2 to 10 digits).
    public static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        if rest.hasPrefix("RO") { rest = rest.dropFirst(2) }
        let digits = rest.filter { !$0.isWhitespace && $0 != "." && $0 != "-" }
        guard (2...10).contains(digits.count), digits.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        // Leading zeros carry nothing.
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? nil : String(trimmed)
    }
}
