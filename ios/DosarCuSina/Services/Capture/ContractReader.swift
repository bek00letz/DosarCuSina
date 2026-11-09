import Foundation

/// Reads what ties a bill or a contract to its ongoing service: what the service is,
/// the codes that identify it (client code, contract number, POD, CLC, the phone
/// number of a mobile plan), where it is supplied and whether the bank pays it by direct
/// debit, and, on a contract, its terms (the start, the minimum period and its end, the
/// monthly price).
///
/// The labels are data, one table read with `LabelledLayout`, so a new wording is a
/// new row, not new reading code. Pure: plain text in, fields out.
enum ContractReader {

    // MARK: - Labels

    /// Printed labels for a contract's values, matched as whole words in folded text.
    /// Longer wordings win, so "contract de abonament nr" is a number, never a price.
    static let labels: [(CaptureFieldKey, [String])] = [
        (.contractNumber, ["numar contract", "nr. contract", "nr contract", "contract nr", "contractul nr", "numarul contractului",
                           "contract de furnizare nr", "contract de abonament nr", "contract de prestari servicii nr",
                           "act aditional nr", "nr. contractului", "contract numarul"]),
        (.startDate, ["data intrarii in vigoare", "intra in vigoare la", "intra in vigoare", "data inceperii", "data incheierii",
                      "incheiat la data de", "incheiat astazi", "data semnarii", "data activarii", "incepand cu data de", "data de inceput"]),
        (.minimumMonths, ["perioada minima", "perioada contractuala", "durata minima", "durata contractului", "perioada initiala",
                          "perioada determinata", "durata minima a contractului"]),
        (.minimumPeriodEnd, ["perioada minima se incheie", "sfarsitul perioadei minime", "data de sfarsit a perioadei minime",
                             "perioada minima expira", "finalul perioadei minime"]),
        (.monthlyPrice, ["abonament lunar", "abonamentul lunar", "pret lunar", "pretul lunar", "tarif lunar", "cost lunar",
                         "valoare lunara", "pretul abonamentului", "tarif abonament", "pret abonament"]),
        (.clientCode, ["cod client", "cod abonat", "cont client"]),
        (.phoneNumber, ["numar de telefon", "nr. de telefon", "numar telefon", "nr. telefon", "nr telefon", "msisdn", "numarul de telefon"]),
    ]

    // MARK: - Reading

    /// A contract's values: its codes, its service and its terms.
    static func contractFields(in text: CaptureText, window: DateWindow) -> [CaptureField] {
        var fields = identifierFields(in: text)
        let layout = LabelledLayout(text: text, words: labels)

        if let (day, source) = layout.day(for: .startDate, window: window) {
            fields.append(field(.startDate, .day(day), 0.7, source))
        }
        if let found = layout.found(for: .minimumMonths) {
            if let months = months(in: found.folded) {
                fields.append(field(.minimumMonths, .number(Decimal(months)), 0.7, found.source))
            }
            // "Perioada minimă: 24 de luni, de la 15.03.2026 până la 14.03.2028".
            let dates = RomanianFieldExtractor.dates(inLine: found.folded, index: found.label.line, window: window)
            if dates.count >= 2, dates[0].day < dates[1].day {
                fields.append(field(.startDate, .day(dates[0].day), 0.65, found.source))
                fields.append(field(.minimumPeriodEnd, .day(dates[1].day), 0.7, found.source))
            } else if let only = dates.first, CaptureText.containsWord("pana", inFolded: found.folded) {
                fields.append(field(.minimumPeriodEnd, .day(only.day), 0.65, found.source))
            }
        }
        if let (day, source) = layout.day(for: .minimumPeriodEnd, window: window) {
            fields.append(field(.minimumPeriodEnd, .day(day), 0.75, source))
        }
        if let found = layout.found(for: .monthlyPrice),
           let amount = RomanianFieldExtractor.amounts(inLine: found.folded).first(where: { $0.amount > 0 }) {
            let currency = RomanianFieldExtractor.currency(inLine: found.folded) ?? RomanianFieldExtractor.dominantCurrency(in: text)
            fields.append(field(.monthlyPrice, .money(CaptureMoney(amount: amount.amount, currencyCode: currency)), 0.65, found.source))
        }
        return fields
    }

    /// The codes a bill or a contract quotes, and what the service is.
    static func identifierFields(in text: CaptureText) -> [CaptureField] {
        var fields: [CaptureField] = []
        let layout = LabelledLayout(text: text, words: labels)
        let raw = text.joinedOriginal
        // The contract's number, by the one rule for values printed in parts (`CompositeValue`).
        if let found = layout.composite(.contract, for: .contractNumber) {
            fields.append(field(.contractNumber, .text(found.value), found.quality == .conflicting ? found.quality.confidence : 0.7, found.source))
        }
        if let found = layout.found(for: .clientCode), let number = code(in: found.value) {
            fields.append(field(.clientCode, .text(number), 0.7, found.source))
        }
        if let pod = RomanianUtilityParser.shared.extractPodCode(in: RomanianUtilityParser.normalizeDiacritics(raw)) {
            fields.append(field(.podCode, .text(pod), 0.75, nil))
        }
        if let clc = RomanianUtilityParser.shared.extractClcCode(in: RomanianUtilityParser.normalizeDiacritics(raw)), clc.contains(where: \.isNumber) {
            fields.append(field(.clcCode, .text(clc), 0.75, nil))
        }
        if let found = layout.found(for: .phoneNumber), let phone = RomanianFieldExtractor.phones(inLine: found.folded).first(where: isMobileNumber) {
            fields.append(field(.phoneNumber, .text(displayPhone(phone)), 0.75, found.source))
        }
        let identifiers = Set(fields.map(\.key))
        if let service = serviceKind(in: text, identifiers: identifiers) {
            fields.append(field(.serviceKind, .text(service), 0.7, nil))
        }
        // Where it is supplied, and whether the bank pays it (`ContractReader+Supply`).
        if let address = supplyAddress(in: text) { fields.append(address) }
        if let directDebit = directDebit(in: text) { fields.append(directDebit) }
        return fields
    }

    private static func field(_ key: CaptureFieldKey, _ value: CaptureValue, _ confidence: Double, _ source: String?) -> CaptureField {
        CaptureField(key: key, value: value, confidence: confidence, sourceText: source, tier: .heuristic)
    }

    // MARK: - Values

    /// The first code-like word: letters, digits and separators, with at least one digit.
    static func code(in value: String) -> String? {
        let candidates = value.uppercased().split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" || $0 == ":" })
        return candidates.lazy
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".-/")) }
            .first { word in
                word.count >= 3 && word.count <= 30 && word.contains(where: \.isNumber)
                    && word.allSatisfy { $0.isLetter || $0.isNumber || "/-.".contains($0) }
                    && !["NR", "NR."].contains(word)
            }
    }

    /// A length in months: "24 de luni", "12 (douăsprezece) luni", "2 ani". Folded text.
    static func months(in folded: String) -> Int? {
        guard let match = TextPattern.first(#"(?<!\d)(\d{1,3})\s*(?:\([^)]*\)\s*)?(?:de\s+)?(luni|luna|ani|an)(?![a-z])"#, in: folded),
              let number = match[1].flatMap(Int.init), let unit = match[2] else { return nil }
        let months = unit.hasPrefix("an") ? number * 12 : number
        return plausibleMonths.contains(months) ? months : nil
    }

    /// The minimum periods contracts carry: a month to ten years.
    static let plausibleMonths = 1...120

    /// Romanian mobile numbers start with 07 (or +40 7).
    static func isMobileNumber(_ digits: String) -> Bool {
        national(digits).hasPrefix("07") && national(digits).count == 10
    }

    /// "0700000000" or "+40700000000" as "0700 000 000".
    static func displayPhone(_ digits: String) -> String {
        let number = national(digits)
        guard number.count == 10 else { return number }
        let characters = Array(number)
        return String(characters[0..<4]) + " " + String(characters[4..<7]) + " " + String(characters[7..<10])
    }

    /// The national form of a Romanian number: "+40 7…" and "0040 7…" become "07…".
    static func national(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        if digits.hasPrefix("0040") { return "0" + digits.dropFirst(4) }
        if digits.hasPrefix("40"), digits.count == 11 { return "0" + digits.dropFirst(2) }
        return digits
    }

    // MARK: - The service

    /// Words that name each service, weighted, in folded text.
    static let serviceSignals: [(service: String, words: [(String, Int)])] = [
        (ServiceKind.gas, [("gaze naturale", 3), ("gaz natural", 3), ("furnizare gaze", 3), ("cod loc de consum (clc)", 2), ("mc gaz", 2), ("consum gaz", 2)]),
        (ServiceKind.electricity, [("energie electrica", 3), ("energie activa", 3), ("energiei electrice", 3), ("kwh", 2), ("certificate verzi", 2)]),
        (ServiceKind.water, [("apa potabila", 3), ("apa rece", 2), ("canalizare", 3), ("apa-canal", 3), ("apa canal", 3), ("apa nova", 3), ("apavital", 3)]),
        (ServiceKind.mobile, [("telefonie mobila", 3), ("abonament mobil", 3), ("date mobile", 2), ("trafic date", 2), ("minute nationale", 2),
                              ("roaming", 2), ("msisdn", 2), ("cartela sim", 2), ("convorbiri", 1), ("sms", 1)]),
        (ServiceKind.internetTV, [("internet fix", 3), ("fibra optica", 3), ("televiziune", 3), ("cablu tv", 3), ("internet", 2),
                                  ("canale tv", 2), ("decodor", 2), ("router", 1), ("tv", 1)]),
    ]

    /// What the service is: the codes first (a CLC means gas, a POD electricity, a mobile
    /// number a phone plan), then the words that win clearly. Nil when it isn't clear.
    static func serviceKind(in text: CaptureText, identifiers: Set<CaptureFieldKey>) -> String? {
        let hasCLC = identifiers.contains(.clcCode), hasPOD = identifiers.contains(.podCode)
        if hasCLC != hasPOD { return hasCLC ? ServiceKind.gas : ServiceKind.electricity }
        let haystack = text.joinedFolded
        var scores = serviceSignals.map { signal in
            (signal.service, signal.words.reduce(0) { total, word in
                total + (CaptureText.containsWord(word.0, inFolded: haystack) ? word.1 : 0)
            })
        }
        if identifiers.contains(.phoneNumber), let index = scores.firstIndex(where: { $0.0 == ServiceKind.mobile }) {
            scores[index].1 += 3
        }
        let ranked = scores.filter { $0.1 >= 2 }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        if let second = ranked.dropFirst().first, second.1 == best.1 { return nil }
        return best.0
    }
}
