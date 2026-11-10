import Foundation

// MARK: - Label tables of their own

/// How a value printed in parts is read on documents without a template (a policy, an
/// invoice, a talon): its wordings are its kind's row (`CaptureKindProfile.labels`, an
/// invoice's in `commonLabels`), and beside them go the labels of other fields that start the
/// same way, so their numbers are never taken (`table(for:)`).
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

    /// The table of a value whose own wordings are `wordings` (its kind's row): those, and the
    /// other fields' labels that start the same way, but for any that is one of its own (the
    /// CIV's "serie civ" is the CIV's, never another field's).
    static func table(for wordings: [LabelWording]) -> [(Key, [LabelWording])] {
        [(.value, wordings), (.other, otherFields.filter { !wordings.contains($0) })]
    }

    /// The table of a value whose own wordings are the folded `labels` of its kind's row.
    static func table(for labels: [String]) -> [(Key, [LabelWording])] {
        table(for: labels.map(LabelWording.words))
    }

    /// A policy's number: its row of the policy table (`labels`, `CaptureKindProfile.policyLabels`'
    /// by default), and the green card's header an RCA printed with its green card shows.
    static func policy(_ labels: [String]) -> [(Key, [LabelWording])] {
        table(for: labels.map(LabelWording.words) + greenCardNumber)
    }

    /// A policy's number as the policy table words it.
    static var policy: [(Key, [LabelWording])] {
        policy(CaptureKindProfile.labels(for: .policyNumber, in: CaptureKindProfile.policyLabels))
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
