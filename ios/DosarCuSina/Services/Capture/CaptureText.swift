import Foundation

/// Recognized text prepared for pattern matching.
///
/// Every line is kept twice: as read (for showing the source to the user) and
/// folded (lowercased, diacritics removed, cedillas and commas unified), so
/// "Poliță", "POLITA" and "polița" all match `polita`.
public struct CaptureText: Sendable {
    public let original: [String]
    public let folded: [String]

    public init(_ text: String) {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.original = lines
        self.folded = lines.map(Self.fold)
    }

    /// Lowercases, strips diacritics (ș/ş → s, ț/ţ → t, ă/â → a, î → i) and unifies spaces.
    public static func fold(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ro_RO"))
            .lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    public var joinedFolded: String { folded.joined(separator: "\n") }
    public var joinedOriginal: String { original.joined(separator: "\n") }

    /// Indexes of lines whose folded text contains any of the labels.
    func lines(containing labels: [String]) -> [Int] {
        folded.indices.filter { index in labels.contains { folded[index].contains($0) } }
    }

    /// True when any label appears anywhere.
    func contains(any labels: [String]) -> Bool {
        labels.contains { joinedFolded.contains($0) }
    }
}

// MARK: - Regular expressions

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
