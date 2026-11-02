import Foundation

/// Decides what kind of document a capture is, from the MRZ (when present) and weighted keywords.
public enum DocumentClassifier {

    public struct Classification: Sendable, Hashable {
        public let kind: CaptureDocumentKind
        /// 0…1. High when one kind clearly wins, low when the text is ambiguous.
        public let confidence: Double
    }

    /// Weighted keywords per kind, matched against folded text (no diacritics, lowercase).
    /// Identity documents bring theirs from their templates (`IdentityTemplates`).
    static let signals: [CaptureDocumentKind: [(String, Double)]] = otherSignals.merging(IdentityTemplates.classifierSignals) { $1 }

    private static let otherSignals: [CaptureDocumentKind: [(String, Double)]] = [
        .vehicleRegistration: [("certificat de inmatriculare", 4), ("talon", 2), ("d.1", 1), ("d.3", 1), ("civ", 1), ("cartea de identitate a vehiculului", 4)],
        .rcaPolicy: [("rca", 3), ("raspundere civila auto", 4), ("asigurare obligatorie", 2), ("bonus-malus", 2), ("bonus malus", 2), ("carte verde", 1)],
        .insurancePolicy: [("polita", 2), ("asigurare", 1), ("casco", 3), ("pad", 1), ("paid", 1), ("asigurator", 1), ("prima de asigurare", 2), ("suma asigurata", 2), ("franciza", 2)],
        .utilityInvoice: [("energie electrica", 3), ("gaze naturale", 3), ("cod client", 2), ("cod loc de consum", 3), ("pod", 1), ("index", 1), ("kwh", 2), ("consum", 1), ("abonament", 1), ("apa rece", 2), ("canalizare", 2)],
        .serviceInvoice: [("manopera", 3), ("deviz", 3), ("service auto", 3), ("km bord", 2), ("kilometraj", 2), ("piese", 1), ("placute", 1), ("filtru", 1), ("schimb ulei", 2), ("nr. inmatriculare", 1), ("factura", 1)],
        // A receipt printed with its warranty terms is still the receipt; "bon fiscal" outweighs warranty wording.
        .fiscalReceipt: [("bon fiscal", 6), ("numerar", 1), ("rest", 1), ("tva a", 1), ("card", 1), ("total", 1)],
        .warrantyCertificate: [("certificat de garantie", 4), ("termen de garantie", 3), ("garantie", 1), ("s/n", 1), ("serie produs", 2)],
        .itpReport: [("inspectie tehnica periodica", 4), ("inspectia tehnica periodica", 4), ("itp", 3), ("rar", 1), ("statie itp", 2), ("valabila pana la", 1)],
        .veterinaryRecord: [("vaccin", 2), ("antirabic", 3), ("microcip", 3), ("deparazitare", 3), ("medic veterinar", 3), ("cabinet veterinar", 3), ("pasaport pentru animale", 4), ("carnet de sanatate", 2)],
        .medicalResult: [("buletin de analize", 4), ("rezultat", 1), ("valori de referinta", 3), ("interval biologic", 3), ("hemoglobina", 2), ("glicemie", 2), ("colesterol", 2), ("medic", 1), ("clinica", 1)],
    ]

    public static func classify(text: CaptureText, mrz: MRZParser.Result?) -> Classification {
        if let mrz {
            return Classification(kind: mrz.isPassport ? .passport : .identityCard, confidence: mrz.allChecksValid ? 0.98 : 0.8)
        }
        let haystack = text.joinedFolded
        var scores: [CaptureDocumentKind: Double] = [:]
        for (kind, words) in signals {
            scores[kind] = words.reduce(0) { total, signal in
                total + (containsWord(signal.0, in: haystack) ? signal.1 : 0)
            }
        }
        // An RCA policy is also an insurance policy; prefer the specific kind when RCA terms are present.
        if let rca = scores[.rcaPolicy], rca >= 3 { scores[.insurancePolicy] = (scores[.insurancePolicy] ?? 0) * 0.5 }
        // A fiscal receipt beats a generic invoice when "bon fiscal" is printed.
        if haystack.contains("bon fiscal") { scores[.serviceInvoice] = (scores[.serviceInvoice] ?? 0) * 0.5 }

        // Ties go to the kind listed first in `CaptureDocumentKind`, so the result never depends on dictionary order.
        let order = Dictionary(uniqueKeysWithValues: CaptureDocumentKind.allCases.enumerated().map { ($1, $0) })
        let ranked = scores.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : (order[lhs.key] ?? 0) < (order[rhs.key] ?? 0)
        }
        guard let best = ranked.first, best.value >= 2 else {
            return Classification(kind: .other, confidence: 0.3)
        }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        let margin = (best.value - runnerUp) / best.value
        let strength = min(best.value / 6, 1)
        return Classification(kind: best.key, confidence: 0.4 + 0.5 * margin * strength + 0.1 * strength)
    }

    /// Whole-word match for short keywords (so "rca" doesn't match "marca"), substring match for phrases.
    static func containsWord(_ word: String, in text: String) -> Bool {
        guard word.count <= 4, !word.contains(" ") else { return text.contains(word) }
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return TextPattern.first(#"(?<![a-z0-9])"# + escaped + #"(?![a-z0-9])"#, in: text) != nil
    }
}
