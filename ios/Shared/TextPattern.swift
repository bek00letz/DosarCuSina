import Foundation

/// Small wrapper over `NSRegularExpression` that returns capture groups as strings.
enum TextPattern {
    struct Match {
        let groups: [String?]
        let range: Range<String.Index>
        subscript(_ index: Int) -> String? { index < groups.count ? groups[index] : nil }
    }

    static func matches(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [Match] {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            assertionFailure("Invalid pattern: \(pattern)")
            return []
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { result in
            guard let whole = Range(result.range, in: text) else { return nil }
            let groups = (0..<result.numberOfRanges).map { index -> String? in
                guard let range = Range(result.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
            return Match(groups: groups, range: whole)
        }
    }

    static func first(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> Match? {
        matches(pattern, in: text, caseInsensitive: caseInsensitive).first
    }
}
