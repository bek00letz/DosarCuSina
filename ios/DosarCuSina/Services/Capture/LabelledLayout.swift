import Foundation

/// How a printed label is written, matched against folded text (no diacritics, lowercase).
enum LabelWording: Hashable, Sendable {
    /// Whole words anywhere on a line: "data nasterii", "date of birth".
    case words(String)
    /// A field number at the start of a line, as on EU driving licences: "1.", "4a.".
    case numbered(String)

    /// The regular expression that finds the label in a folded line.
    var pattern: String {
        switch self {
        case .words(let words):
            return #"(?<![a-z])"# + NSRegularExpression.escapedPattern(for: words) + #"(?![a-z])"#
        case .numbered(let number):
            let digits = number.prefix { $0.isNumber }
            let letter = number.dropFirst(digits.count)
            // "1." needs its dot, so a date at the start of a line isn't a label; "4a" may drop it.
            guard !letter.isEmpty else { return #"^\s*"# + digits + #"\.(?!\d)"# }
            let suffix = #"\s?"# + NSRegularExpression.escapedPattern(for: String(letter))
            // Lettered fields share rows ("4a. 20.04.2018  4c. SRPCIV"): mid-line, after a space and with their dot.
            return #"(?:^\s*"# + digits + suffix + #"\.?|(?<=\s)"# + digits + suffix + #"\.)(?![a-z0-9])"#
        }
    }

    /// Longer wordings are matched first, so "prenume" is never read as "nume".
    var length: Int {
        switch self {
        case .words(let words): words.count
        case .numbered(let number): number.count
        }
    }
}

/// Reads documents laid out as printed labels with values beside or under them:
/// identity cards, licences, certificates, any table. The labels are data, so a
/// new layout needs a table, not new reading code.
///
/// - A label is matched as whole words in folded text; longer wordings win.
/// - A value is the rest of the label's line when the line holds more than labels.
/// - With positions (recognized pages), a value is otherwise the nearest line on the
///   same row to the right of the label, or the nearest line below whose span
///   overlaps the label's, before the next label in that column. The label's own
///   translation stacked under it ("Nume" over "Surname") is skipped, and value lines
///   stacked tightly in the column are one value ("CORINA" over "IOANA").
/// - Without positions (pasted text, a PDF's text layer), the value is the next line
///   that isn't a label, skipping the label's own translations.
/// - A value is never a known label, so a label never borrows its neighbour's value.
struct LabelledLayout<Key: Hashable> {
    struct Position {
        let key: Key
        let line: Int
        /// Where the label starts and ends on its folded line.
        let start: String.Index
        let end: String.Index
    }

    /// A value found for a label: the lines it came from and its text.
    struct Found {
        let label: Position
        /// The lines holding the value, top to bottom. The label's line when the value follows it.
        let lines: [Int]
        /// The label's translations stacked under it.
        let labelLines: [Int]
        let value: String
        /// The value in folded form, for dates and numbers.
        let folded: String
        let source: String
    }

    /// The largest gap between two value lines stacked in one column, as a share of the line height.
    static var stackedGapRatio: Double { 0.6 }
    /// How far below its label a value may sit, in line heights.
    static var maximumDrop: Double { 3.5 }
    /// How far to the right of its label a value may sit, in line heights.
    static var maximumBesideGap: Double { 8 }

    let text: CaptureText
    let positions: [Position]
    private let positionsByLine: [Int: [Position]]

    init(text: CaptureText, labels: [(Key, [LabelWording])]) {
        self.text = text
        let wordings = labels
            .flatMap { key, words in words.map { (key, $0) } }
            .sorted { $0.1.length > $1.1.length }
        var found: [Position] = []
        for (index, line) in text.folded.enumerated() {
            var taken: [Range<String.Index>] = []
            for (key, wording) in wordings {
                for match in TextPattern.matches(wording.pattern, in: line) where !taken.contains(where: { $0.overlaps(match.range) }) {
                    taken.append(match.range)
                    found.append(Position(key: key, line: index, start: match.range.lowerBound, end: match.range.upperBound))
                }
            }
        }
        positions = found.sorted { ($0.line, $0.start) < ($1.line, $1.start) }
        positionsByLine = Dictionary(grouping: positions, by: \.line)
    }

    init(text: CaptureText, words: [(Key, [String])]) {
        self.init(text: text, labels: words.map { ($0.0, $0.1.map(LabelWording.words)) })
    }

    /// The first line a label is on, if it was found.
    func line(of key: Key) -> Int? {
        positions.first { $0.key == key }?.line
    }

    func isLabelLine(_ line: Int) -> Bool {
        positionsByLine[line] != nil
    }

    /// The text printed for a label, with the lines it came from.
    func value(for key: Key) -> (value: String, source: String)? {
        found(for: key).map { ($0.value, $0.source) }
    }

    /// The value for a label, trying every place the label was printed.
    func found(for key: Key) -> Found? {
        positions.lazy.filter { $0.key == key }.compactMap { value(at: $0) }.first
    }

    /// Every value printed for a label, top to bottom, for a reader that checks each one
    /// (an address, where a column header may come before the real label).
    func allFound(for key: Key) -> [Found] {
        positions.filter { $0.key == key }.compactMap { value(at: $0) }
    }

    /// The date printed for a label: after it on its line, or in its value.
    func day(for key: Key, window: DateWindow = .aroundToday) -> (CalendarDay, String)? {
        for position in positions where position.key == key {
            let line = text.folded[position.line]
            let nextLabel = (positionsByLine[position.line] ?? []).filter { $0.start > position.start }.map(\.start).min() ?? line.endIndex
            // Only the text between this label and the next, so a field number ("3.") never
            // reads as part of the date after it.
            let segment = position.end < nextLabel ? String(line[position.end..<nextLabel]) : ""
            if let match = RomanianFieldExtractor.dates(inLine: segment, index: position.line, window: window).first {
                return (match.day, text.original[position.line])
            }
            if let found = value(at: position), found.lines != [position.line],
               let match = RomanianFieldExtractor.dates(inLine: found.folded, index: position.line, window: window).first {
                return (match.day, found.source)
            }
        }
        return nil
    }

    // MARK: - Values printed in parts

    /// A value printed in parts (`CompositeValue`), at any of `key`'s labels: the parts
    /// in the label's value; a series alone there takes its number from what follows it
    /// (the fragments beside it on its row, else the next line, in its column when lines
    /// have positions), only when that starts with the number or its own "Nr.", so another
    /// field's number ("Nr. înmatriculare …") is never taken. The readings of every place
    /// the label is printed are then weighed together (`CompositeValue.choose`): a whole
    /// value first; else a series and a number read apart, joined.
    func composite(_ shape: CompositeValue, for key: Key) -> CompositeValue.Found? {
        var readings: [(parts: CompositeValue.Parts, source: String)] = []
        for position in positions where position.key == key {
            guard let found = value(at: position), var parts = shape.parts(in: found.value) else { continue }
            var source = found.source
            if parts.series != nil, parts.number == nil, let next = continuation(after: found.lines.last ?? position.line),
               let number = shape.numberAlone(in: next, anchored: true) {
                parts.number = number
                source += " " + next
            }
            readings.append((parts, source))
        }
        return shape.choose(readings)
    }

    /// What follows a value's line: the fragments to its right on its row, else the next
    /// line that isn't a label (the nearest in its column, when lines have positions).
    private func continuation(after line: Int) -> String? {
        guard let box = text.boxes[line] else {
            return nextLine(after: line).map { text.original[$0] }
        }
        let page = text.pages[line]
        let right = text.boxes.indices
            .filter { index in
                guard index != line, text.pages[index] == page, let other = text.boxes[index] else { return false }
                return other.isOnSameRow(as: box) && other.minX >= box.maxX - 0.25 * box.height
                    && other.minX - box.maxX <= Self.maximumBesideGap * box.height
            }
            .sorted { (text.boxes[$0]?.minX ?? 0) < (text.boxes[$1]?.minX ?? 0) }
        let beside = right.prefix { !isLabelLine($0) }
        if !beside.isEmpty { return beside.map { text.original[$0] }.joined(separator: " ") }
        guard let below = nextInColumn(below: line, span: box, limit: box.maxY + Self.maximumDrop * box.height),
              !isLabelLine(below) else { return nil }
        return text.original[below]
    }

    /// Lines in reading order, each label followed by its translations and its value,
    /// so text shown to a person keeps a card's columns together.
    func readableLines() -> [String] {
        var emitted = Set<Int>()
        var result: [String] = []
        func emit(_ line: Int) {
            guard emitted.insert(line).inserted else { return }
            result.append(text.original[line])
        }
        for line in text.original.indices where !emitted.contains(line) {
            emit(line)
            for position in positionsByLine[line] ?? [] {
                guard let found = value(at: position) else {
                    labelBlock(below: position).forEach(emit)
                    continue
                }
                found.labelLines.forEach(emit)
                found.lines.forEach(emit)
            }
        }
        return result
    }

    // MARK: - Finding values

    private func value(at position: Position) -> Found? {
        if let rest = restOfLine(after: position) {
            return Found(label: position, lines: [position.line], labelLines: [], value: rest, folded: RomanianText.fold(rest), source: text.original[position.line])
        }
        let labelLines = labelBlock(below: position)
        let lines: [Int]
        if text.boxes[position.line] != nil {
            lines = beside(position).map { [$0] } ?? column(below: position, after: labelLines.last ?? position.line)
        } else {
            lines = nextLine(after: labelLines.last ?? position.line).map { [$0] } ?? []
        }
        guard !lines.isEmpty else { return nil }
        let value = lines.map { text.original[$0] }.joined(separator: " ")
        let source = ([position.line] + labelLines + lines).map { text.original[$0] }.joined(separator: " ")
        return Found(label: position, lines: lines, labelLines: labelLines, value: value, folded: RomanianText.fold(value), source: source)
    }

    /// What follows the label on its own line, when no other label follows it there.
    /// What follows the label on its own line, up to the next label on that line, so two
    /// fields sharing a row ("4a. 20.04.2018 4c. SRPCIV") each keep their own value.
    private func restOfLine(after position: Position) -> String? {
        let folded = text.folded[position.line]
        let original = text.original[position.line]
        let from = folded.distance(from: folded.startIndex, to: position.end)
        let nextLabel = (positionsByLine[position.line] ?? []).filter { $0.start > position.start }.map(\.start).min()
        let to = nextLabel.map { folded.distance(from: folded.startIndex, to: $0) } ?? original.count
        guard from < min(to, original.count) else { return nil }
        let rest = Self.droppingTranslations(String(original.dropFirst(from).prefix(min(to, original.count) - from)))
            .trimmingCharacters(in: CharacterSet(charactersIn: " :/-.\t"))
        return rest.contains(where: { $0.isLetter || $0.isNumber }) ? rest : nil
    }

    /// A label's printed translations right after it belong to the label, not to the
    /// value: "/Authority/Autorité" after "Autoritatea". Each "/" starts a translation,
    /// which ends at the first word in capitals or with digits, where a value printed
    /// on the same line begins ("…/Autorité SPCEEPS EXEMPLU").
    static func droppingTranslations(_ rest: String) -> String {
        var remaining = Substring(rest).drop { $0 == " " }
        while remaining.first == "/" {
            remaining = remaining.dropFirst().drop { $0 == " " }
            while let word = remaining.split(separator: " ", maxSplits: 1).first.map({ $0.split(separator: "/").first ?? $0 }),
                  !word.isEmpty, !isValueWord(word) {
                remaining = remaining.dropFirst(word.count).drop { $0 == " " }
            }
        }
        return String(remaining)
    }

    /// A word printed as a value rather than as a label: capitals, or digits.
    private static func isValueWord(_ word: Substring) -> Bool {
        let letters = word.filter(\.isLetter)
        if word.contains(where: \.isNumber) { return true }
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }

    /// Everything on the label's row after it, up to the next label: the rest of its line and
    /// the fragments beside it, left to right ("9." then "A" "B" "C" in their own boxes).
    func restOfRow(for key: Key) -> (value: String, source: String)? {
        for position in positions where position.key == key {
            var parts = [restOfLine(after: position)].compactMap { $0 }
            var sources = [text.original[position.line]]
            if positionsByLine[position.line]?.contains(where: { $0.start > position.start }) != true,
               let lineBox = text.boxes[position.line] {
                let page = text.pages[position.line]
                let right = text.boxes.indices
                    .filter { index in
                        guard index != position.line, text.pages[index] == page, let box = text.boxes[index] else { return false }
                        return box.isOnSameRow(as: lineBox) && box.minX >= lineBox.maxX - 0.25 * lineBox.height
                    }
                    .sorted { (text.boxes[$0]?.minX ?? 0) < (text.boxes[$1]?.minX ?? 0) }
                for index in right {
                    if isLabelLine(index) { break }
                    parts.append(text.original[index])
                    sources.append(text.original[index])
                }
            }
            if !parts.isEmpty { return (parts.joined(separator: " "), sources.joined(separator: " ")) }
        }
        return nil
    }

    /// Whether every label on a line is `key`: the label printed again in another language.
    private func isTranslation(_ line: Int, of key: Key) -> Bool {
        guard let labels = positionsByLine[line] else { return false }
        return labels.allSatisfy { $0.key == key } && restOfLine(after: labels[labels.count - 1]) == nil
    }

    /// The label's translations directly under it (in its column, or the next lines without positions).
    private func labelBlock(below position: Position) -> [Int] {
        var block: [Int] = []
        var current = position.line
        while true {
            let next: Int?
            if let span = span(of: position) {
                next = nextInColumn(below: current, span: span, limit: nil)
            } else {
                next = current + 1 < text.original.count ? current + 1 : nil
            }
            guard let next, isTranslation(next, of: position.key) else { return block }
            block.append(next)
            current = next
        }
    }

    /// Without positions: the next line after the label block, unless it is another label.
    private func nextLine(after line: Int) -> Int? {
        let next = line + 1
        guard next < text.original.count, !isLabelLine(next) else { return nil }
        return next
    }

    /// The label's horizontal span on its page: its share of its line's box.
    private func span(of position: Position) -> TextBox? {
        guard let box = text.boxes[position.line] else { return nil }
        let folded = text.folded[position.line]
        let start = folded.distance(from: folded.startIndex, to: position.start)
        let end = folded.distance(from: folded.startIndex, to: position.end)
        return box.slice(from: start, to: end, of: folded.count)
    }

    /// The nearest line on the label's row, to its right, when it isn't another label.
    private func beside(_ position: Position) -> Int? {
        guard let lineBox = text.boxes[position.line] else { return nil }
        let page = text.pages[position.line]
        let right = text.boxes.indices
            .filter { index in
                guard index != position.line, text.pages[index] == page, let box = text.boxes[index] else { return false }
                return box.isOnSameRow(as: lineBox) && box.minX >= lineBox.maxX - 0.25 * lineBox.height
                    && box.minX - lineBox.maxX <= Self.maximumBesideGap * lineBox.height
            }
            .min { (text.boxes[$0]?.minX ?? 0) < (text.boxes[$1]?.minX ?? 0) }
        guard let right, !isLabelLine(right) else { return nil }
        return right
    }

    /// The value lines in the label's column: the nearest line below that isn't a label,
    /// and the lines stacked tightly under it.
    private func column(below position: Position, after line: Int) -> [Int] {
        guard let span = span(of: position), let top = text.boxes[line] else { return [] }
        guard let first = nextInColumn(below: line, span: span, limit: top.maxY + Self.maximumDrop * top.height),
              !isLabelLine(first), let firstBox = text.boxes[first] else { return [] }
        var lines = [first]
        var last = firstBox
        while let next = nextInColumn(below: lines[lines.count - 1], span: last, limit: last.maxY + Self.stackedGapRatio * last.height),
              !isLabelLine(next), let box = text.boxes[next],
              abs(box.minX - last.minX) <= 2 * min(box.height, last.height),
              box.height <= 1.5 * last.height, last.height <= 1.5 * box.height {
            lines.append(next)
            last = box
        }
        return lines
    }

    /// The nearest line below `line` on the same page whose span overlaps `span`; on a
    /// row with several, the one that overlaps most. `limit` caps how far down it looks.
    private func nextInColumn(below line: Int, span: TextBox, limit: Double?) -> Int? {
        guard let anchor = text.boxes[line] else { return nil }
        let page = text.pages[line]
        let candidates = text.boxes.indices.filter { index in
            guard index != line, text.pages[index] == page, let box = text.boxes[index] else { return false }
            // A real overlap, not a shared edge: at least a quarter of the narrower of the two.
            let overlap = box.horizontalOverlap(span)
            return box.minY >= anchor.midY && !box.isOnSameRow(as: anchor) && overlap > 0 && overlap >= 0.25 * min(box.width, span.width)
                && (limit.map { box.minY <= $0 } ?? true)
        }
        guard let nearest = candidates.min(by: { (text.boxes[$0]?.minY ?? 0) < (text.boxes[$1]?.minY ?? 0) }),
              let nearestBox = text.boxes[nearest] else { return nil }
        return candidates
            .filter { text.boxes[$0]?.isOnSameRow(as: nearestBox) == true }
            .max { (text.boxes[$0]?.horizontalOverlap(span) ?? 0) < (text.boxes[$1]?.horizontalOverlap(span) ?? 0) }
    }
}
