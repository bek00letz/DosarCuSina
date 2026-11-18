import Foundation

/// What a paper the person saved teaches the phone's own reader: the one path to learn.
///
/// It learns only from what the person saved, never from a model's answer. It compares the values
/// saved with what the phone's own tiers (1–2) read from the same page, with the lessons they had
/// (`CaptureReadingSource.lessons`), and for every value the phone missed or read wrong it looks
/// for the label the issuer printed it under. A lesson is kept only when the evidence points one way:
///
/// - the saved value is printed next to exactly one label on the page, and that label is short:
///   one to four words, with no digits (`accepts`). Its label is where `LabelledLayout` reads a
///   label's value, read backwards: the words before it on its line, after a date or an amount
///   printed before it there (`afterLastValue`); else, on a page whose lines have positions (a
///   photo, a scan, a digital PDF), the nearest line above it in its own column (a two-column
///   layout) or the nearest line to its left on its row, with nothing between them, whichever is
///   a label, and none when both are (the text to its left may be another column's); without
///   positions, the line above;
/// - the label isn't one the kind reads as another value (`CaptureKindProfile.wordings(otherThan:)`),
///   and one the kind reads as this value teaches only where the kind's own readers, without any
///   lesson, read the value wrong on this page (a column they read on rows joined across it);
/// - the label holds no value of the person's: none of the values saved (a name, an address, a
///   code), nothing the binder keeps that names the household (`Saved.household`: the people's
///   names, the homes' addresses and localities, the plates, `HouseholdValues`), no proper name
///   the page prints in its buyer's block (`buyerBlockNames`), no card number, nothing shaped like
///   a CNP; it holds only the issuer's words;
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
    struct Saved: Sendable {
        var kind: CaptureDocumentKind
        var values: [CaptureFieldKey: CaptureValue]
        /// The words of what the binder keeps that names the household, wherever it is kept
        /// (`HouseholdValues.words`): a label holding one is the person's, never the issuer's.
        var household: Set<String> = []
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

        // The page as it was recognized, each line where it sits, never joined into rows: where
        // the lessons are read (`CaptureAnalyzer`), so a column's label is found above its value.
        let text = source.pages.isEmpty ? read.text : CaptureText(pages: source.pages)
        let phone = firstValues(read.fields)
        let window = DateWindow.around(CalendarDay(source.referenceDate))
        let personal = personalWords(in: saved.values).union(saved.household).union(buyerBlockNames(in: read.text, kind: kind))
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
        // What the kind's own readers read of the page without any lesson, when it is asked.
        var kindAlone: [CaptureFieldKey: CaptureValue]?
        for key in saved.values.keys.sorted(by: { $0.rawValue < $1.rawValue }) where kind.allows(key) && !right.contains(key) {
            guard let value = saved.values[key],
                  let label = label(of: value, key: key, in: text, window: window),
                  accepts(label, value: value, personal: personal) else { continue }
            let lesson = CaptureLesson(issuer: issuer, kind: kind, field: key, label: label)
            // A wording the kind reads as another value is the kind's, never this one's.
            guard !kind.profile.wordings(otherThan: key).contains(lesson.folded) else { continue }
            // One it reads as this value teaches only where the kind's own readers, without any
            // lesson, read the value wrong here (a column, read on rows joined across the page):
            // the lesson reads it where this issuer prints it.
            if kind.profile.wordings(of: key).contains(lesson.folded) {
                if kindAlone == nil { kindAlone = firstValues(analyze(source, as: kind, with: analyzer).fields) }
                guard kindAlone?[key].map({ same($0, value) }) != true else { continue }
            }
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
        return Outcome(issuer: issuer, issuerName: issuerName(saved: saved.values, page: read.text) ?? "", learned: learned, forgotten: forgotten)
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
        words(of: values.filter { !issuerFields.contains($0.key) }.values.compactMap(\.text))
    }

    /// The folded words of `texts` a label is checked against: each of `shortestText` letters or
    /// digits or more, as a value's words are looked for on the page.
    static func words(of texts: some Sequence<String>) -> Set<String> {
        Set(texts.flatMap { text in RomanianText.words(text).filter { $0.count >= shortestText }.map(String.init) })
    }

    /// The proper names the page prints in its buyer's block (`RomanianFieldExtractor.buyerBlock`):
    /// the customer's name and address as printed, each word that starts with a capital and is no
    /// word of a label any table knows (the kind's, every document's, the lexicon's), folded. A
    /// label holding one is the person's.
    static func buyerBlockNames(in text: CaptureText, kind: CaptureDocumentKind) -> Set<String> {
        let block = RomanianFieldExtractor.buyerBlock(in: text)
        guard !block.isEmpty else { return [] }
        let tables = kind.profile.labels + CaptureKindProfile.commonLabels
        let known = words(of: tables.flatMap(\.1) + CaptureLexicon.buyerLabels + CaptureLexicon.nonItemWords
            + CaptureLexicon.holderAddressLabels + CaptureLexicon.policyholderNeighbourLabels)
        var names = Set<String>()
        for line in block.sorted() {
            for word in text.original[line].split(whereSeparator: { !$0.isLetter }) where word.first?.isUppercase == true {
                for folded in words(of: [String(word)]) where !known.contains(folded) { names.insert(folded) }
            }
        }
        return names
    }

    /// The one label the saved value is printed next to on the page; nil when it is printed next
    /// to none, or next to two different ones.
    static func label(of value: CaptureValue, key: CaptureFieldKey, in text: CaptureText, window: DateWindow) -> String? {
        let found = places(of: value, key: key, in: text, window: window).compactMap { label(at: $0, in: text) }
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
                starts = RomanianFieldExtractor.numbers(inLine: line, as: key == .meterIndex ? .meterIndex : .count)
                    .filter { $0.reading.value == number }.map(\.range.lowerBound)
            case .metric(let number, let unit):
                starts = RomanianFieldExtractor.numbers(inLine: line, as: unit == .kilometres ? .kilometres : .meterIndex)
                    .filter { $0.reading.value == number }.map(\.range.lowerBound)
            case .text(let printed):
                starts = textStarts(of: printed, inLine: line)
            case .lineItems:
                starts = []
            }
            return starts.map { (index, $0) }
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

    /// The label of the value printed at `place`, where `LabelledLayout` would read it as that
    /// label's value: the words before it on its line, after a value printed before it there;
    /// else, when it starts its line on a page with positions, the nearest line above it in its
    /// own column (`LabelledLayout.lineAbove`) or the nearest line to its left on its row with
    /// nothing between them (`LabelledLayout.lineBefore`, as far as a lesson's value is read
    /// beside its label, `LessonBook.rowReach`), whichever is a label; when both are, none (the
    /// text to its left may be another column's); without positions, the line above on the same
    /// page. Nil when that is no label: none, too long, or digits.
    private static func label(at place: (line: Int, start: String.Index), in text: CaptureText) -> String? {
        let before = text.folded[place.line][..<place.start]
        if before.contains(where: { $0.isLetter || $0.isNumber }) {
            return printed(on: place.line, upTo: place.start, in: text)
        }
        guard text.boxes[place.line] != nil else {
            let above = place.line - 1
            guard above >= 0, text.pages[above] == text.pages[place.line] else { return nil }
            return printed(on: above, upTo: nil, in: text)
        }
        // In its own column, the line above it there; on its own row, the nearest line to its
        // left, with nothing between them. When both read as labels, the text to its left may be
        // another column's (a two-column bill): which is its label can't be told, and none is.
        let above = LabelledLayout<CaptureFieldKey>.lineAbove(place.line, in: text).flatMap { printed(on: $0, upTo: nil, in: text) }
        let left = LabelledLayout<CaptureFieldKey>.lineBefore(place.line, in: text, reach: LessonBook.rowReach)
            .flatMap { printed(on: $0, upTo: nil, in: text) }
        switch (above, left) {
        case (let above?, nil): return above
        case (nil, let left?): return left
        case (let above?, let left?): return RomanianText.fold(above) == RomanianText.fold(left) ? above : nil
        case (nil, nil): return nil
        }
    }

    /// The label as printed on `line`, up to `end` (its end when nil): its words after a value
    /// printed before them (`afterLastValue`), the same characters of the line as read when
    /// folding kept them one for one, else its folded words. Nil when they aren't label-shaped
    /// (`longestLabel` words at most, no digits).
    private static func printed(on line: Int, upTo end: String.Index?, in text: CaptureText) -> String? {
        let folded = text.folded[line]
        let end = end ?? folded.endIndex
        let start = afterLastValue(in: folded, before: end)
        let words = RomanianText.words(String(folded[start..<end]))
        guard (1...longestLabel).contains(words.count), !folded[start..<end].contains(where: \.isNumber) else { return nil }
        let original = text.original[line]
        let printed: String
        if original.count == folded.count {
            let from = folded.distance(from: folded.startIndex, to: start), to = folded.distance(from: folded.startIndex, to: end)
            printed = String(original.dropFirst(from).prefix(to - from))
        } else {
            printed = words.joined(separator: " ")
        }
        let label = printed.trimmingCharacters(in: LabelledLayout<CaptureFieldKey>.valueSeparators)
        return label.isEmpty ? nil : label
    }

    /// Where the words after the last value printed on a folded line before `end` start: after its
    /// last date, or its last amount printed with its currency and that currency ("01.11.2026",
    /// "123,45 lei"), as the shared readers read them; the line's start when none comes before
    /// `end`. Only a value a reader reads on its own ends another label's value: a bare number
    /// ("Termen 30 zile") is part of its label, which then holds a digit and is refused.
    static func afterLastValue(in line: String, before end: String.Index) -> String.Index {
        let prefix = String(line[..<end])
        var cut = 0
        for date in RomanianFieldExtractor.dates(inLine: prefix, index: 0) {
            cut = max(cut, prefix.distance(from: prefix.startIndex, to: date.range.upperBound))
        }
        for amount in RomanianFieldExtractor.amounts(inLine: prefix) where amount.hasCurrency {
            let currency = prefix[amount.range.upperBound...].drop(while: \.isWhitespace)
            let currencyEnd = currency.firstIndex(where: \.isWhitespace) ?? prefix.endIndex
            cut = max(cut, prefix.distance(from: prefix.startIndex, to: currencyEnd))
        }
        return line.index(line.startIndex, offsetBy: cut)
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
