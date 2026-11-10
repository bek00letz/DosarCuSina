import Foundation

/// What search may keep, decided once for the index and for recent searches:
/// - a number shaped like a CNP (thirteen digits on their own) is never indexed
///   or remembered, wherever it was typed or read, valid or misread;
/// - a card number (`PaymentCardNumbers`) is never indexed or remembered, even masked;
/// - sealed text (a secret) is never indexed or remembered;
/// - words kept on this phone outside the binder (recent searches, a trip's plan) are
///   kept only when `mayRemember` allows them, checked again when they are read back;
/// - a query that found anything in a locked section is never remembered;
/// - outside the app (the iPhone's search), nothing from a locked category or the
///   examples, and only titles, without those numbers or the values a category keeps
///   out of search (`mayShowOutside`, `outsideText`).
public enum SearchPrivacy {
    /// The text with every CNP-shaped number, every card number and every sealed value
    /// taken out. A card number is never searched, even by its last four digits.
    public static func redacting(_ text: String) -> String {
        guard text.contains(where: \.isNumber) || text.contains(SecretSealer.prefix) || text.contains(PaymentCardNumbers.mask) else { return text }
        var result = text
        for range in cnpShapedRanges(in: result).reversed() {
            result.replaceSubrange(range, with: "")
        }
        result = PaymentCardNumbers.redact(result).replacingOccurrences(of: PaymentCardNumbers.maskedPattern, with: "", options: .regularExpression)
        if result.contains(SecretSealer.prefix) {
            result = result.split(separator: " ", omittingEmptySubsequences: false)
                .filter { !SecretSealer.isSealed(String($0)) }
                .joined(separator: " ")
        }
        return result
    }

    /// Whether words the person typed may be kept on this phone outside the binder (among
    /// the recent searches, in a trip's plan): only when they hold nothing search never
    /// keeps, no CNP-shaped number, no card number (masked or not) and no sealed value.
    /// The one rule for what is remembered, used when it is kept and again when it is read
    /// back, so what an earlier version kept goes too.
    public static func mayRemember(_ text: String) -> Bool {
        redacting(text) == text
    }

    /// Whether a search may be kept among the recent ones: its words may be remembered, and
    /// it found nothing in a locked section.
    public static func mayRemember(_ query: String, results: [SearchResult]) -> Bool {
        mayRemember(query) && !results.contains { $0.document.isSensitive }
    }

    // MARK: - Outside the app

    /// Whether a record may be shown outside the app, in the iPhone's search
    /// (Spotlight). Stricter than Caută, where a locked section still shows its title:
    /// outside the app a category behind Face ID shows nothing at all, whether or not
    /// it is open now, and examples never leave the app.
    public static func mayShowOutside(isLocked: Bool, isExample: Bool) -> Bool {
        !isLocked && !isExample
    }

    /// A title or a short line as it may be shown outside the app: without any
    /// CNP-shaped number, any sealed value, or any of `withheld` (the values its
    /// category keeps out of search, such as a document number), written with or
    /// without separators. Nil when nothing worth showing is left.
    public static func outsideText(_ text: String?, withholding withheld: [String] = []) -> String? {
        guard let text else { return nil }
        var result = redacting(text)
        for value in withheld {
            guard let pattern = withheldPattern(value) else { continue }
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // What a removed value leaves behind: "Pașaport – " reads "Pașaport".
        let dangling = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "–—-·,:;/|#"))
        result = result.trimmingCharacters(in: dangling)
        return result.contains(where: { $0.isLetter || $0.isNumber }) ? result : nil
    }

    /// The values a section's category keeps out of search (`FieldDefinition.isIndexable`:
    /// document numbers, CNPs, medical notes, codes) and its sensitive or secret rows, as
    /// stored and as shown.
    public static func withheldValues(of asset: Asset, definition: TemplateDefinition?) -> [String] {
        var values: [String] = []
        for field in definition?.allFields ?? [] where !field.isIndexable {
            guard let value = asset.value(field.key) else { continue }
            values += [value.textValue, FieldFormatter.display(value, field: field)].compactMap { $0 }
        }
        values += asset.customFacts.filter { $0.isSensitive || $0.isSecret }.map(\.value)
        return values
    }

    /// The value's letters and digits in order, with anything but a letter or a digit
    /// allowed between them, so "RX 123456", "RX-123456" and "rx123456" are one value.
    /// Nil for a value too short to stand for anything or too long to sit in a title.
    private static func withheldPattern(_ value: String) -> String? {
        let characters = value.filter { $0.isLetter || $0.isNumber }
        guard (4...64).contains(characters.count) else { return nil }
        return characters.map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "[^\\p{L}\\p{N}]*")
    }

    /// Runs of exactly thirteen digits, not part of a longer number.
    static func cnpShapedRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var count = 0
        var index = text.startIndex
        while index <= text.endIndex {
            let isDigit = index < text.endIndex && text[index].isASCII && text[index].isNumber
            if isDigit {
                if start == nil { start = index }
                count += 1
            } else {
                if let runStart = start, count == 13 { ranges.append(runStart..<index) }
                start = nil
                count = 0
            }
            guard index < text.endIndex else { break }
            index = text.index(after: index)
        }
        return ranges
    }
}
