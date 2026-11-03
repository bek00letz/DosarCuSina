import Foundation

/// The one answer to "do these two texts say the same thing?": how Romanian text is
/// folded for comparing, and how a keyword is found in it. Search, choices, component
/// matching, every capture reader, the classifier and the router all use it.
public enum RomanianText {
    /// Lowercase, no diacritics (ă, â → a; î → i; ș and the older ş → s; ț and ţ → t),
    /// wide and narrow forms alike, no-break spaces as spaces, a typographic minus as
    /// "-". Spacing and punctuation are kept, so a folded line still lines up with
    /// what was read.
    public static func fold(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ş", with: "ș").replacingOccurrences(of: "ţ", with: "ț")
            .replacingOccurrences(of: "Ş", with: "Ș").replacingOccurrences(of: "Ţ", with: "Ț")
            .replacingOccurrences(of: "−", with: "-")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .dosarDefault)
            .lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// The folded words of `text`: runs of letters and digits, everything else dropped.
    public static func words(_ text: String) -> [Substring] {
        fold(text).split { !$0.isLetter && !$0.isNumber }
    }

    /// How a keyword's last word has to match.
    public enum WordMatch: Sendable {
        /// The whole word and nothing more: "index" is not "indexare", "rca" is not "marca".
        case word
        /// The start of a word, so Romanian endings still match: "garanti" finds
        /// "garanția", "scadent" finds "scadentă". Never the middle of a word:
        /// "achitat" doesn't find "neachitat".
        case stem

        /// Short single words must match whole; longer words and phrases may take an ending.
        public static func natural(for phrase: String) -> WordMatch {
            phrase.count <= 4 && !phrase.contains(" ") ? .word : .stem
        }
    }

    /// A keyword ready to look for in folded text, compiled once and used on many lines.
    public struct Keyword {
        public let phrase: String
        private let regex: NSRegularExpression?

        /// `phrase` is folded here. Its words must follow each other in the text,
        /// separated only by spaces or punctuation; each starts a word, and every
        /// word but the last is whole. The last is whole too, unless `match` is
        /// `.stem`. Letters next to digits count as a new word ("120kwh" has "kwh").
        public init(_ phrase: String, as match: WordMatch? = nil) {
            self.phrase = phrase
            let parts = RomanianText.words(phrase).map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !parts.isEmpty else {
                regex = nil
                return
            }
            let mode = match ?? .natural(for: RomanianText.fold(phrase))
            let ending = mode == .word ? #"(?!\p{L})"# : ""
            let pattern = #"(?<!\p{L})"# + parts.joined(separator: #"(?![\p{L}])[^\p{L}\p{N}]+"#) + ending
            regex = try? NSRegularExpression(pattern: pattern)
        }

        /// Whether the keyword is in `folded`, which is already folded (`RomanianText.fold`).
        public func isFound(inFolded folded: String) -> Bool {
            guard let regex else { return false }
            return regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)) != nil
        }
    }

    /// Whether `phrase` is in `text`, as a whole word or phrase (`.word`), or with an
    /// ending on its last word (`.stem`). Both are folded first.
    public static func containsWord(_ phrase: String, in text: String, as match: WordMatch? = nil) -> Bool {
        Keyword(phrase, as: match).isFound(inFolded: fold(text))
    }
}
