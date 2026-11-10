import Foundation

/// Pattern-based extraction for Romanian documents: dates, amounts, tax IDs,
/// invoice numbers, plates, VINs, phone numbers, policy details, odometer readings.
///
/// Every function is pure and works on ``CaptureText``. The analyzer decides which
/// ones to run for which kind of document.
public enum RomanianFieldExtractor {

    // MARK: - Dates

    struct DateMatch {
        let day: CalendarDay
        let line: Int
        let range: Range<String.Index>
    }

    private static let monthNames: [(String, Int)] = [
        ("ianuarie", 1), ("februarie", 2), ("martie", 3), ("aprilie", 4), ("mai", 5), ("iunie", 6),
        ("iulie", 7), ("august", 8), ("septembrie", 9), ("octombrie", 10), ("noiembrie", 11), ("decembrie", 12),
        ("ian", 1), ("feb", 2), ("mar", 3), ("apr", 4), ("iun", 6), ("iul", 7), ("aug", 8),
        ("sept", 9), ("sep", 9), ("oct", 10), ("noi", 11), ("nov", 11), ("dec", 12),
        // English, as on bilingual passports ("12 IUN/JUN 31").
        ("jan", 1), ("may", 5), ("jun", 6), ("jul", 7),
    ]

    private static let romanMonths: [String: Int] = [
        "i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5, "vi": 6,
        "vii": 7, "viii": 8, "ix": 9, "x": 10, "xi": 11, "xii": 12,
    ]

    /// All dates on one folded line, in reading order. A two-digit year takes the century
    /// that puts the date inside `window` (see `DateWindow.resolve`), so "12.03.18" on an
    /// identity card is 2018 and a birth year "52" is 1952.
    static func dates(inLine line: String, index: Int, window: DateWindow = .aroundToday) -> [DateMatch] {
        var found: [DateMatch] = []

        for match in TextPattern.matches(#"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#, in: line) {
            if let y = match[1].flatMap(Int.init), let m = match[2].flatMap(Int.init), let d = match[3].flatMap(Int.init),
               let day = CalendarDay(printedYear: y, month: m, day: d) {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        for match in TextPattern.matches(#"(?<![\d.])(\d{1,2})\s?[./-]\s?(\d{1,2})\s?[./-]\s?(\d{4}|\d{2})(?![\d])"#, in: line) {
            guard !found.contains(where: { $0.range.overlaps(match.range) }),
                  let d = match[1].flatMap(Int.init), let m = match[2].flatMap(Int.init),
                  let rawYear = match[3], let y = Int(rawYear) else { continue }
            let resolved = rawYear.count == 2 ? window.resolve(twoDigitYear: y, month: m, day: d) : CalendarDay(printedYear: y, month: m, day: d)
            if let day = resolved {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        // Identity cards print dates with spaces: "03 07 1983". Strict, so a phone number
        // or an amount never reads as one: two-digit day and month, a four-digit year.
        for match in TextPattern.matches(#"(?<![\d.,])(?<!\d )(0[1-9]|[12]\d|3[01]) (0[1-9]|1[0-2]) ((?:19|20)\d{2})(?! ?\d)"#, in: line) {
            guard !found.contains(where: { $0.range.overlaps(match.range) }),
                  let d = match[1].flatMap(Int.init), let m = match[2].flatMap(Int.init), let y = match[3].flatMap(Int.init),
                  let day = CalendarDay(printedYear: y, month: m, day: d) else { continue }
            found.append(DateMatch(day: day, line: index, range: match.range))
        }

        for match in TextPattern.matches(#"(?<!\d)(\d{1,2})[./-](x{0,1}i{1,3}|iv|v|vi{1,3}|ix|x|xi{1,2})[./-](\d{4})(?!\d)"#, in: line) {
            if let d = match[1].flatMap(Int.init), let m = match[2].flatMap({ romanMonths[$0.lowercased()] }),
               let y = match[3].flatMap(Int.init), let day = CalendarDay(printedYear: y, month: m, day: d) {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        let names = monthNames.map(\.0).joined(separator: "|")
        for match in TextPattern.matches(#"(?<!\d)(\d{1,2})\s+("# + names + #")\.?,?\s+(\d{4})(?!\d)"#, in: line) {
            if let d = match[1].flatMap(Int.init),
               let m = match[2].flatMap({ name in monthNames.first { $0.0 == name.lowercased() }?.1 }),
               let y = match[3].flatMap(Int.init), let day = CalendarDay(printedYear: y, month: m, day: d) {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        // Passports print the month in two languages and may shorten the year: "12 IUN/JUN 31".
        for match in TextPattern.matches(#"(?<!\d)(\d{1,2})\s+("# + names + #")\s*/\s*(?:"# + names + #")\.?\s+(\d{4}|\d{2})(?!\d)"#, in: line) {
            guard !found.contains(where: { $0.range.overlaps(match.range) }),
                  let d = match[1].flatMap(Int.init),
                  let m = match[2].flatMap({ name in monthNames.first { $0.0 == name.lowercased() }?.1 }),
                  let rawYear = match[3], let y = Int(rawYear),
                  let day = rawYear.count == 2 ? window.resolve(twoDigitYear: y, month: m, day: d) : CalendarDay(printedYear: y, month: m, day: d)
            else { continue }
            found.append(DateMatch(day: day, line: index, range: match.range))
        }

        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func allDates(in text: CaptureText, window: DateWindow = .aroundToday) -> [DateMatch] {
        text.folded.enumerated().flatMap { dates(inLine: $0.element, index: $0.offset, window: window) }
    }

    /// The first date after one of the labels: on the label's line (after the label), or on the next line.
    static func labelledDate(_ labels: [String], in text: CaptureText, window: DateWindow = .aroundToday) -> (day: CalendarDay, source: String)? {
        for index in text.lines(containing: labels) {
            let line = text.folded[index]
            let labelEnd = labels.compactMap { line.range(of: $0)?.upperBound }.min() ?? line.startIndex
            if let match = dates(inLine: line, index: index, window: window).first(where: { $0.range.lowerBound >= labelEnd }) {
                return (match.day, text.original[index])
            }
            if index + 1 < text.folded.count, let match = dates(inLine: text.folded[index + 1], index: index + 1, window: window).first {
                return (match.day, text.original[index] + " " + text.original[index + 1])
            }
        }
        return nil
    }

    /// A validity period on one line after one of `labels` ("valabilă de la 01.11.2026 până la
    /// 31.10.2027", "12.03.21-12.03.2031"), or on the line after it.
    static func validityPeriod(in text: CaptureText, labels: [String], window: DateWindow = .aroundToday) -> (start: CalendarDay, end: CalendarDay, source: String)? {
        for index in text.lines(containing: labels) {
            var found = dates(inLine: text.folded[index], index: index, window: window)
            if found.count < 2, index + 1 < text.folded.count {
                found += dates(inLine: text.folded[index + 1], index: index + 1, window: window)
            }
            if found.count >= 2, found[0].day < found[1].day {
                return (found[0].day, found[1].day, text.original[index])
            }
        }
        return nil
    }

    // MARK: - Money

    /// An amount printed on a document, read by the one number reader (`RomanianNumber`).
    /// Ten or more digits with no separators is an identifier (CNP, IBAN digits, account or
    /// meter number), never an amount on a household document.
    static func amount(_ raw: String) -> RomanianNumber.Reading? {
        let digits = raw.filter { !$0.isWhitespace }
        guard !(digits.allSatisfy(\.isNumber) && digits.count >= 10) else { return nil }
        return try? RomanianNumber.read(raw, as: .money, from: .document).get()
    }

    /// An amount: `1.234,56`, `1 234,56` (space groups only with decimals), `1,234.56`, `350`, `350,00`.
    /// Digits glued to letters are never an amount: a bonus-malus class ("B6"), an instalment
    /// ("R1"), a product code ("5W30"). Only a currency may touch it ("350lei", "RON350").
    static let amountPattern = #"(?<![\d.,])(?:(?<=lei|ron|eur)|(?<!\p{L}))(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,3}(?: \d{3})+,\d{1,2}|\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?!\d|[.,]\d)(?:(?=(?:lei|ron|eur|euro)(?!\p{L}))|(?!\p{L}))"#

    /// A currency written right after an amount.
    private static let currencyAfter = #"^\s*(?:lei|ron|eur|euro|usd|€|\$)(?!\p{L})"#

    struct AmountMatch {
        let amount: Decimal
        /// Read by the Romanian rule where another reading was possible ("3,750"): "Verifică".
        let isAmbiguous: Bool
        let range: Range<String.Index>
        /// Its currency is written right after it ("1234.56 LEI"): an amount the line states.
        var hasCurrency = false
    }

    /// Amounts on a line, skipping anything that is part of a date.
    static func amounts(inLine line: String) -> [AmountMatch] {
        let dateRanges = dates(inLine: line, index: 0).map(\.range)
        return TextPattern.matches(amountPattern, in: line).compactMap { match in
            guard !dateRanges.contains(where: { $0.overlaps(match.range) }),
                  let raw = match[1], let reading = amount(raw) else { return nil }
            let currency = TextPattern.first(currencyAfter, in: String(line[match.range.upperBound...])) != nil
            return AmountMatch(amount: reading.value, isAmbiguous: reading.needsCheck, range: match.range, hasCurrency: currency)
        }
    }

    /// The amount a label states, from the text after it: the first amount followed by its
    /// currency ("Prima de asigurare 1234.56 LEI, Clasă Bonus-Malus: B6"), else the last.
    static func statedAmount(in matches: [AmountMatch]) -> AmountMatch? {
        matches.first(where: \.hasCurrency) ?? matches.last
    }

    /// Whether an amount on the line under a label is that label's value: nothing but a
    /// currency comes before it on its line. "Nr. rate 1 Valoare rate R1: 1234.56 Lei" is
    /// another label's value, never the one above it.
    static func standsAlone(_ match: AmountMatch, inLine line: String) -> Bool {
        let before = String(line[..<match.range.lowerBound])
            .replacingOccurrences(of: #"(?<!\p{L})(?:lei|ron|eur|euro|usd)(?!\p{L})"#, with: "", options: [.regularExpression, .caseInsensitive])
        return !before.contains(where: \.isLetter)
    }

    /// The currency named on a line, if any.
    static func currency(inLine line: String) -> String? {
        if TextPattern.first(#"\b(lei|ron)\b"#, in: line) != nil { return "RON" }
        if line.contains("€") || TextPattern.first(#"\beur(o)?\b"#, in: line) != nil { return "EUR" }
        if line.contains("$") || TextPattern.first(#"\busd\b"#, in: line) != nil { return "USD" }
        return nil
    }

    /// The currency used most in the document, defaulting to RON.
    static func dominantCurrency(in text: CaptureText) -> String {
        var counts: [String: Int] = [:]
        for line in text.folded {
            if let code = currency(inLine: line) { counts[code, default: 0] += 1 }
        }
        // Ties go to RON, then alphabetically, so the answer never depends on dictionary order.
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : (lhs.key != "RON" && (rhs.key == "RON" || lhs.key > rhs.key))
        }?.key ?? "RON"
    }

    /// A total that isn't labelled more strongly: the word alone, on a line that isn't VAT.
    static let plainTotalLabel = "total"
    /// Words that make a "total" line some other sum: VAT, a subtotal, a sum without VAT.
    static let notTheTotal = ["tva", "subtotal", "fara"]

    /// The amount to pay: a total labelled by one of `labels` first, strongest first (the kind's
    /// table, `CaptureKindProfile.labels(for: .total)`), then a plain "total" line that isn't VAT.
    /// `ambiguous` when the amount could have been read another way ("3,750"): the field gets "Verifică".
    static func total(in text: CaptureText, labels strongTotalLabels: [String] = CaptureKindProfile.commonLabels(for: .total))
        -> (money: Money, source: String, strong: Bool, ambiguous: Bool)? {
        let fallbackCurrency = dominantCurrency(in: text)
        func amountNear(_ index: Int, after labels: [String]) -> (money: Money, ambiguous: Bool)? {
            let line = text.folded[index]
            let labelEnd = labels.compactMap { line.range(of: $0)?.upperBound }.min() ?? line.startIndex
            let onLine = amounts(inLine: line).filter { $0.range.lowerBound >= labelEnd }
            if let stated = statedAmount(in: onLine) {
                return (Money(stated.amount, currency: currency(inLine: line) ?? fallbackCurrency), stated.isAmbiguous)
            }
            // The value under its label, never another label's on the next line.
            if index + 1 < text.folded.count {
                let nextLine = text.folded[index + 1]
                if let next = amounts(inLine: nextLine).first, standsAlone(next, inLine: nextLine) {
                    return (Money(next.amount, currency: currency(inLine: nextLine) ?? fallbackCurrency), next.isAmbiguous)
                }
            }
            return nil
        }

        for label in strongTotalLabels {
            for index in text.lines(containing: [label]) {
                if let found = amountNear(index, after: [label]) {
                    return (found.money, text.original[index], true, found.ambiguous)
                }
            }
        }
        for index in text.lines(containing: [plainTotalLabel]).reversed() {
            let line = text.folded[index]
            guard !notTheTotal.contains(where: { CaptureText.containsWord($0, inFolded: line) }) else { continue }
            if let found = amountNear(index, after: [plainTotalLabel]) {
                return (found.money, text.original[index], false, found.ambiguous)
            }
        }
        return nil
    }

    // MARK: - Line items

    private static let nonItemWords = [
        "total", "tva", "subtotal", "rest", "de plata", "cui", "cif", "cod fiscal", "nr.", "cont", "iban",
        "data", "tel", "telefon", "adresa", "banca", "capital", "reg. com", "j40", "numerar", "card",
        "rest", "achitat", "bon fiscal", "discount", "scadent", "client", "cumparator", "furnizor",
        "km bord", "kilometraj", "odometru", "garanti", "valabil",
    ]

    /// Lines that look like an invoice or receipt line: a description followed by an amount.
    static func lineItems(in text: CaptureText, currency: String, resolver: any CaptureComponentResolving) -> [CaptureLineItem] {
        var items: [CaptureLineItem] = []
        let nonItems = nonItemWords.map { RomanianText.Keyword($0) }
        for (index, line) in text.folded.enumerated() {
            guard !nonItems.contains(where: { $0.isFound(inFolded: line) }) else { continue }
            // A line carrying a personal number is never a billed item.
            guard personalNumber(in: CaptureText(text.original[index])) == nil else { continue }
            let found = amounts(inLine: line)
            guard let amount = found.last, amount.amount > 0 else { continue }
            // The description ends where the quantity starts ("2 buc"), or else at the line amount,
            // so product codes like "5W30" stay part of it.
            var quantity: Decimal?
            var descriptionEnd = amount.range.lowerBound
            if let match = TextPattern.matches(#"(?<![\w.,])(\d+(?:[.,]\d+)?)\s*(buc|bucati|bucata|l|litri|ore|h|set|kit|x)\b"#, in: line).last,
               match.range.upperBound <= amount.range.lowerBound {
                quantity = match[1].flatMap { RomanianNumber.value($0, as: .meterIndex, from: .document) }
                descriptionEnd = match.range.lowerBound
            }
            let descriptionPart = String(line[..<descriptionEnd])
            guard descriptionPart.filter(\.isLetter).count >= 3 else { continue }
            let original = text.original[index]
            let cut = original.index(original.startIndex, offsetBy: min(descriptionPart.count, original.count))
            let description = String(original[..<cut])
                .trimmingCharacters(in: CharacterSet(charactersIn: " -:.*\t"))
            guard !description.isEmpty else { continue }
            items.append(CaptureLineItem(
                description: description,
                quantity: quantity,
                amount: Money(amount.amount, currency: currency),
                componentKey: resolver.componentKey(for: description)
            ))
        }
        return items
    }

    // MARK: - Identifiers

    /// Romanian company tax ID (CUI/CIF) with its control digit checked (key 753217532).
    public static func isValidCUI(_ digits: String) -> Bool {
        guard digits.count >= 2, digits.count <= 10, digits.allSatisfy(\.isNumber) else { return false }
        let values = digits.compactMap(\.wholeNumberValue)
        guard let control = values.last else { return false }
        let body = Array(values.dropLast())
        let padded = Array(repeating: 0, count: 9 - body.count) + body
        let key = [7, 5, 3, 2, 1, 7, 5, 3, 2]
        let sum = zip(padded, key).reduce(0) { $0 + $1.0 * $1.1 }
        var expected = (sum * 10) % 11
        if expected == 10 { expected = 0 }
        return expected == control
    }

    /// The first tax ID after a CUI/CIF label, and whether its control digit is valid.
    static func taxID(in text: CaptureText) -> (value: String, valid: Bool, line: Int)? {
        let pattern = #"(?:c\.?\s?u\.?\s?i\.?|c\.?\s?i\.?\s?f\.?|cod\s+fiscal|cod\s+unic\s+de\s+inregistrare|cod\s+de\s+identificare\s+fiscala)\s*[:.]?\s*(ro)?\s*(\d{2,10})\b"#
        for (index, line) in text.folded.enumerated() {
            if let match = TextPattern.first(pattern, in: line), let digits = match[2] {
                let value = (match[1] != nil ? "RO" : "") + digits
                return (value, isValidCUI(digits), index)
            }
        }
        return nil
    }

    /// Whether a line names a company by its legal form ("S.R.L.", "S.A.", "PFA"): a firm,
    /// never a person.
    static func namesACompany(_ line: String) -> Bool {
        TextPattern.first(companyPattern, in: RomanianText.fold(line)) != nil
    }

    private static let companyPattern = #"\b(s\.?\s?r\.?\s?l\.?|s\.?\s?a\.?|s\.?\s?c\.?\s?s\.?|p\.?\s?f\.?\s?a\.?|i\.?\s?i\.?)(?=\s|$|,)"#
    private static let buyerLabels = ["client", "cumparator", "beneficiar", "asigurat", "contractant"]
    /// What comes before an issuer's name on its line and isn't part of it.
    private static let issuerPrefixes = ["Furnizor:", "Furnizor", "Vânzător:", "Vanzator:", "Emitent:", "S.C.", "SC "]

    /// The company that issued the document: a line with a company suffix that isn't in the buyer's block.
    static func issuerName(in text: CaptureText) -> (name: String, line: Int)? {
        for (index, line) in text.folded.enumerated() {
            guard TextPattern.first(companyPattern, in: line) != nil else { continue }
            let inBuyerBlock = (max(0, index - 2)...index).contains { lineIndex in
                buyerLabels.contains { text.folded[lineIndex].contains($0) }
            }
            if inBuyerBlock { continue }
            var name = text.original[index]
            for prefix in issuerPrefixes where name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
            }
            name = name.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":,")))
            if name.count >= 3 { return (name, index) }
        }
        return nil
    }

    /// Invoice series and number ("Factura seria ABC nr. 12345", "Nr. factură: XYZ-2026-0001"),
    /// read by the one rule for values printed in parts.
    static func invoiceNumber(in text: CaptureText) -> CompositeValue.Found? {
        CompositeLabels.read(.invoice, labels: CompositeLabels.invoice, in: text)
    }

    /// The reading before values printed in parts had one rule, kept switched off until
    /// that rule is proven on real documents (`invoiceNumber(in:)` replaces it).
    static func legacyInvoiceNumber(in text: CaptureText) -> (value: String, source: String)? {
        let patterns = [
            #"(?:factura|factura fiscala|invoice)[^\n]*?seri[ae]\s*[:.]?\s*([a-z]{1,6})\s*(?:nr\.?|numar|no\.?)\s*[:.]?\s*([a-z0-9-]{2,20})"#,
            #"seri[ae]\s*[:.]?\s*([a-z]{1,6})\s*(?:nr\.?|numar)\s*[:.]?\s*(\d{2,12})"#,
            #"(?:factura|factura fiscala|invoice)\s*(?:nr\.?|numar|no\.?)\s*[:.]?\s*()([a-z0-9][a-z0-9 /-]{2,20}[0-9])"#,
            #"nr\.?\s*factura\s*[:.]?\s*()([a-z0-9][a-z0-9/-]{2,20})"#,
        ]
        for (index, line) in text.folded.enumerated() {
            for pattern in patterns {
                if let match = TextPattern.first(pattern, in: line), let number = match[2] {
                    let series = (match[1] ?? "").uppercased()
                    let value = (series.isEmpty ? "" : series + " ") + number.uppercased().trimmingCharacters(in: .whitespaces)
                    return (value, text.original[index])
                }
            }
        }
        return nil
    }

    private static let countyCodes = Set([
        "AB", "AR", "AG", "BC", "BH", "BN", "BT", "BV", "BR", "BZ", "CS", "CL", "CJ", "CT", "CV", "DB", "DJ",
        "GL", "GR", "GJ", "HR", "HD", "IL", "IS", "IF", "MM", "MH", "MS", "NT", "OT", "PH", "SM", "SJ", "SB",
        "SV", "TR", "TM", "TL", "VS", "VL", "VN", "B",
    ])

    /// A Romanian registration plate, normalized to `B 123 ABC` / `CJ 12 ABC`.
    static func licensePlate(in text: CaptureText) -> (value: String, source: String)? {
        for (index, line) in text.original.enumerated() {
            for match in TextPattern.matches(#"\b([A-Z]{1,2})[ -]?(\d{2,3})[ -]?([A-Z]{3})\b"#, in: line, caseInsensitive: false) {
                guard let county = match[1], let digits = match[2], let letters = match[3],
                      countyCodes.contains(county),
                      digits.count == 2 || county == "B",
                      !letters.hasPrefix("I"), !letters.hasPrefix("O") else { continue }
                return ("\(county) \(digits) \(letters)", text.original[index])
            }
        }
        return nil
    }

    /// A 17-character VIN. The position-9 check digit is optional in Europe, so a match is
    /// reported with whether it also passes the check (stronger evidence when it does).
    /// After one of `labels`, a VIN printed in groups is read joined.
    static func vin(in text: CaptureText, labels: [String] = CaptureKindProfile.commonLabels(for: .vin))
        -> (value: String, checksumValid: Bool, source: String)? {
        let pattern = #"(?<![A-Z0-9])([A-HJ-NPR-Z0-9]{17})(?![A-Z0-9])"#
        for (index, line) in text.original.enumerated() {
            var candidates = [line.uppercased()]
            // VINs are sometimes printed in groups ("WVW ZZZ AUZ ..."); join the part after a VIN label.
            let folded = text.folded[index]
            if let labelEnd = labels.compactMap({ folded.range(of: $0)?.upperBound }).min() {
                let offset = folded.distance(from: folded.startIndex, to: labelEnd)
                candidates.append(String(line.dropFirst(offset)).uppercased().filter { !$0.isWhitespace && $0 != ":" })
            }
            for candidate in candidates {
                if let match = TextPattern.first(pattern, in: candidate, caseInsensitive: false),
                   let value = match[1], value.contains(where: \.isLetter), value.contains(where: \.isNumber) {
                    return (value, vinChecksumValid(value), text.original[index])
                }
            }
        }
        return nil
    }

    static func vinChecksumValid(_ vin: String) -> Bool {
        let transliteration: [Character: Int] = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
            "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
            "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9,
        ]
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        let characters = Array(vin)
        guard characters.count == 17 else { return false }
        var sum = 0
        for (index, character) in characters.enumerated() {
            guard let value = character.wholeNumberValue ?? transliteration[character] else { return false }
            sum += value * weights[index]
        }
        let remainder = sum % 11
        let expected: Character = remainder == 10 ? "X" : Character(String(remainder))
        return characters[8] == expected
    }

    /// Romanian phone numbers: mobile, landline, toll-free and short codes like `*1234`.
    static func phones(inLine line: String) -> [String] {
        let pattern = #"(?<!\d)((?:\+40|0040|0)\s?(?:7\d{2}|800|801|[23]\d{1,2})[\s.-]?\d{3}[\s.-]?\d{3,4}|\*\d{3,4})(?!\d)"#
        return TextPattern.matches(pattern, in: line).compactMap { match in
            match[1].map { $0.filter { $0.isNumber || $0 == "+" || $0 == "*" } }
        }
    }

    /// A phone number on a line with one of `labels` (claims, assistance), or on the line after it.
    static func claimsPhone(in text: CaptureText, labels: [String]) -> (value: String, source: String)? {
        for index in text.lines(containing: labels) {
            if let phone = phones(inLine: text.folded[index]).first { return (phone, text.original[index]) }
            if index + 1 < text.folded.count, let phone = phones(inLine: text.folded[index + 1]).first {
                return (phone, text.original[index + 1])
            }
        }
        return nil
    }

    /// The insurance policy's series and number, as one value, wherever and however they
    /// are printed (`CompositeValue`, `CompositeLabels.policy`).
    static func policyNumber(in text: CaptureText) -> CompositeValue.Found? {
        CompositeLabels.read(.policy, labels: CompositeLabels.policy, in: text)
    }

    /// The vehicle identity card's (CIV) series and number, as one value.
    static func civNumber(in text: CaptureText) -> CompositeValue.Found? {
        CompositeLabels.read(.vehicleCard, labels: CompositeLabels.vehicleCard, in: text)
    }

    /// The reading before values printed in parts had one rule, kept switched off until
    /// that rule is proven on real documents (`policyNumber(in:)` replaces it).
    static func legacyPolicyNumber(in text: CaptureText) -> (value: String, source: String)? {
        let labels = legacyPolicyLabels
        for index in text.lines(containing: labels) {
            let original = text.original[index]
            let folded = text.folded[index]
            let labelEnd = labels.compactMap { folded.range(of: $0)?.upperBound }.min() ?? folded.startIndex
            let offset = folded.distance(from: folded.startIndex, to: labelEnd)
            let tail = String(original.dropFirst(min(offset, original.count)))
            if let match = TextPattern.first(#"([A-Z0-9][A-Z0-9/ .-]{3,40}\d)"#, in: tail.uppercased(), caseInsensitive: false),
               let value = match[1] {
                let cleaned = value
                    .replacingOccurrences(of: "NR.", with: "NR")
                    .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":.")))
                return (cleaned, original)
            }
        }
        return nil
    }

    /// The labels the switched-off reading looked for (`CompositeLabels.policy` replaces them).
    private static let legacyPolicyLabels = [
        "seria si numarul", "seria si nr", "nr. polita", "nr polita", "numar polita", "numarul politei",
        "polita nr", "polita seria", "polita rca seria", "serie polita",
    ]

    /// RCA bonus-malus class (B0–B8, M1–M8), on a line with one of `labels`.
    static func bonusMalus(in text: CaptureText, labels: [String]) -> String? {
        for index in text.lines(containing: labels) {
            if let match = TextPattern.first(#"\b(b[0-8]|m[1-8])\b"#, in: text.folded[index]), let value = match[1] {
                return value.uppercased()
            }
        }
        return nil
    }

    /// An odometer reading. Prefers a value after one of `labels` ("Km bord: 86.420") over a
    /// bare "86420 km". A label's words may be printed together ("kmbord").
    static func odometer(in text: CaptureText, labels: [String] = CaptureKindProfile.commonLabels(for: .odometer))
        -> (km: Decimal, source: String, labelled: Bool)? {
        let number = #"(\d{1,3}(?:[., ]\d{3})+|\d{3,7})(?!\d|[.,]\d)"#
        let label = alternatives(labels, spaces: #"\s*"#)
        for (index, line) in text.folded.enumerated() {
            if let match = TextPattern.first(label + #"\s*[:.]?\s*"# + number, in: line),
               let raw = match[1], let km = RomanianNumber.value(raw, as: .kilometres, from: .document) {
                return (km, text.original[index], true)
            }
        }
        for (index, line) in text.folded.enumerated() {
            if let match = TextPattern.first(number + #"\s*km\b"#, in: line),
               let raw = match[1], let km = RomanianNumber.value(raw, as: .kilometres, from: .document), km >= 100 {
                return (km, text.original[index], false)
            }
        }
        return nil
    }

    /// Warranty length in months after one of `labels` ("Termen de garanție: 24 luni", "garanție 2 ani").
    static func warrantyMonths(in text: CaptureText, labels: [String]) -> (months: Int, source: String)? {
        let label = alternatives(labels)
        for index in text.lines(containing: labels) {
            if let match = TextPattern.first(label + #"\w*[^\d\n]{0,25}(\d{1,3})\s*(luni|luna|ani|an)\b"#, in: text.folded[index]),
               let count = match[1].flatMap(Int.init), let unit = match[2] {
                let months = unit.hasPrefix("an") ? count * 12 : count
                if (1...240).contains(months) { return (months, text.original[index]) }
            }
        }
        return nil
    }

    /// The country part of a chip implanted in Romania (ISO 3166 numeric code).
    static let romanianChipPrefix = "642"

    /// A 15-digit ISO pet microchip number: on a line with one of `labels`, or one implanted in Romania.
    static func microchip(in text: CaptureText, labels: [String]) -> (value: String, source: String)? {
        for (index, line) in text.folded.enumerated() {
            let compact = line.replacingOccurrences(of: " ", with: "")
            if let match = TextPattern.first(#"(?<!\d)(\d{15})(?!\d)"#, in: compact), let value = match[1],
               labels.contains(where: { CaptureText.containsWord($0, inFolded: line) }) || value.hasPrefix(romanianChipPrefix) {
                return (value, text.original[index])
            }
        }
        return nil
    }

    /// A serial number after one of `labels` ("S/N", "Seria produs", "IMEI").
    static func serialNumber(in text: CaptureText, labels: [String]) -> (value: String, source: String)? {
        let label = alternatives(labels)
        for (index, line) in text.original.enumerated() {
            if let match = TextPattern.first(label + #"\s*[:.#]?\s*([A-Z0-9][A-Z0-9-]{4,24})"#, in: line),
               let value = match[1] {
                return (value.uppercased(), text.original[index])
            }
        }
        return nil
    }

    /// A table's wordings as one group of a pattern, in their order: each one as printed,
    /// with `spaces` between its words.
    static func alternatives(_ labels: [String], spaces: String = " ") -> String {
        let wordings = labels.map { label in
            label.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: spaces)
        }
        return "(?:" + wordings.joined(separator: "|") + ")"
    }

    // MARK: - Numbered document fields

    /// Vehicle registration certificate fields: `A` plate, `B` first registration, `D.1` make, `D.3` model, `E` VIN.
    static func registrationFields(in text: CaptureText) -> [CaptureFieldKey: (CaptureValue, String)] {
        var result: [CaptureFieldKey: (CaptureValue, String)] = [:]
        for (index, line) in text.original.enumerated() {
            let folded = text.folded[index]
            if let match = TextPattern.first(#"^\s*d\.?\s?1\.?\s+(.{2,30})$"#, in: line), let value = match[1] {
                result[.make] = (.text(value.trimmingCharacters(in: .whitespaces)), line)
            } else if let match = TextPattern.first(#"^\s*d\.?\s?3\.?\s+(.{1,40})$"#, in: line), let value = match[1] {
                result[.model] = (.text(value.trimmingCharacters(in: .whitespaces)), line)
            } else if TextPattern.first(#"^\s*b\.?\s"#, in: folded) != nil, let day = dates(inLine: folded, index: index).first?.day {
                result[.firstRegistrationDate] = (.day(day), line)
            }
        }
        return result
    }
}
