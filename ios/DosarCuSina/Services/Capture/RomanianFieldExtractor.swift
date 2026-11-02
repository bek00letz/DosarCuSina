import Foundation

/// Pattern-based extraction for Romanian documents: dates, amounts, tax IDs,
/// invoice numbers, plates, VINs, phone numbers, policy details, odometer readings.
///
/// Every function is pure and works on ``CaptureText``. The analyzer decides which
/// ones to run for which kind of document.
public enum RomanianFieldExtractor {

    // MARK: - Dates

    struct DateMatch {
        let day: CaptureDay
        let line: Int
        let range: Range<String.Index>
    }

    private static let monthNames: [(String, Int)] = [
        ("ianuarie", 1), ("februarie", 2), ("martie", 3), ("aprilie", 4), ("mai", 5), ("iunie", 6),
        ("iulie", 7), ("august", 8), ("septembrie", 9), ("octombrie", 10), ("noiembrie", 11), ("decembrie", 12),
        ("ian", 1), ("feb", 2), ("mar", 3), ("apr", 4), ("iun", 6), ("iul", 7), ("aug", 8),
        ("sept", 9), ("sep", 9), ("oct", 10), ("noi", 11), ("nov", 11), ("dec", 12),
    ]

    private static let romanMonths: [String: Int] = [
        "i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5, "vi": 6,
        "vii": 7, "viii": 8, "ix": 9, "x": 10, "xi": 11, "xii": 12,
    ]

    /// All dates on one folded line, in reading order.
    static func dates(inLine line: String, index: Int) -> [DateMatch] {
        var found: [DateMatch] = []

        for match in TextPattern.matches(#"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#, in: line) {
            if let y = match[1].flatMap(Int.init), let m = match[2].flatMap(Int.init), let d = match[3].flatMap(Int.init),
               let day = CaptureDay(year: y, month: m, day: d) {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        for match in TextPattern.matches(#"(?<![\d.])(\d{1,2})\s?[./-]\s?(\d{1,2})\s?[./-]\s?(\d{4}|\d{2})(?![\d])"#, in: line) {
            guard !found.contains(where: { $0.range.overlaps(match.range) }),
                  let d = match[1].flatMap(Int.init), let m = match[2].flatMap(Int.init),
                  let rawYear = match[3], let y = Int(rawYear) else { continue }
            let year = rawYear.count == 2 ? 2000 + y : y
            if let day = CaptureDay(year: year, month: m, day: d) {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        for match in TextPattern.matches(#"(?<!\d)(\d{1,2})[./-](x{0,1}i{1,3}|iv|v|vi{1,3}|ix|x|xi{1,2})[./-](\d{4})(?!\d)"#, in: line) {
            if let d = match[1].flatMap(Int.init), let m = match[2].flatMap({ romanMonths[$0.lowercased()] }),
               let y = match[3].flatMap(Int.init), let day = CaptureDay(year: y, month: m, day: d) {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        let names = monthNames.map(\.0).joined(separator: "|")
        for match in TextPattern.matches(#"(?<!\d)(\d{1,2})\s+("# + names + #")\.?,?\s+(\d{4})(?!\d)"#, in: line) {
            if let d = match[1].flatMap(Int.init),
               let m = match[2].flatMap({ name in monthNames.first { $0.0 == name.lowercased() }?.1 }),
               let y = match[3].flatMap(Int.init), let day = CaptureDay(year: y, month: m, day: d) {
                found.append(DateMatch(day: day, line: index, range: match.range))
            }
        }

        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func allDates(in text: CaptureText) -> [DateMatch] {
        text.folded.enumerated().flatMap { dates(inLine: $0.element, index: $0.offset) }
    }

    /// The first date after one of the labels: on the label's line (after the label), or on the next line.
    static func labelledDate(_ labels: [String], in text: CaptureText) -> (day: CaptureDay, source: String)? {
        for index in text.lines(containing: labels) {
            let line = text.folded[index]
            let labelEnd = labels.compactMap { line.range(of: $0)?.upperBound }.min() ?? line.startIndex
            if let match = dates(inLine: line, index: index).first(where: { $0.range.lowerBound >= labelEnd }) {
                return (match.day, text.original[index])
            }
            if index + 1 < text.folded.count, let match = dates(inLine: text.folded[index + 1], index: index + 1).first {
                return (match.day, text.original[index] + " " + text.original[index + 1])
            }
        }
        return nil
    }

    /// A validity period on one line ("valabilă de la 01.11.2026 până la 31.10.2027", "12.03.21-12.03.2031").
    static func validityPeriod(in text: CaptureText) -> (start: CaptureDay, end: CaptureDay, source: String)? {
        let labels = ["valabil", "perioada", "valabilitate", "validity", "de la", "asigurare"]
        for index in text.lines(containing: labels) {
            var found = dates(inLine: text.folded[index], index: index)
            if found.count < 2, index + 1 < text.folded.count {
                found += dates(inLine: text.folded[index + 1], index: index + 1)
            }
            if found.count >= 2, found[0].day < found[1].day {
                return (found[0].day, found[1].day, text.original[index])
            }
        }
        return nil
    }

    // MARK: - Money

    /// Parses Romanian and international amount formats into a `Decimal`:
    /// `1.234,56`, `1 234,56`, `1234.56`, `1,234.56`, `350`.
    public static func parseAmount(_ raw: String) -> Decimal? {
        var value = raw.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !value.isEmpty, value.contains(where: \.isNumber) else { return nil }
        // Ten or more digits with no separators is an identifier (CNP, IBAN digits,
        // account or meter number), never an amount on a household document.
        guard !(value.allSatisfy(\.isNumber) && value.count >= 10) else { return nil }
        let lastComma = value.lastIndex(of: ",")
        let lastDot = value.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            if comma > dot {
                value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        case (_?, nil):
            // In Romanian the comma is the decimal mark; several commas can only be thousands groups.
            value = value.filter { $0 == "," }.count > 1
                ? value.replacingOccurrences(of: ",", with: "")
                : value.replacingOccurrences(of: ",", with: ".")
        case let (nil, dot?):
            let decimals = value.distance(from: dot, to: value.endIndex) - 1
            if decimals == 3 || value.filter({ $0 == "." }).count > 1 {
                value = value.replacingOccurrences(of: ".", with: "")
            }
        case (nil, nil):
            break
        }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// An amount: `1.234,56`, `1 234,56` (space groups only with decimals), `1,234.56`, `350`, `350,00`.
    static let amountPattern = #"(?<![\d.,])(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,3}(?: \d{3})+,\d{1,2}|\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?!\d|[.,]\d)"#

    struct AmountMatch {
        let amount: Decimal
        let range: Range<String.Index>
    }

    /// Amounts on a line, skipping anything that is part of a date.
    static func amounts(inLine line: String) -> [AmountMatch] {
        let dateRanges = dates(inLine: line, index: 0).map(\.range)
        return TextPattern.matches(amountPattern, in: line).compactMap { match in
            guard !dateRanges.contains(where: { $0.overlaps(match.range) }),
                  let raw = match[1], let amount = parseAmount(raw) else { return nil }
            return AmountMatch(amount: amount, range: match.range)
        }
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

    private static let strongTotalLabels = [
        "total de plata", "total plata", "suma de plata", "rest de plata", "total general",
        "total factura", "valoare totala", "prima de asigurare", "prima totala", "total cu tva", "de plata",
    ]

    /// The amount to pay: a strongly labelled total first, then a plain "total" line that isn't VAT.
    static func total(in text: CaptureText) -> (money: CaptureMoney, source: String, strong: Bool)? {
        let fallbackCurrency = dominantCurrency(in: text)
        func amountNear(_ index: Int, after labels: [String]) -> CaptureMoney? {
            let line = text.folded[index]
            let labelEnd = labels.compactMap { line.range(of: $0)?.upperBound }.min() ?? line.startIndex
            let onLine = amounts(inLine: line).filter { $0.range.lowerBound >= labelEnd }
            if let last = onLine.last {
                return CaptureMoney(amount: last.amount, currencyCode: currency(inLine: line) ?? fallbackCurrency)
            }
            if index + 1 < text.folded.count, let next = amounts(inLine: text.folded[index + 1]).last {
                return CaptureMoney(amount: next.amount, currencyCode: currency(inLine: text.folded[index + 1]) ?? fallbackCurrency)
            }
            return nil
        }

        for label in strongTotalLabels {
            for index in text.lines(containing: [label]) {
                if let money = amountNear(index, after: [label]) {
                    return (money, text.original[index], true)
                }
            }
        }
        for index in text.lines(containing: ["total"]).reversed() {
            let line = text.folded[index]
            guard !line.contains("tva"), !line.contains("subtotal"), !line.contains("fara") else { continue }
            if let money = amountNear(index, after: ["total"]) {
                return (money, text.original[index], false)
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
        for (index, line) in text.folded.enumerated() {
            guard !nonItemWords.contains(where: { line.contains($0) }) else { continue }
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
                quantity = match[1].flatMap(parseAmount)
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
                amount: CaptureMoney(amount: amount.amount, currencyCode: currency),
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

    private static let companyPattern = #"\b(s\.?\s?r\.?\s?l\.?|s\.?\s?a\.?|s\.?\s?c\.?\s?s\.?|p\.?\s?f\.?\s?a\.?|i\.?\s?i\.?)(?=\s|$|,)"#
    private static let buyerLabels = ["client", "cumparator", "beneficiar", "asigurat", "contractant"]

    /// The company that issued the document: a line with a company suffix that isn't in the buyer's block.
    static func issuerName(in text: CaptureText) -> (name: String, line: Int)? {
        for (index, line) in text.folded.enumerated() {
            guard TextPattern.first(companyPattern, in: line) != nil else { continue }
            let inBuyerBlock = (max(0, index - 2)...index).contains { lineIndex in
                buyerLabels.contains { text.folded[lineIndex].contains($0) }
            }
            if inBuyerBlock { continue }
            var name = text.original[index]
            for prefix in ["Furnizor:", "Furnizor", "Vânzător:", "Vanzator:", "Emitent:", "S.C.", "SC "] where name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
            }
            name = name.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":,")))
            if name.count >= 3 { return (name, index) }
        }
        return nil
    }

    /// Invoice series and number ("Factura seria ABC nr. 12345", "Nr. factură: XYZ-2026-0001").
    static func invoiceNumber(in text: CaptureText) -> (value: String, source: String)? {
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
    static func vin(in text: CaptureText) -> (value: String, checksumValid: Bool, source: String)? {
        let pattern = #"(?<![A-Z0-9])([A-HJ-NPR-Z0-9]{17})(?![A-Z0-9])"#
        let labels = ["vin", "serie sasiu", "seria sasiu", "nr. identificare", "numar de identificare"]
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

    /// A phone number on a line mentioning claims or assistance, or on the line after it.
    static func claimsPhone(in text: CaptureText) -> (value: String, source: String)? {
        let labels = ["daune", "dauna", "avizare", "asistenta", "call center", "callcenter", "nonstop", "24/7", "suport clienti"]
        for index in text.lines(containing: labels) {
            if let phone = phones(inLine: text.folded[index]).first { return (phone, text.original[index]) }
            if index + 1 < text.folded.count, let phone = phones(inLine: text.folded[index + 1]).first {
                return (phone, text.original[index + 1])
            }
        }
        return nil
    }

    /// The insurance policy's series and number, after a policy label.
    static func policyNumber(in text: CaptureText) -> (value: String, source: String)? {
        let labels = ["seria si numarul", "seria si nr", "nr. polita", "nr polita", "numar polita", "numarul politei", "polita nr", "polita seria", "polita rca seria", "serie polita"]
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

    /// RCA bonus-malus class (B0–B8, M1–M8).
    static func bonusMalus(in text: CaptureText) -> String? {
        for index in text.lines(containing: ["bonus", "malus", "clasa"]) {
            if let match = TextPattern.first(#"\b(b[0-8]|m[1-8])\b"#, in: text.folded[index]), let value = match[1] {
                return value.uppercased()
            }
        }
        return nil
    }

    /// An odometer reading. Prefers a labelled value ("Km bord: 86.420") over a bare "86420 km".
    static func odometer(in text: CaptureText) -> (km: Decimal, source: String, labelled: Bool)? {
        let number = #"(\d{1,3}(?:[. ]\d{3})+|\d{3,7})"#
        for (index, line) in text.folded.enumerated() {
            if let match = TextPattern.first(#"(?:kilometraj|km\s*bord|km\s*la\s*bord|odometru|rulaj|km\s*parcursi)\s*[:.]?\s*"# + number, in: line),
               let raw = match[1], let km = parseAmount(raw.replacingOccurrences(of: " ", with: "")) {
                return (km, text.original[index], true)
            }
        }
        for (index, line) in text.folded.enumerated() {
            if let match = TextPattern.first(number + #"\s*km\b"#, in: line),
               let raw = match[1], let km = parseAmount(raw.replacingOccurrences(of: " ", with: "")), km >= 100 {
                return (km, text.original[index], false)
            }
        }
        return nil
    }

    /// Warranty length in months ("Termen de garanție: 24 luni", "garanție 2 ani").
    static func warrantyMonths(in text: CaptureText) -> (months: Int, source: String)? {
        for index in text.lines(containing: ["garanti"]) {
            if let match = TextPattern.first(#"garanti\w*[^\d\n]{0,25}(\d{1,3})\s*(luni|luna|ani|an)\b"#, in: text.folded[index]),
               let count = match[1].flatMap(Int.init), let unit = match[2] {
                let months = unit.hasPrefix("an") ? count * 12 : count
                if (1...240).contains(months) { return (months, text.original[index]) }
            }
        }
        return nil
    }

    /// A 15-digit ISO pet microchip number.
    static func microchip(in text: CaptureText) -> (value: String, source: String)? {
        for (index, line) in text.folded.enumerated() {
            let compact = line.replacingOccurrences(of: " ", with: "")
            if let match = TextPattern.first(#"(?<!\d)(\d{15})(?!\d)"#, in: compact), let value = match[1],
               line.contains("cip") || line.contains("transponder") || value.hasPrefix("642") {
                return (value, text.original[index])
            }
        }
        return nil
    }

    /// A serial number after "S/N", "Serie", "Seria produs" or "IMEI".
    static func serialNumber(in text: CaptureText) -> (value: String, source: String)? {
        for (index, line) in text.original.enumerated() {
            if let match = TextPattern.first(#"(?:s/n|sn|serial|seria produs|serie produs|imei)\s*[:.#]?\s*([A-Z0-9][A-Z0-9-]{4,24})"#, in: line),
               let value = match[1] {
                return (value.uppercased(), text.original[index])
            }
        }
        return nil
    }

    // MARK: - Numbered document fields

    /// EU driving licence fields are numbered: `1.` surname, `2.` given names, `4a.` issue date,
    /// `4b.` expiry, `5.` licence number, `9.` categories.
    static func drivingLicenceFields(in text: CaptureText) -> [CaptureFieldKey: (CaptureValue, String)] {
        var result: [CaptureFieldKey: (CaptureValue, String)] = [:]
        for (index, line) in text.folded.enumerated() {
            let original = text.original[index]
            if TextPattern.first(#"^\s*4\s?b\b\.?"#, in: line) != nil, let day = dates(inLine: line, index: index).first?.day {
                result[.expiryDate] = (.day(day), original)
            } else if TextPattern.first(#"^\s*4\s?a\b\.?"#, in: line) != nil, let day = dates(inLine: line, index: index).first?.day {
                result[.issueDate] = (.day(day), original)
            } else if let match = TextPattern.first(#"^\s*5\.\s*([A-Z0-9]{5,14})\b"#, in: original) , let value = match[1] {
                result[.documentNumber] = (.text(value.uppercased()), original)
            } else if let match = TextPattern.first(#"^\s*1\.\s*([A-ZĂÂÎȘȚŞŢ -]{2,40})$"#, in: original), let value = match[1] {
                result[.surname] = (.text(value.trimmingCharacters(in: .whitespaces)), original)
            } else if let match = TextPattern.first(#"^\s*2\.\s*([A-ZĂÂÎȘȚŞŢ -]{2,40})$"#, in: original), let value = match[1] {
                result[.givenNames] = (.text(value.trimmingCharacters(in: .whitespaces)), original)
            } else if let match = TextPattern.first(#"^\s*9\.\s*([A-Z0-9 ,/]{1,30})$"#, in: original), let value = match[1] {
                result[.licenceCategories] = (.text(value.trimmingCharacters(in: .whitespaces)), original)
            }
        }
        return result
    }

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
