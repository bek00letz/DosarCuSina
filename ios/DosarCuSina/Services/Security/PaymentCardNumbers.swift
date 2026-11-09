import Foundation

/// A bank card's full number never stays in the binder: not in what a document's text
/// keeps, not in a field, not in search, the iPhone's search, backups or logs. Only the
/// last four digits are kept. One set of rules, here, used wherever text enters or leaves:
/// - every capture result, before the review or anything else sees it (`CaptureResult.withoutCardNumbers`);
/// - what a filed document keeps of its text (`AttachmentActions`) and what an import brings;
/// - every field a section saves (`AssetActions`, through `sanitizing`);
/// - search and the iPhone's search (`SearchPrivacy.redacting`).
///
/// Two rules, by how sure the app is that the text is a card:
/// - **Anywhere:** a run of 14 to 19 digits (spaces or dashes between groups allowed) that
///   starts like a card number (Visa, Mastercard, Maestro, American Express and the rest)
///   and passes the Luhn check, or is printed in groups of four. Thirteen digits are never
///   taken, so a CNP stays as it is; an IMEI (15 digits, starting otherwise) or a 20-digit
///   health card number isn't a card number either.
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
        for run in runs(in: text, strict: strict).reversed() where run.isCardNumber || strict {
            result.replaceSubrange(run.range, with: run.masked)
        }
        return result
    }

    /// Whether the text holds something shaped like a card number (the "anywhere" rule).
    public static func containsCardNumber(_ text: String) -> Bool {
        runs(in: text, strict: false).contains(where: \.isCardNumber)
    }

    /// The last four digits of the card number in the text: a full number by the
    /// "anywhere" rule (or, `strict`, any run of twelve digits or more), else one already
    /// masked ("•••• 4821").
    public static func lastFour(in text: String, strict: Bool = false) -> String? {
        if let run = runs(in: text, strict: strict).first(where: { $0.isCardNumber || (strict && $0.digits.count >= 12) }) {
            return String(run.digits.suffix(4))
        }
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

    /// Raw JSON a newer build wrote, with any card number in its text masked; sealed codes stay.
    public static func redacting(_ raw: JSONValue) -> JSONValue {
        raw.mappingStrings { SecretSealer.isSealed($0) ? $0 : redact($0) }
    }

    // MARK: - Runs of digits

    struct Run {
        let range: Range<String.Index>
        let digits: String
        /// Printed in groups of four ("4111 1111 1111 1111").
        let groupedInFours: Bool

        /// A card number by the "anywhere" rule.
        var isCardNumber: Bool {
            guard (14...19).contains(digits.count), let brand = PaymentCardNumbers.brand(of: digits), brand.lengths.contains(digits.count) else { return false }
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
        return TextPattern.matches(pattern, in: text, caseInsensitive: false).compactMap { match in
            let raw = String(text[match.range])
            let digits = raw.filter { $0.isASCII && $0.isNumber }
            guard digits.count <= 19 || strict else { return nil }
            let groups = raw.split(whereSeparator: { $0 == " " || $0 == "-" })
            let grouped = groups.count >= 3 && groups.allSatisfy { $0.count == 4 }
            return Run(range: match.range, digits: digits, groupedInFours: grouped)
        }
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
