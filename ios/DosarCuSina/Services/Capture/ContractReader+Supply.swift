import Foundation

/// Two more things a bill or a contract says about its place and its reminder: where the
/// service is supplied, and whether the bank pays it by direct debit. Both are read from
/// wordings kept as data, the same for every provider, so a new wording is a new row.
extension ContractReader {

    // MARK: - The supply address

    /// What an address label names (`CaptureLexicon.supplyAddressLabels`). The payer's address
    /// and the consumption point's codes are labels too, so their values are never read as the
    /// supply address and "cod loc de consum" never reads as "loc de consum".
    enum AddressLabel: Hashable, Sendable {
        case supply
        case other
    }

    /// The longest supply address kept, so a paragraph read after a label is never taken for one.
    static let addressMaxLength = 160

    /// Where the service is supplied: the value of a supply label that reads as an address,
    /// with the next line when it only names the town ("Sector 3, București"). Never the
    /// billing address: only supply labels are read.
    static func supplyAddress(in text: CaptureText) -> CaptureField? {
        let layout = LabelledLayout(text: text, words: CaptureLexicon.supplyAddressLabels)
        for found in layout.allFound(for: .supply) {
            var value = cleanedAddress(found.value)
            var source = found.source
            if let last = found.lines.last, let next = continuation(after: last, in: text, layout: layout) {
                value += ", " + text.original[next].trimmingCharacters(in: .whitespaces)
                source += " " + text.original[next]
            }
            guard value.count <= addressMaxLength, PostalAddress(value) != nil else { continue }
            return CaptureField(key: .supplyAddress, value: .text(value), confidence: 0.7, sourceText: source, tier: .heuristic)
        }
        return nil
    }

    /// The value without a label printed in it ("Adresa: Str. …" under a "Loc de consum" header).
    private static func cleanedAddress(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " :-\t"))
        if RomanianText.fold(trimmed).hasPrefix("adresa") {
            trimmed = String(trimmed.dropFirst("adresa".count)).trimmingCharacters(in: CharacterSet(charactersIn: " :-\t"))
        }
        return trimmed
    }

    /// The line after an address that only names its town, sector or county, when it sits
    /// under it (on the same page, starting near it, close below).
    private static func continuation(after line: Int, in text: CaptureText, layout: LabelledLayout<AddressLabel>) -> Int? {
        let next = line + 1
        guard next < text.original.count, text.pages[next] == text.pages[line], !layout.isLabelLine(next),
              PostalAddress.namesOnlyThePlace(text.original[next]) else { return nil }
        if let above = text.boxes[line], let below = text.boxes[next] {
            let height = max(above.height, below.height)
            guard below.minY >= above.midY, below.minY - above.maxY <= 1.2 * height,
                  below.horizontalOverlap(above) > 0 || abs(below.minX - above.minX) <= 2 * height else { return nil }
        }
        return next
    }

    // MARK: - Direct debit

    /// How a bill says it is paid by direct debit ("debit direct", "debitare directă",
    /// "domiciliere"), folded. Each wording is a statement that it *is* paid so, never an
    /// offer to set it up.
    static let directDebitStatements: [String] = {
        var statements = [
            "se achita prin debit direct", "se va achita prin debit direct", "achitata prin debit direct", "achitat prin debit direct",
            "se plateste prin debit direct", "se va plati prin debit direct", "platita prin debit direct", "platit prin debit direct",
            "se incaseaza prin debit direct", "se va incasa prin debit direct", "incasata prin debit direct", "incasat prin debit direct",
            "plata se face prin debit direct", "plata se va face prin debit direct", "plata se efectueaza prin debit direct",
            "plata se va efectua prin debit direct", "plata facturii se face prin debit direct", "plata facturii se va face prin debit direct",
            "aveti debit direct activ", "ai debit direct activ", "debitul direct este activ", "debitul direct este activat",
            "factura domiciliata", "factura este domiciliata", "se achita prin domiciliere", "se plateste prin domiciliere",
            "mandat de debitare directa nr", "mandat de debit direct nr", "mandat debit direct nr",
            "va fi debitata din contul", "va fi debitat din contul", "se va debita din contul", "se debiteaza din contul",
        ]
        // A label with a yes: "Debit direct: activ", "Domiciliere: DA".
        for label in ["plata prin debit direct", "debit direct", "debitare directa", "domiciliere", "domiciliere facturi"] {
            for yes in ["da", "activ", "activa", "activat", "activata"] { statements.append(label + " " + yes) }
        }
        // How it is paid: "Modalitate de plată: Debit direct".
        for label in ["modalitate de plata", "modalitatea de plata", "mod de plata", "metoda de plata", "forma de plata", "tip plata", "tip de plata"] {
            for method in ["debit direct", "debitare directa", "domiciliere"] { statements.append(label + " " + method) }
        }
        return statements
    }()

    /// A heading that says it only when it stands alone on its line ("Plata prin debit direct")
    /// and nothing around it offers it or lists it among other ways to pay.
    static let directDebitHeadings: [String] = ["plata prin debit direct", "plata prin debitare directa", "plata prin domiciliere"]

    /// Words that turn a wording into a "no", an offer or one choice in a list of ways to pay:
    /// "nu aveți debit direct", "Modalități de plată: debit direct, card, numerar". Whole words, folded.
    static let directDebitDenials: [String] = [
        "nu", "fara", "inactiv", "inactiva", "dezactivat", "dezactivata", "neactivat", "neactivata", "anulat", "anulata",
        "niciun", "nicio", "www", "http", "https",
        "modalitati", "metode", "variante", "optiuni", "moduri", "numerar", "ghiseu", "card", "cardul", "online", "ordin de plata",
    ]

    /// Beginnings of the verbs that offer it: "activează", "înscrie-te", "alege", "poți".
    static let directDebitOffers: [String] = [
        "activeaz", "activati", "activeaza", "inscrie", "inscrieti", "alege", "alegeti", "poti", "puteti", "doresti", "doriti",
        "vrei", "vreti", "afla", "aflati", "solicita", "beneficiaz", "opteaz", "optati", "incearca", "descopera", "seteaz",
    ]

    /// The wordings above, compiled once for one reading (a page's lines, or one answer).
    private struct DirectDebitRules {
        let statements = ContractReader.directDebitStatements.map { RomanianText.Keyword($0, as: .word) }
        let denials = ContractReader.directDebitDenials.map { RomanianText.Keyword($0, as: .word) }
        let offers = ContractReader.directDebitOffers.map { RomanianText.Keyword($0, as: .stem) }

        func states(_ line: String) -> Bool {
            let folded = RomanianText.fold(line)
            guard statements.contains(where: { $0.isFound(inFolded: folded) }) else { return false }
            return !deniesOrOffers(folded)
        }

        /// A "no", an offer, a list of ways to pay, or a question ("Ai debit direct activ?").
        func deniesOrOffers(_ folded: String) -> Bool {
            folded.contains("?") || denials.contains { $0.isFound(inFolded: folded) } || offers.contains { $0.isFound(inFolded: folded) }
        }

        /// A heading alone on its line, with no offer or list on the lines around it.
        func isHeading(_ line: Int, in text: CaptureText) -> Bool {
            let words = RomanianText.words(text.original[line]).joined(separator: " ")
            guard ContractReader.directDebitHeadings.contains(words) else { return false }
            let around = [line - 1, line + 1].filter { text.folded.indices.contains($0) && text.pages[$0] == text.pages[line] }
            return !around.contains { deniesOrOffers(text.folded[$0]) }
        }
    }

    /// Whether a line (or a sentence) says the bill is paid by direct debit, and says
    /// nothing that turns it into a "no" or an offer. The one rule for every reader: the
    /// phone's and the AI provider's answer alike.
    static func statesDirectDebit(_ line: String) -> Bool {
        DirectDebitRules().states(line)
    }

    /// The printed statement that the bill is paid by direct debit, when there is one: on a
    /// line, across a line break, or as a heading standing alone.
    static func directDebit(in text: CaptureText) -> CaptureField? {
        let rules = DirectDebitRules()
        for index in text.original.indices {
            let line = text.original[index]
            var statement: String?
            if rules.states(line) || rules.isHeading(index, in: text) {
                statement = line
            } else if index + 1 < text.original.count, text.pages[index + 1] == text.pages[index],
                      !rules.states(text.original[index + 1]) {
                // "Factura se va achita prin debit" / "direct la data scadenței."
                let joined = line + " " + text.original[index + 1]
                if rules.states(joined) { statement = joined }
            }
            guard let statement else { continue }
            let printed = statement.trimmingCharacters(in: .whitespaces)
            return CaptureField(key: .directDebit, value: .text(printed), confidence: 0.7, sourceText: printed, tier: .heuristic)
        }
        return nil
    }
}
