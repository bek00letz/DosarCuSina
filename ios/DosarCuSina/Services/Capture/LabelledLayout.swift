import Foundation

/// Reads documents laid out as printed labels with values beside or under them:
/// identity cards, licences, certificates. The labels are data (a table per
/// document kind), so a new layout needs a table, not new reading code.
///
/// - A label is matched as whole words in folded text (no diacritics, lowercase);
///   longer wordings win, so "prenume" is never read as "nume".
/// - A value is the rest of the label's line when the line holds more than labels,
///   otherwise the next line, when that line isn't itself a label line.
/// - A date belongs to a label only when it follows it on its line or sits on the
///   next non-label line, so dates are never borrowed from a neighbouring label.
struct LabelledLayout<Key: Hashable> {
    struct Position {
        let key: Key
        let line: Int
        /// Where the label ends on its folded line.
        let end: String.Index
    }

    let text: CaptureText
    let positions: [Position]

    init(text: CaptureText, labels: [(Key, [String])]) {
        self.text = text
        let wordings = labels
            .flatMap { key, words in words.map { (key, $0) } }
            .sorted { $0.1.count > $1.1.count }
        var found: [Position] = []
        for (index, line) in text.folded.enumerated() {
            var taken: [Range<String.Index>] = []
            for (key, word) in wordings {
                guard let range = Self.wordRange(word, in: line), !taken.contains(where: { $0.overlaps(range) }) else { continue }
                taken.append(range)
                found.append(Position(key: key, line: index, end: range.upperBound))
            }
        }
        positions = found.sorted { ($0.line, $0.end) < ($1.line, $1.end) }
    }

    /// The line a label is on, if it was found.
    func line(of key: Key) -> Int? {
        positions.first { $0.key == key }?.line
    }

    private func isLabelLine(_ line: Int) -> Bool {
        positions.contains { $0.line == line }
    }

    /// The text printed for a label, with the lines it came from.
    func value(for key: Key) -> (value: String, source: String)? {
        guard let position = positions.first(where: { $0.key == key }) else { return nil }
        let folded = text.folded[position.line]
        let original = text.original[position.line]
        let labelFollows = positions.contains { $0.line == position.line && $0.end > position.end }
        if !labelFollows {
            let offset = folded.distance(from: folded.startIndex, to: position.end)
            if offset < original.count {
                let rest = String(original.dropFirst(offset)).trimmingCharacters(in: CharacterSet(charactersIn: " :/-.\t"))
                if rest.contains(where: { $0.isLetter || $0.isNumber }) { return (rest, original) }
            }
        }
        let next = position.line + 1
        guard next < text.original.count, !isLabelLine(next) else { return nil }
        let value = text.original[next].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : (value, original + " " + value)
    }

    /// The date printed for a label.
    func day(for key: Key) -> (CaptureDay, String)? {
        guard let position = positions.first(where: { $0.key == key }) else { return nil }
        let line = text.folded[position.line]
        if let match = RomanianFieldExtractor.dates(inLine: line, index: position.line).first(where: { $0.range.lowerBound >= position.end }) {
            return (match.day, text.original[position.line])
        }
        let next = position.line + 1
        guard next < text.folded.count, !isLabelLine(next),
              let match = RomanianFieldExtractor.dates(inLine: text.folded[next], index: next).first else { return nil }
        return (match.day, text.original[position.line] + " " + text.original[next])
    }

    /// A label as whole words, so "sex" isn't found inside "sexe" and "nume" not inside "prenume".
    private static func wordRange(_ word: String, in line: String) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return TextPattern.first(#"(?<![a-z])"# + escaped + #"(?![a-z])"#, in: line)?.range
    }
}
