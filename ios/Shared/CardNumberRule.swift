import Foundation

/// A bank card's full number never stays in the binder: not in what a document's text
/// keeps, not in a field, a row under Date importante, a note or any other words a record
/// keeps, not in search, the iPhone's search, backups, logs or the share inbox. Only the last
/// four digits are kept. One set of rules, here, used wherever text enters or leaves:
/// - what the share extension writes about a shared file (`InboxItem.originalName`);
/// - every capture result, before the review or anything else sees it (`CaptureResult.withoutCardNumbers`);
/// - everything kept: the unit of work masks the words of every record it saves, whoever
///   wrote them, an import included (`FreeText`), fields through `sanitizing`;
/// - a secret, before it is sealed (`SecretFields.sealing`);
/// - search and the iPhone's search (`SearchPrivacy.redacting`).
///
/// The rule reads text alone and lives in `ios/Shared`, so the app, its widgets and the share
/// extension use the same one; what a section's field types say about its values (`keepsWhole`,
/// `sanitizing`, `KeptWhole`'s makers) is the app's, beside the fields.
///
/// Two rules, by how sure the app is that the text is a card:
/// - **Anywhere:** a run of 14 to 19 digits (spaces or dashes between groups allowed) that
///   starts like a card number (Visa, Mastercard, Maestro, American Express and the rest)
///   and passes the Luhn check, or is printed in groups of four. Thirteen digits are never
///   taken, so a CNP stays as it is; an IMEI (15 digits, starting otherwise) or a 20-digit
///   health card number isn't a card number either. A card number printed next to other
///   digits, with only a space or a dash between them ("12 4111 1111 1111 1111"), is found
///   inside the longer run: a part of it that begins and ends where its groups do, is
///   printed like a card (one piece, groups of four, 4-6-5) and passes the Luhn check. Digits
///   with nothing between them are one number and are only ever taken whole, so a long code
///   with no spaces (a meter's, a contract's) stays as it is. Inside a long number printed
///   all in groups of four, only a card at its start counts ("4111 1111 1111 1111 0828"),
///   or one right after it, since every part of such a number is grouped like a card.
///
///   Groups apart by anything else (a dot, a slash, several spaces or another kind of space,
///   a dash with spaces around it: "4111.1111.1111.1111", "4111 / 1111 / …") count too, with
///   one kind of gap throughout, printed like a card and passing the Luhn check, whether alone or
///   next to other digits; so dates ("01.02.2026"), amounts ("1.250.000"), versions and a table's
///   columns stay as they are. A date printed with dots, slashes or dashes ("01.02.2026",
///   "2026-02-01") is a number of its own, so a card printed right after it is found as if
///   alone ("01.02.2026 4111 1111 1111 1111"), never read as the end of a long number in fours.
///   Digits of any script count as the digits they are ("４１１１…",
///   "٤١١١…"), and the four kept are written in ASCII digits.
///
///   What is never a card, whatever its digits: digits glued to a letter, before or after
///   them ("AB4111…", an IBAN's account in one piece, its first group after the country's
///   letters), since a card number is never printed glued to letters; groups that carry on an
///   IBAN printed in groups ("RO49 AAAA 1234 5678 9012 3456", even mistyped); any part of an
///   IBAN that passes its own check (`IBAN.ranges`), in any spacing; a field's value whose
///   type names what it is and whose own check it passes (`keepsWhole(_:as:)`: an IBAN, a
///   pet's microchip); and, in the words a section keeps, the same digits as one of its own
///   values kept that way (`KeptWhole`).
/// - **On a bank card** (`strict`): any run of eight digits or more, whatever it starts
///   with or whether its check digit passes, since a misread digit must not let the rest
///   through; groups apart by one space or dash are one run, and what is left of a longer run
///   apart by anything else is another. Nothing is kept whole there.
///
/// A number taken out is written as its last four digits after a mask: "•••• 4821".
public enum PaymentCardNumbers {
    /// What stands for the digits taken out.
    public static let mask = "••••"
    /// A masked number with its last four digits ("•••• 4821"), for taking it out whole.
    public static let maskedPattern = #"(?:••••[ -]?)+\d{0,4}"#

    /// The digits of a section's own values that its field types tell apart from a card number
    /// (a pet's microchip in its microchip field, passing that field's check), which stay whole
    /// wherever the same section's words hold them: its notes, its rows, its visits, the text
    /// read off its documents. Made only by the app, from a value and its field's type
    /// (`KeptWhole(_:fields:)`, `KeptWhole(typed:)`, both through `keepsWhole`), never from
    /// the digits alone: a 15-digit chip starting 642 and a 15-digit Maestro card can be the
    /// same digits, and only the field says which it is.
    public struct KeptWhole: Hashable, Sendable {
        /// Each value's digits, as a run of the text gives them (`Run.digits`).
        let digits: Set<String>

        /// Nothing kept whole: every card-shaped run is masked.
        public static let nothing = KeptWhole(checkedDigits: [])

        /// Digits `keepsWhole` already approved; only its makers call this.
        init(checkedDigits digits: Set<String>) {
            self.digits = digits
        }

        public var isEmpty: Bool { digits.isEmpty }

        /// Whether a run found in the text is one of these values, whole.
        func keeps(_ run: Run) -> Bool {
            digits.contains(run.digits)
        }
    }

    /// The text with every card number in it masked, keeping only the last four digits. A run
    /// that is one of `kept` (a section's own typed values) stays whole, except on a bank card.
    public static func redact(_ text: String, strict: Bool = false, keeping kept: KeptWhole = .nothing) -> String {
        guard text.contains(where: \.isNumber) else { return text }
        var result = text
        let found = strict ? runs(in: text, strict: true) : cardNumbers(in: text).filter { !kept.keeps($0) }
        for run in found.reversed() {
            result.replaceSubrange(run.range, with: run.masked)
        }
        return result
    }

    /// Whether the text holds something shaped like a card number (the "anywhere" rule), leaving
    /// out a run that is one of `kept` (a value its field's type keeps whole), as `redact` does.
    public static func containsCardNumber(_ text: String, keeping kept: KeptWhole = .nothing) -> Bool {
        guard text.contains(where: \.isNumber) else { return false }
        return cardNumbers(in: text).contains { !kept.keeps($0) }
    }

    /// The last four digits of the card number in the text: a full number by the
    /// "anywhere" rule (or, `strict`, any run of twelve digits or more), else one already
    /// masked ("•••• 4821").
    public static func lastFour(in text: String, strict: Bool = false) -> String? {
        let run = cardNumbers(in: text).first ?? (strict ? runs(in: text, strict: true).first { $0.digits.count >= 12 } : nil)
        if let run { return String(run.digits.suffix(4)) }
        let masked = #"[•*xX]{4}[ -]?(?:[•*xX]{4}[ -]?){0,3}(\d{4})(?!\d)"#
        return TextPattern.first(masked, in: text, caseInsensitive: false)?[1]
    }

    /// Only the last four digits of what was typed or read: "4821" from "4821", from
    /// "•••• 4821" or from a whole number pasted by mistake. Nil when it has fewer.
    public static func lastFour(of value: String) -> String? {
        let digits = value.filter { $0.isASCII && $0.isNumber }
        guard digits.count >= 4 else { return nil }
        return String(digits.suffix(4))
    }

    /// The network a card number's first digits name, as a `PaymentCardNetwork` key.
    public static func network(ofNumber digits: String) -> String? {
        brand(of: digits)?.network
    }

    // MARK: - Runs of digits

    /// What may stand between two groups of a number's digits: a run of spaces (any kind of
    /// space, a tab included), or one dash, dot or slash with spaces around it or none.
    static let gapPattern = #"(?:[\t\p{Zs}]*+[-./][\t\p{Zs}]*+|[\t\p{Zs}]++)"#

    /// Whether a character is part of what stands between two groups (`gapPattern`).
    static func isGapCharacter(_ character: Character) -> Bool {
        if character == "-" || character == "." || character == "/" || character == "\t" { return true }
        return character.unicodeScalars.count == 1 && character.unicodeScalars.first?.properties.generalCategory == .spaceSeparator
    }

    /// A decimal digit of any script as its ASCII digit ("٤", "４" and "4" are all "4").
    static func digit(_ character: Character) -> Character? {
        guard character.isNumber, let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
        return Character(String(value))
    }

    /// What stands between two groups of a run.
    struct Gap: Equatable {
        enum Kind: Equatable { case space, dash, dot, slash }
        let kind: Kind
        /// One space or one dash: the way most numbers are printed in groups.
        let isNarrow: Bool

        init(_ text: Substring) {
            kind = text.contains("-") ? .dash : text.contains(".") ? .dot : text.contains("/") ? .slash : .space
            isNarrow = text == " " || text == "-"
        }
    }

    struct Run {
        let range: Range<String.Index>
        /// The run's digits as ASCII digits, whatever script they are written in.
        let digits: String
        /// Each group's digits, the same way.
        let pieces: [String]
        /// Where each group of digits sits, in order: the pieces between its gaps.
        let groups: [Range<String.Index>]
        /// How many digits each group has.
        let groupSizes: [Int]
        /// What stands between each group and the next.
        let gaps: [Gap]
        /// The whole run of digits found in the text, not a part of a longer one.
        let isWhole: Bool

        init(groups: ArraySlice<Range<String.Index>>, in text: String, isWhole: Bool) {
            self.groups = Array(groups)
            self.range = (groups.first?.lowerBound ?? text.startIndex)..<(groups.last?.upperBound ?? text.startIndex)
            let pieces = groups.map { String(text[$0].compactMap(PaymentCardNumbers.digit)) }
            self.pieces = pieces
            self.digits = pieces.joined()
            self.groupSizes = pieces.map(\.count)
            self.gaps = zip(self.groups, self.groups.dropFirst()).map { Gap(text[$0.upperBound..<$1.lowerBound]) }
            self.isWhole = isWhole
        }

        /// Some of its groups are apart by something else than one space or one dash.
        var isApartByOthers: Bool {
            gaps.contains { !$0.isNarrow }
        }

        /// Its stretches of groups apart by one space or one dash only, in order, each taken as
        /// a whole run: the run itself when nothing else stands between its groups. A date in it
        /// (`isDate(at:)`) is a stretch of its own, so its year never starts a card printed after it.
        func stretches(in text: String) -> [Run] {
            let dates = groups.indices.dropLast(2).filter(isDate(at:))
            let insideDates = Set(dates.flatMap { [$0, $0 + 1] })
            let dateEdges = Set(dates.flatMap { [$0 - 1, $0 + 2] }.filter { gaps.indices.contains($0) })
            let ends = Set(gaps.indices.filter { !gaps[$0].isNarrow && !insideDates.contains($0) }).union(dateEdges)
            guard !ends.isEmpty else { return [self] }
            var stretches: [Run] = []
            var start = 0
            for index in ends.sorted() {
                stretches.append(Run(groups: groups[start...index], in: text, isWhole: true))
                start = index + 1
            }
            stretches.append(Run(groups: groups[start...], in: text, isWhole: true))
            return stretches
        }

        /// Whether the three groups from `start` are a date: a day, a month and a year of four
        /// digits ("01.02.2026", "2/1/2026", "2026-02-01"), apart twice by the same dot, slash or
        /// dash. A card never prints groups that short, so a date is never part of one.
        private func isDate(at start: Int) -> Bool {
            guard gaps[start].kind == gaps[start + 1].kind, gaps[start].kind != .space else { return false }
            let sizes = Array(groupSizes[start...(start + 2)])
            let values = pieces[start...(start + 2)].map { Int($0) ?? 0 }
            let short = 1...2
            if short.contains(sizes[0]), short.contains(sizes[1]), sizes[2] == 4 {
                return ((1...31).contains(values[0]) && (1...12).contains(values[1]))
                    || ((1...12).contains(values[0]) && (1...31).contains(values[1]))
            }
            if sizes[0] == 4, short.contains(sizes[1]), short.contains(sizes[2]) {
                return (1...12).contains(values[1]) && (1...31).contains(values[2])
            }
            return false
        }

        /// Printed in groups of four ("4111 1111 1111 1111").
        var groupedInFours: Bool {
            groupSizes.count >= 3 && groupSizes.allSatisfy { $0 == 4 }
        }

        /// Printed the way cards print their number: in one piece, in groups of four (19 digits
        /// end with three), or in American Express's and Diners Club's 4-6-5 and 4-6-4.
        var printedLikeACard: Bool {
            guard let last = groupSizes.last else { return false }
            if groupSizes.count == 1 || groupSizes == [4, 6, 5] || groupSizes == [4, 6, 4] { return true }
            return groupSizes.dropLast().allSatisfy { $0 == 4 } && (3...4).contains(last)
        }

        /// A card number by the "anywhere" rule. A whole run printed in groups of four counts
        /// even when its check digit was misread; a part of a longer run must pass the check and
        /// be printed like a card, since inside a long number printed in fours every part is.
        /// Groups apart by anything else (dots, slashes, several spaces, which dates, amounts and
        /// a table's columns give too) count only with one kind of gap throughout, printed like a
        /// card and passing the check.
        var isCardNumber: Bool {
            guard (14...19).contains(digits.count), let brand = PaymentCardNumbers.brand(of: digits), brand.lengths.contains(digits.count) else { return false }
            if isApartByOthers {
                let kinds = gaps.map(\.kind)
                return kinds.allSatisfy { $0 == kinds.first } && printedLikeACard && PaymentCardNumbers.passesLuhn(digits)
            }
            if !isWhole { return printedLikeACard && PaymentCardNumbers.passesLuhn(digits) }
            return PaymentCardNumbers.passesLuhn(digits) || (groupedInFours && digits.count == 16)
        }

        var masked: String {
            digits.count >= 12 ? "\(PaymentCardNumbers.mask) \(digits.suffix(4))" : PaymentCardNumbers.mask
        }
    }

    /// Runs of digits, of any script, whose groups are apart by what `gapPattern` allows, not
    /// part of a longer run, with `least` digits or more.
    static func spans(in text: String, least: Int) -> [Run] {
        let pattern = #"\d(?:"# + gapPattern + #"?\d){"# + String(least - 1) + #",}(?!"# + gapPattern + #"?\d)"#
        return TextPattern.matches(pattern, in: text, caseInsensitive: false).map { match in
            Run(groups: groups(in: text, range: match.range)[...], in: text, isWhole: true)
        }
    }

    /// Runs of digits with at most one space or dash between them, not part of a longer
    /// run: twelve digits or more, or (`strict`) eight or more. On a bank card (`strict`), where
    /// a longer run's groups are apart by anything else (dots, slashes, several spaces), the card
    /// numbers the "anywhere" rule finds in it are runs, and so is what is left of it beside
    /// them, with eight digits or more.
    static func runs(in text: String, strict: Bool) -> [Run] {
        let least = strict ? 8 : 12
        var ibans: [Range<String.Index>]?
        return spans(in: text, least: least).flatMap { span -> [Run] in
            let stretches = span.stretches(in: text)
            guard strict, span.isApartByOthers else { return stretches.filter { $0.digits.count >= least } }
            if ibans == nil { ibans = text.contains(where: \.isLetter) ? IBAN.ranges(in: text) : [] }
            let cards = cardNumbers(inSpan: span, of: text, outside: ibans ?? [])
            var found = cards
            var rest: [Range<String.Index>] = []
            func keepRest() {
                if !rest.isEmpty {
                    let run = Run(groups: rest[...], in: text, isWhole: true)
                    if run.digits.count >= least { found.append(run) }
                }
                rest = []
            }
            let inACard = { (group: Range<String.Index>) in cards.contains { $0.range.overlaps(group) } }
            for stretch in stretches {
                if stretch.digits.count >= least, !stretch.groups.contains(where: inACard) {
                    keepRest()
                    found.append(stretch)
                    continue
                }
                for group in stretch.groups {
                    if inACard(group) { keepRest() } else { rest.append(group) }
                }
            }
            keepRest()
            return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
        }
    }

    /// The card numbers in the text by the "anywhere" rule, in order (`cardNumbers(inSpan:of:outside:)`).
    static func cardNumbers(in text: String) -> [Run] {
        let ibans = text.contains(where: \.isLetter) ? IBAN.ranges(in: text) : []
        return spans(in: text, least: 12).flatMap { cardNumbers(inSpan: $0, of: text, outside: ibans) }
    }

    /// The card numbers in one run of the text (`spans(in:least:)`) by the "anywhere" rule, in
    /// order: in each of its stretches apart by one space or dash, a whole stretch that is one,
    /// else the parts of a longer one that are (`parts(of:in:where:)`), looked for only in what
    /// of it isn't a code (`pieces(of:in:outside:)`); then, where something else stands between
    /// groups (dots, slashes, several spaces), the card numbers printed that way.
    static func cardNumbers(inSpan span: Run, of text: String, outside ibans: [Range<String.Index>]) -> [Run] {
        func cards(in run: Run, where accepts: (Run) -> Bool) -> [Run] {
            pieces(of: run, in: text, outside: ibans).flatMap { piece in
                accepts(piece) ? [piece] : parts(of: piece, in: text, where: accepts)
            }
        }
        let found = span.stretches(in: text).filter { $0.digits.count >= 12 }.flatMap { cards(in: $0, where: \.isCardNumber) }
        guard span.isApartByOthers else { return found }
        let apart = cards(in: span) { $0.isApartByOthers && $0.isCardNumber }
            .filter { card in !found.contains { $0.range.overlaps(card.range) } }
        return (found + apart).sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// What of a run can be a card number, once the digits that belong to a code are left
    /// out: the groups inside an IBAN that passes its check (`ibans`); a group glued to a letter
    /// before or after it, with nothing between (an IBAN's account after its bank's letters, its
    /// first group after the country's, a code such as "AB4111…"), since a card number is never
    /// printed that way; and, with no IBAN that passes its check there, groups that carry on an
    /// IBAN printed in groups (`continuesAnIBAN`). Anything left out of a run makes what remains
    /// a part of it, which must pass the Luhn check and be printed like a card.
    static func pieces(of run: Run, in text: String, outside ibans: [Range<String.Index>]) -> [Run] {
        let overlapsIBAN = { (group: Range<String.Index>) in ibans.contains { $0.overlaps(group) } }
        let hasIBAN = run.groups.contains(where: overlapsIBAN)
        var stretches: [ArraySlice<Range<String.Index>>] = []
        var current: [Range<String.Index>] = []
        for group in run.groups {
            if overlapsIBAN(group) {
                if !current.isEmpty { stretches.append(current[...]) }
                current = []
            } else {
                current.append(group)
            }
        }
        if !current.isEmpty { stretches.append(current[...]) }
        return stretches.compactMap { stretch -> Run? in
            var groups = stretch
            if let first = groups.first, first.lowerBound > text.startIndex, text[text.index(before: first.lowerBound)].isLetter {
                groups = groups.dropFirst()
            }
            if let last = groups.last, last.upperBound < text.endIndex, text[last.upperBound].isLetter {
                groups = groups.dropLast()
            }
            guard !groups.isEmpty else { return nil }
            let piece = groups.count == run.groups.count ? run : Run(groups: groups, in: text, isWhole: false)
            return !hasIBAN && continuesAnIBAN(piece, in: text) ? nil : piece
        }
    }

    /// Whether the run carries on an IBAN printed in groups, its check passing or not: a
    /// country that issues IBANs (`IBAN.lengths`) in capitals and two check
    /// digits, maybe groups of four letters or digits, then the run, each apart by spaces or by
    /// one dash, dot or slash ("RO49 AAAA 1234 5678 9012 3456", "RO49.AAAA.1234.5678…").
    static func continuesAnIBAN(_ run: Run, in text: String) -> Bool {
        let before = text[..<run.range.lowerBound].suffix(48)
        guard let last = before.last, isGapCharacter(last) else { return false }
        let apart = #"(?:[-./]|[\t\p{Zs}]++)"#
        let head = #"(?<![\p{L}\p{N}])([A-Z]{2})\d{2}(?:"# + apart + #"[A-Z0-9]{4})*"# + apart + #"$"#
        guard let country = TextPattern.first(head, in: String(before), caseInsensitive: false)?[1] else { return false }
        return IBAN.lengths[country] != nil
    }

    /// The card numbers inside a run that isn't one as a whole: a card number printed next to
    /// other digits ("12 4111 1111 1111 1111", "4111-1111-1111-1111-27"). Only parts that
    /// begin and end where the run's groups do are tried, from the left and the longest first
    /// at each place; a part is taken when `accepts` takes it (a card number, `isCardNumber`:
    /// printed like a card and passing the Luhn check). Digits with nothing between them stay
    /// one number. In a run printed all in groups of four, every part is grouped like a card,
    /// so a part is tried only at its start or right after a card found there: a card printed
    /// before other digits, never the middle or the end of a long number (a 20-digit health
    /// card number in five groups).
    static func parts(of run: Run, in text: String, where accepts: (Run) -> Bool = \.isCardNumber) -> [Run] {
        let sizes = run.groupSizes
        guard sizes.count >= 2 else { return [] }
        let cardLengths = 14...19
        let startOnly = sizes.allSatisfy { $0 == 4 }
        var found: [Run] = []
        var start = 0
        while start < sizes.count {
            // The ends that give a card's length, longest first; nothing longer is ever built.
            var length = 0
            var ends: [Int] = []
            for end in start..<sizes.count {
                length += sizes[end]
                if length > cardLengths.upperBound { break }
                let isWhole = start == 0 && end == sizes.count - 1
                if cardLengths.contains(length), !isWhole { ends.append(end) }
            }
            let part = ends.reversed().lazy
                .map { Run(groups: run.groups[start...$0], in: text, isWhole: false) }
                .first(where: accepts)
            if let part {
                found.append(part)
                start += part.groups.count
            } else if startOnly {
                // Printed all in fours: a card starts the run or follows one found before it.
                break
            } else {
                start += 1
            }
        }
        return found
    }

    /// The groups of digits in `range`: the pieces between its gaps.
    private static func groups(in text: String, range: Range<String.Index>) -> [Range<String.Index>] {
        var groups: [Range<String.Index>] = []
        var groupStart: String.Index?
        var index = range.lowerBound
        while index < range.upperBound {
            let next = text.index(after: index)
            if isGapCharacter(text[index]) {
                if let groupStart { groups.append(groupStart..<index) }
                groupStart = nil
            } else if groupStart == nil {
                groupStart = index
            }
            index = next
        }
        if let groupStart { groups.append(groupStart..<range.upperBound) }
        return groups
    }

    // MARK: - Brands

    struct Brand {
        let network: String
        let lengths: ClosedRange<Int>
    }

    /// The network a number belongs to by its first digits (the issuer ranges every
    /// network publishes), with the lengths it uses.
    static func brand(of digits: String) -> Brand? {
        func starts(_ low: Int, _ high: Int, digits count: Int) -> Bool {
            guard digits.count >= count, let prefix = Int(digits.prefix(count)) else { return false }
            return (low...high).contains(prefix)
        }
        if starts(34, 34, digits: 2) || starts(37, 37, digits: 2) { return Brand(network: PaymentCardNetwork.amex, lengths: 15...15) }
        if starts(4, 4, digits: 1) { return Brand(network: PaymentCardNetwork.visa, lengths: 16...19) }
        if starts(51, 55, digits: 2) || starts(2221, 2720, digits: 4) { return Brand(network: PaymentCardNetwork.mastercard, lengths: 16...16) }
        if starts(50, 50, digits: 2) || starts(56, 69, digits: 2) { return Brand(network: PaymentCardNetwork.maestro, lengths: 14...19) }
        // Diners Club, JCB and Discover. An IMEI (15 digits, often starting 35) is none of them.
        if starts(300, 305, digits: 3) || starts(36, 36, digits: 2) { return Brand(network: PaymentCardNetwork.other, lengths: 14...19) }
        if starts(3528, 3589, digits: 4) || starts(38, 39, digits: 2) { return Brand(network: PaymentCardNetwork.other, lengths: 16...19) }
        return nil
    }

    /// The Luhn check every card number carries in its last digit.
    static func passesLuhn(_ digits: String) -> Bool {
        let numbers = digits.compactMap(\.wholeNumberValue)
        guard numbers.count == digits.count, numbers.count >= 12 else { return false }
        var sum = 0
        for (offset, digit) in numbers.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }
}

/// The card networks a bank card can be on, kept as stable keys (`document.cardNetwork`).
public enum PaymentCardNetwork {
    public static let visa = "cardNetwork.visa"
    public static let mastercard = "cardNetwork.mastercard"
    public static let maestro = "cardNetwork.maestro"
    public static let amex = "cardNetwork.amex"
    public static let other = "cardNetwork.other"

    public static let all = [visa, mastercard, maestro, amex, other]
}
