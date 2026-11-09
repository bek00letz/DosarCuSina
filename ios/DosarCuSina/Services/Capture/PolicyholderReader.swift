import Foundation

/// Reads who a policy insures: the owner or insured's name, and their CNP when printed
/// ("C.U.I. / C.N.P. Proprietar: …"). The labels are one table read with `LabelledLayout`,
/// so a new wording is a new row. The CNP is read only on the phone, only to find the
/// person among the household (`Policyholders`), and is never shown, kept or asked of the
/// AI provider.
enum PolicyholderReader {
    enum Label: Hashable {
        case name
        case personalNumber
        case other
    }

    static let labels: [(Label, [LabelWording])] = [
        (.name, [
            "nume/denumire proprietar", "nume / denumire proprietar", "denumire proprietar", "nume proprietar", "proprietar/utilizator",
            "proprietar / utilizator", "proprietarul vehiculului", "proprietar", "nume asigurat", "asiguratul", "asigurat", "contractant",
        ].map(LabelWording.words)),
        (.personalNumber, [
            "c.u.i. / c.n.p. proprietar", "c.u.i./c.n.p. proprietar", "cui / cnp proprietar", "cui/cnp proprietar", "c.n.p. proprietar",
            "cnp proprietar", "c.n.p./c.u.i.", "cnp/cui", "cui/cnp", "cnp asigurat", "c.n.p. asigurat",
        ].map(LabelWording.words)),
        (.other, CompositeLabels.otherFields + [
            "adresa", "adresa proprietar", "domiciliu", "telefon", "email", "e-mail", "seria", "serie", "nr. polita", "asigurator",
        ].map(LabelWording.words)),
    ]

    /// The policyholder's name and CNP, as printed, when the page names them.
    static func fields(in text: CaptureText) -> [CaptureField] {
        let layout = LabelledLayout(text: text, labels: labels)
        var fields: [CaptureField] = []
        if let found = layout.allFound(for: .name).lazy.compactMap({ found in
            RomanianFieldExtractor.personName(found.value.uppercased()).map { (found, $0) }
        }).first {
            fields.append(CaptureField(key: .policyholder, value: .text(CaptureMapping.titleCased(found.1)), confidence: 0.7, sourceText: found.0.source, tier: .heuristic))
        }
        if let cnp = layout.allFound(for: .personalNumber).lazy.compactMap({ found -> String? in
            let digits = found.value.filter { !$0.isWhitespace }
            guard let match = TextPattern.first(#"(?<!\d)(\d{13})(?!\d)"#, in: digits), let cnp = match[1],
                  RomanianFieldExtractor.isValidCNP(cnp) else { return nil }
            return cnp
        }).first {
            // Never its source line: the number stays out of anything shown.
            fields.append(CaptureField(key: .policyholderPersonalNumber, value: .text(cnp), confidence: 0.97, sourceText: nil, tier: .deterministic))
        }
        return fields
    }
}
