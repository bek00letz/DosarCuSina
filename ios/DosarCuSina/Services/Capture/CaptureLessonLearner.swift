import Foundation

/// What a paper the person saved teaches the phone's own reader: the one path to learn.
///
/// It learns only from what the person saved, never from a model's answer. It compares the values
/// saved with what the phone's own tiers (1–2) read from the same page, with the lessons they had
/// (`CaptureReadingSource.lessons`), and for every value the phone missed or read wrong it looks
/// for the label the issuer printed it under. A lesson is kept only when the evidence points one way:
///
/// - the saved value is printed next to exactly one label on the page (the words before it on its
///   line, or the line above when it starts its line), and that label is short: one to four words,
///   with no digits (`accepts`);
/// - the label holds no value of the person's: none of the values saved (a name, an address, a
///   code), no card number, nothing shaped like a CNP; it holds only the issuer's words;
/// - told to the readers, the label reads the saved value on this very page, and every value the
///   phone read right still reads the same;
/// - no lesson of the same issuer gives that label to another value; when one does, both go.
///
/// A lesson that read a value the person corrected, from a label on this page, goes too
/// (`Outcome.forgotten`). Pure: the filer records the outcome in the filing's own step
/// (`CaptureLessons.record`).
enum CaptureLessonLearner {
    /// The longest label a lesson keeps, in words: a label, never a sentence.
    static let longestLabel = 4
    /// The fewest letters and digits a text value needs to be looked for on the page: a shorter
    /// one is found in too many places to say where it was printed.
    static let shortestText = 3

    /// What the person saved from a review.
    struct Saved {
        var kind: CaptureDocumentKind
        var values: [CaptureFieldKey: CaptureValue]
    }

    /// What one saved paper taught.
    struct Outcome: Equatable, Sendable {
        let issuer: IssuerKey
        /// The issuer's name, for Settings: as saved, else as the page names it.
        let issuerName: String
        let learned: [CaptureLesson]
        /// Lessons this paper shows wrong: one that read a value the person corrected, or one
        /// that gives a label this paper prints another value under.
        let forgotten: [CaptureLesson]
    }

    /// The fields that name the issuer itself: their values are the issuer's words, never the person's.
    static let issuerFields: Set<CaptureFieldKey> = [.provider, .retailer, .providerTaxID]

    /// What saving `saved` from the page `source` teaches; nil when it teaches nothing (a personal
    /// document, a page that names no issuer, nothing missed or nothing found).
    static func lessons(from source: CaptureReadingSource, saved: Saved, analyzer: CaptureAnalyzer = .standard()) -> Outcome? {
        let kind = saved.kind
        guard kind.profile.learnsIssuerLabels else { return nil }
        let book = source.lessons
        let read = analyze(source, as: kind, with: analyzer.learning(book))
        guard let issuer = read.issuer else { return nil }
        // A CUI saved that isn't the one the page prints: whose paper this is isn't certain.
        if let pageTaxID = issuer.taxID, let savedTaxID = ProviderTaxID.normalized(saved.values[.providerTaxID]?.text),
           savedTaxID != pageTaxID { return nil }

        let text = read.text
        let phone = firstValues(read.fields)
        let window = DateWindow.around(CalendarDay(source.referenceDate))
        let personal = personalWords(in: saved.values)
        let standing = book.standing(for: issuer, kind: kind)
        let right = Set(saved.values.keys.filter { key in phone[key].map { same($0, saved.values[key]) } ?? false })

        var forgotten: [CaptureLesson] = []
        // A label on this page that read a value the person corrected was wrong.
        for lesson in standing {
            guard let value = saved.values[lesson.field], let wrong = phone[lesson.field], !same(wrong, value),
                  !text.lines(containing: [lesson.folded]).isEmpty else { continue }
            forgotten.append(lesson)
        }

        var learned: [CaptureLesson] = []
        for key in saved.values.keys.sorted(by: { $0.rawValue < $1.rawValue }) where kind.allows(key) && !right.contains(key) {
            guard let value = saved.values[key],
                  let label = label(of: value, key: key, in: text, window: window),
                  accepts(label, value: value, personal: personal) else { continue }
            let lesson = CaptureLesson(issuer: issuer, kind: kind, field: key, label: label)
            // A wording the kind's own table has already: nothing to learn.
            guard !kind.profile.labels(for: key).contains(lesson.folded) else { continue }
            // A label already taught for another value: the papers disagree, and neither stands.
            let disagreeing = standing.filter { $0.contradicts(lesson) }
            guard disagreeing.isEmpty else {
                forgotten += disagreeing.filter { !forgotten.contains($0) }
                continue
            }
            guard !learned.contains(where: { $0.contradicts(lesson) }) else { continue }
            // Told to the readers, it reads the saved value here, and keeps what was right.
            let trial = LessonBook(book.lessons.filter { !forgotten.contains($0) } + learned + [lesson])
            let again = firstValues(analyze(source, as: kind, with: analyzer.learning(trial)).fields)
            guard again[key].map({ same($0, value) }) == true,
                  right.allSatisfy({ key in again[key].map { same($0, saved.values[key]) } ?? false }) else { continue }
            learned.append(lesson)
        }
        // Two lessons of this paper the same: once.
        learned = learned.filter { lesson in !standing.contains(lesson) }
        guard !learned.isEmpty || !forgotten.isEmpty else { return nil }
        return Outcome(issuer: issuer, issuerName: issuerName(saved: saved.values, page: text) ?? "", learned: learned, forgotten: forgotten)
    }

    // MARK: The label

    /// Whether `label` may be kept: one to four words, no digits, none of the person's values,
    /// not the saved value itself, no card number and nothing shaped like a CNP.
    static func accepts(_ label: String, value: CaptureValue, personal: Set<String>) -> Bool {
        guard isLabelShaped(label) else { return false }
        if let text = value.text, RomanianText.compact(label).contains(RomanianText.compact(text)) { return false }
        return RomanianText.words(label).allSatisfy { !personal.contains(String($0)) }
    }

    /// Whether `label` is shaped like a label a lesson may keep, whoever wrote it (a backup's
    /// lessons are held to it too): one to four words, no digits, no card number, nothing shaped
    /// like a CNP.
    static func isLabelShaped(_ label: String) -> Bool {
        let words = RomanianText.words(label)
        guard (1...longestLabel).contains(words.count), !label.contains(where: \.isNumber),
              words.contains(where: { $0.count >= 2 }) else { return false }
        // No digits, so none of these; asked anyway, as of everything kept.
        return !PaymentCardNumbers.containsCardNumber(label) && SearchPrivacy.cnpShapedRanges(in: label).isEmpty
    }

    /// The words of every value saved that isn't the issuer's own name: a holder's name, an
    /// address, a code. A label holding one of them is the person's, never the issuer's.
    static func personalWords(in values: [CaptureFieldKey: CaptureValue]) -> Set<String> {
        Set(values.filter { !issuerFields.contains($0.key) }.values.compactMap(\.text).flatMap { text in
            RomanianText.words(text).filter { $0.count >= shortestText }.map(String.init)
        })
    }

    /// The one label the saved value is printed next to on the page; nil when it is printed next
    /// to none, or next to two different ones.
    static func label(of value: CaptureValue, key: CaptureFieldKey, in text: CaptureText, window: DateWindow) -> String? {
        let found = places(of: value, key: key, in: text, window: window).compactMap { label(before: $0, in: text) }
        let distinct = Dictionary(grouping: found, by: RomanianText.fold)
        guard distinct.count == 1 else { return nil }
        return found.first
    }

    /// Where a value is printed: each line it is on, and where on the folded line it starts.
    private static func places(of value: CaptureValue, key: CaptureFieldKey, in text: CaptureText, window: DateWindow)
        -> [(line: Int, start: String.Index)] {
        text.folded.indices.flatMap { index -> [(line: Int, start: String.Index)] in
            let line = text.folded[index]
            let starts: [String.Index]
            switch value {
            case .day(let day):
                starts = RomanianFieldExtractor.dates(inLine: line, index: index, window: window).filter { $0.day == day }.map(\.range.lowerBound)
            case .money(let money):
                starts = RomanianFieldExtractor.amounts(inLine: line).filter { $0.amount == money.amount }.map(\.range.lowerBound)
            case .number(let number):
                starts = numbers(inLine: line, as: key == .meterIndex ? .meterIndex : .count).filter { $0.value == number }.map(\.start)
            case .metric(let number, let unit):
                starts = numbers(inLine: line, as: unit == .kilometres ? .kilometres : .meterIndex).filter { $0.value == number }.map(\.start)
            case .text(let printed):
                starts = textStarts(of: printed, inLine: line)
            case .lineItems:
                starts = []
            }
            return starts.map { (index, $0) }
        }
    }

    /// The numbers on a folded line that aren't part of a date, read by the one number reader.
    private static func numbers(inLine line: String, as kind: NumberKind) -> [(value: Decimal, start: String.Index)] {
        let dates = RomanianFieldExtractor.dates(inLine: line, index: 0).map(\.range)
        return TextPattern.matches(#"(?<![\d.,])(\d+(?:[.,]\d+)*)(?!\d)"#, in: line).compactMap { match in
            guard !dates.contains(where: { $0.overlaps(match.range) }), let raw = match[1],
                  let reading = try? RomanianNumber.read(raw, as: kind, from: .document).get() else { return nil }
            return (reading.value, match.range.lowerBound)
        }
    }

    /// Where a text value starts on a folded line, compared the one way (`RomanianText.compact`)
    /// and never in the middle of a word or a number.
    private static func textStarts(of value: String, inLine line: String) -> [String.Index] {
        let target = RomanianText.compact(value)
        guard target.count >= shortestText else { return [] }
        // Each letter or digit of the line, as compared, with where it is.
        let marks: [(character: Character, at: String.Index)] = line.indices.compactMap { index in
            let compact = RomanianText.compact(String(line[index]))
            guard compact.count == 1, let character = compact.first else { return nil }
            return (character, index)
        }
        let characters = marks.map(\.character)
        let wanted = Array(target)
        guard characters.count >= wanted.count else { return [] }
        func standsApart(_ index: String.Index?) -> Bool {
            guard let index else { return true }
            return !(line[index].isLetter || line[index].isNumber)
        }
        return (0...(characters.count - wanted.count)).compactMap { offset in
            guard Array(characters[offset..<(offset + wanted.count)]) == wanted else { return nil }
            let start = marks[offset].at, end = marks[offset + wanted.count - 1].at
            let before = start > line.startIndex ? line.index(before: start) : nil
            let after = line.index(after: end) < line.endIndex ? line.index(after: end) : nil
            return standsApart(before) && standsApart(after) ? start : nil
        }
    }

    /// The label before a value: the words before it on its line, or, when it starts its line,
    /// the whole line above on the same page. Nil when that is no label: none, too long, or digits.
    private static func label(before place: (line: Int, start: String.Index), in text: CaptureText) -> String? {
        let before = text.folded[place.line][..<place.start]
        if before.contains(where: { $0.isLetter || $0.isNumber }) {
            return printed(String(before), line: place.line, in: text)
        }
        let above = place.line - 1
        guard above >= 0, text.pages[above] == text.pages[place.line] else { return nil }
        return printed(text.folded[above], line: above, in: text)
    }

    /// What separates a label from its value, around it.
    private static let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;=|-–—"))

    /// The label as printed, from the folded words before a value (`folded`, a prefix of the folded
    /// line): the same characters of the line as read, when folding kept them one for one, else its
    /// folded words. Nil when it isn't label-shaped (`longestLabel` words at most, no digits).
    private static func printed(_ folded: String, line: Int, in text: CaptureText) -> String? {
        let words = RomanianText.words(folded)
        guard (1...longestLabel).contains(words.count), !folded.contains(where: \.isNumber) else { return nil }
        let original = text.original[line]
        let printed: String
        if original.count == text.folded[line].count {
            printed = String(original.prefix(folded.count))
        } else {
            printed = words.joined(separator: " ")
        }
        let label = printed.trimmingCharacters(in: separators)
        return label.isEmpty ? nil : label
    }

    // MARK: Values

    /// Whether a reader's value is the one saved: a text compared the one way, an amount by its
    /// sum, a number by its value.
    static func same(_ read: CaptureValue, _ saved: CaptureValue?) -> Bool {
        guard let saved else { return false }
        switch (read, saved) {
        case (.text(let a), .text(let b)): return RomanianText.compact(a) == RomanianText.compact(b)
        case (.money(let a), .money(let b)): return a.amount == b.amount
        case (.metric(let a, _), .metric(let b, _)): return a == b
        default: return read == saved
        }
    }

    /// The issuer's name as saved, else as the page names it.
    private static func issuerName(saved: [CaptureFieldKey: CaptureValue], page text: CaptureText) -> String? {
        for key in [CaptureFieldKey.provider, .retailer] {
            if let name = saved[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        }
        return UtilityProviders.named(in: text)?.name ?? RomanianFieldExtractor.issuerName(in: text)?.name
    }

    private static func firstValues(_ fields: [CaptureField]) -> [CaptureFieldKey: CaptureValue] {
        Dictionary(fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    private static func analyze(_ source: CaptureReadingSource, as kind: CaptureDocumentKind, with analyzer: CaptureAnalyzer) -> CaptureAnalyzer.Analysis {
        source.pages.isEmpty
            ? analyzer.analyze(text: source.text, barcodes: source.barcodes, referenceDate: source.referenceDate, as: kind)
            : analyzer.analyze(pages: source.pages, barcodes: source.barcodes, referenceDate: source.referenceDate, as: kind)
    }
}
