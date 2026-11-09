import Foundation

/// A bank card's full number never stays in the binder: not in what a document's text
/// keeps, not in a field, a row under Date importante, a note or any other words a record
/// keeps, not in search, the iPhone's search, backups or logs. Only the last four digits are
/// kept. One set of rules, here, used wherever text enters or leaves:
/// - every capture result, before the review or anything else sees it (`CaptureResult.withoutCardNumbers`);
/// - everything kept: the unit of work masks the words of every record it saves, whoever
///   wrote them, an import included (`FreeText`), fields through `sanitizing`;
/// - a secret, before it is sealed (`SecretFields.sealing`);
/// - search and the iPhone's search (`SearchPrivacy.redacting`).
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
///   with no spaces (a meter's, a contract's) stays as it is.
/// - **On a bank card** (`strict`): any run of eight digits or more, whatever it starts
///   with or whether its check digit passes, since a misread digit must not let the rest
///   through.
///
/// A number taken out is written as its last four digits after a mask: "•••• 4821".
public enum PaymentCardNumbers {
    /// What stands for the digits taken out.
    public static let mask = "••••"
    /// A masked number with its last four digits ("•••• 4821"), for taking it out whole.
    public static let maskedPattern = #"(?:••••[ -]?)+\d{0,4}"#

    /// The text with every card number in it masked, keeping only the last four digits.
    public static func redact(_ text: String, strict: Bool = false) -> String {
        guard text.contains(where: \.isNumber) else { return text }
        var result = text
        for run in (strict ? runs(in: text, strict: true) : cardNumbers(in: text)).reversed() {
            result.replaceSubrange(run.range, with: run.masked)
        }
        return result
    }

    /// Whether the text holds something shaped like a card number (the "anywhere" rule).
    public static func containsCardNumber(_ text: String) -> Bool {
        guard text.contains(where: \.isNumber) else { return false }
        return !cardNumbers(in: text).isEmpty
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

    /// The same values with every text masked by the "anywhere" rule, and the fields that
    /// keep only the last digits (`DocumentFields.cardLastFour`) cut to them.
    public static func sanitizing(_ values: FieldValues) -> FieldValues {
        // A value this build can't read is masked the same way, wherever text sits in it.
        var result = values.mappingUnreadable { redacting($0) }
        for (key, value) in values.storage {
            // A sealed code is the secret's own business, never rewritten.
            guard case .text(let text) = value, !SecretSealer.isSealed(text) else { continue }
            if key == DocumentFields.cardLastFour {
                result[key] = lastFour(of: text).map(FieldValue.text)
            } else {
                let masked = redact(text)
                if masked != text { result[key] = .text(masked) }
            }
        }
        return result
    }

    /// Rows under Date importante with every card number masked, in their labels and values and
    /// in the rows this build can't read. A secret row's sealed code is the secret's own business.
    public static func sanitizing(_ facts: KeptList<CustomFact>) -> KeptList<CustomFact> {
        let masked = facts.items.map { fact in
            var fact = fact
            fact.label = redact(fact.label)
            if !SecretSealer.isSealed(fact.value) { fact.value = redact(fact.value) }
            return fact
        }
        return facts.replacingItems(masked).mappingUnreadable { redacting($0) }
    }

    /// Raw JSON a newer build wrote, with any card number in its text masked; sealed codes stay.
    public static func redacting(_ raw: JSONValue) -> JSONValue {
        raw.mappingStrings { SecretSealer.isSealed($0) ? $0 : redact($0) }
    }

    // MARK: - Runs of digits

    struct Run {
        let range: Range<String.Index>
        let digits: String
        /// Where each group of digits sits, in order: the pieces between single spaces or dashes.
        let groups: [Range<String.Index>]
        /// How many digits each group has.
        let groupSizes: [Int]
        /// The whole run of digits found in the text, not a part of a longer one.
        let isWhole: Bool

        init(groups: ArraySlice<Range<String.Index>>, in text: String, isWhole: Bool) {
            self.groups = Array(groups)
            self.range = (groups.first?.lowerBound ?? text.startIndex)..<(groups.last?.upperBound ?? text.startIndex)
            let pieces = groups.map { text[$0].filter { $0.isASCII && $0.isNumber } }
            self.digits = pieces.joined()
            self.groupSizes = pieces.map(\.count)
            self.isWhole = isWhole
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
        var isCardNumber: Bool {
            guard (14...19).contains(digits.count), let brand = PaymentCardNumbers.brand(of: digits), brand.lengths.contains(digits.count) else { return false }
            if !isWhole { return printedLikeACard && PaymentCardNumbers.passesLuhn(digits) }
            return PaymentCardNumbers.passesLuhn(digits) || (groupedInFours && digits.count == 16)
        }

        var masked: String {
            digits.count >= 12 ? "\(PaymentCardNumbers.mask) \(digits.suffix(4))" : PaymentCardNumbers.mask
        }
    }

    /// Runs of digits with at most one space or dash between them, not part of a longer
    /// run: twelve digits or more, or (`strict`) eight or more.
    static func runs(in text: String, strict: Bool) -> [Run] {
        let least = strict ? 8 : 12
        let pattern = #"(?<!\d[ -]?)\d(?:[ -]?\d){"# + String(least - 1) + #",}(?![ -]?\d)"#
        return TextPattern.matches(pattern, in: text, caseInsensitive: false).map { match in
            Run(groups: groups(in: text, range: match.range)[...], in: text, isWhole: true)
        }
    }

    /// The card numbers in the text by the "anywhere" rule, in order: a whole run of digits
    /// that is one, else the parts of a longer run that are (`parts(of:in:)`).
    static func cardNumbers(in text: String) -> [Run] {
        runs(in: text, strict: false).flatMap { run in run.isCardNumber ? [run] : parts(of: run, in: text) }
    }

    /// The card numbers inside a run that isn't one as a whole: a card number printed next to
    /// other digits ("12 4111 1111 1111 1111", "4111-1111-1111-1111-27"). Only parts that
    /// begin and end where the run's groups do are tried, from the left and the longest first
    /// at each place; a part is taken when it is a card number (`isCardNumber`: printed like a
    /// card and passing the Luhn check). Digits with nothing between them stay one number.
    static func parts(of run: Run, in text: String) -> [Run] {
        let sizes = run.groupSizes
        guard sizes.count >= 2 else { return [] }
        let cardLengths = 14...19
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
                .first(where: \.isCardNumber)
            if let part {
                found.append(part)
                start += part.groups.count
            } else {
                start += 1
            }
        }
        return found
    }

    /// The groups of digits in `range`: the pieces between its spaces and dashes.
    private static func groups(in text: String, range: Range<String.Index>) -> [Range<String.Index>] {
        var groups: [Range<String.Index>] = []
        var groupStart: String.Index?
        var index = range.lowerBound
        while index < range.upperBound {
            let next = text.index(after: index)
            if text[index] == " " || text[index] == "-" {
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

    public static var options: [ChoiceOption] {
        [
            ChoiceOption(key: visa, label: "Visa", aliases: ["Visa Debit", "Visa Electron", "Visa Classic", "Visa Gold", "Visa Platinum"]),
            ChoiceOption(key: mastercard, label: "Mastercard", aliases: ["MasterCard", "Debit Mastercard", "Mastercard Gold", "World Mastercard"]),
            ChoiceOption(key: maestro, label: "Maestro"),
            ChoiceOption(key: amex, label: "American Express", aliases: ["Amex"]),
            ChoiceOption(key: other, label: String(localized: "Altă rețea"), aliases: ["Altul"]),
        ]
    }

    /// The network's name: "Visa".
    public static func label(for key: String?) -> String? {
        key.flatMap { options.option(for: $0)?.label }
    }

    /// The words that name a network on the card, folded, most specific first.
    static let words: [(network: String, names: [String])] = [
        (maestro, ["maestro"]),
        (mastercard, ["mastercard", "master card"]),
        (amex, ["american express", "amex"]),
        (visa, ["visa"]),
    ]

    /// The network the card's printed words name, matched as whole words.
    static func read(in folded: String) -> String? {
        words.first { entry in entry.names.contains { CaptureText.containsWord($0, inFolded: folded) } }?.network
    }
}
