import Foundation

/// What search may keep, decided once for the index and for recent searches:
/// - a number shaped like a CNP (thirteen digits on their own) is never indexed
///   or remembered, wherever it was typed or read, valid or misread;
/// - sealed text (a secret) is never indexed;
/// - a query that found anything in a locked section is never remembered.
public enum SearchPrivacy {
    /// The text with every CNP-shaped number and every sealed value taken out.
    public static func redacting(_ text: String) -> String {
        guard text.contains(where: \.isNumber) || text.contains(SecretSealer.prefix) else { return text }
        var result = text
        for range in cnpShapedRanges(in: result).reversed() {
            result.replaceSubrange(range, with: "")
        }
        if result.contains(SecretSealer.prefix) {
            result = result.split(separator: " ", omittingEmptySubsequences: false)
                .filter { !SecretSealer.isSealed(String($0)) }
                .joined(separator: " ")
        }
        return result
    }

    /// Whether the text holds a number shaped like a CNP.
    public static func containsCNPShapedNumber(_ text: String) -> Bool {
        !cnpShapedRanges(in: text).isEmpty
    }

    /// Whether a search may be kept among the recent ones.
    public static func mayRemember(_ query: String, results: [SearchResult]) -> Bool {
        !containsCNPShapedNumber(query) && !results.contains { $0.document.isSensitive }
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
