import Foundation

// MARK: - Label tables of their own

/// Label tables for values printed in parts on documents read without a template (a
/// policy, an invoice, a talon): the labels of the whole and of the series, and the
/// labels of other fields that start the same way, so their numbers are never taken.
enum CompositeLabels {
    /// The words that introduce a part of a value and are never a part themselves, in
    /// capitals as `CompositeValue` reads them.
    static let partWords = ["NR", "NO", "NUMAR", "NUMARUL", "NUMBER", "SERIA", "SERIE", "SERIES"]

    /// A label's role in a composite's own table.
    enum Key: Hashable, Sendable {
        case value
        case other
    }

    /// Labels of other fields that begin like a part's label ("Nr. înmatriculare",
    /// "Serie șasiu"), shared by every table: longer wordings win, so these are never
    /// read as the start of a series or a number.
    static let otherFields: [LabelWording] = words([
        "nr. inmatriculare", "nr inmatriculare", "numar de inmatriculare", "numar inmatriculare", "nr. de inmatriculare",
        "nr. inregistrare", "numar de inregistrare", "nr. identificare", "nr identificare", "numar de identificare", "nr. de identificare",
        "serie sasiu", "seria sasiu", "seria de sasiu", "serie de sasiu", "serie civ", "seria civ", "serie motor", "seria motor",
        "serie contor", "seria contor", "seria contorului", "seria si numarul contorului", "serie si numar contor", "serie/numar contor",
        "serie produs", "seria produs", "nr. contract", "numar contract", "nr. client", "cod client",
        "nr. telefon", "nr. de telefon", "nr. crt", "nr. rate", "nr. rata",
    ])

    /// A policy's number: its row of the policy table (`CaptureKindProfile.policyLabels`),
    /// and the green card's header an RCA printed with its green card shows.
    static var policy: [(Key, [LabelWording])] {
        [
            (.value, CaptureKindProfile.labels(for: .policyNumber, in: CaptureKindProfile.policyLabels).map(LabelWording.words) + greenCardNumber),
            (.other, otherFields),
        ]
    }

    /// The header a green card prints over its number, the country's code, the insurer's
    /// and the number (field 4 of the Council of Bureaux model, in English beside the
    /// country's own language), as BAAR's Romanian models word it; an RCA printed with its
    /// green card shows it too. Read by the policy table and the green card's template.
    static let greenCardNumber: [LabelWording] = words([
        "codul tarii / codul asiguratorului / seria si numarul politei", "codul tarii/codul asiguratorului/seria si numarul politei",
        "codul tarii / codul asiguratorului / numarul", "codul tarii/codul asiguratorului/numarul",
        "country code / insurer's code / serial and policy numbers", "country code / insurer's code / number",
        "country code/insurer's code/number", "codul tarii", "country code",
    ])

    static let invoice: [(Key, [LabelWording])] = [
        (.value, [
            "nr. factura", "nr factura", "numar factura", "numarul facturii", "factura nr", "factura fiscala nr", "factura seria",
            "seria si numarul facturii", "serie si numar factura", "seria si numarul", "invoice no", "invoice number", "seria", "serie",
        ].map(LabelWording.words)),
        (.other, otherFields),
    ]

    static let vehicleCard: [(Key, [LabelWording])] = [
        (.value, ["serie civ", "seria civ", "nr. civ", "numar civ", "c.i.v.", "cartea de identitate a vehiculului"].map(LabelWording.words)),
        (.other, otherFields.filter { $0.words.map { !["serie civ", "seria civ"].contains($0) } ?? true }),
    ]

    /// A value of `shape`, read at the labels of `table`.
    static func read(_ shape: CompositeValue, labels table: [(Key, [LabelWording])], in text: CaptureText) -> CompositeValue.Found? {
        LabelledLayout(text: text, labels: table).composite(shape, for: .value)
    }

    private static func words(_ list: [String]) -> [LabelWording] { list.map(LabelWording.words) }
}

extension LabelWording {
    /// The words of a `words` label.
    var words: String? {
        if case .words(let words) = self { return words }
        return nil
    }
}
