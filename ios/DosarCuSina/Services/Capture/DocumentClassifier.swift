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
        // A contract names itself; the minimum period and its length are what set it apart from a bill.
        .contract: [("contract de furnizare", 5), ("contract de abonament", 5), ("contract de prestari servicii", 4),
                    ("act aditional", 5), ("perioada minima", 4), ("perioada contractuala", 3), ("durata contractului", 3),
                    ("durata minima", 3), ("perioada initiala", 2), ("perioada determinata", 2), ("conditii generale", 1),
                    ("abonament lunar", 1), ("se incheie", 1), ("partile", 1)],
        .serviceInvoice: [("manopera", 3), ("deviz", 3), ("service auto", 3), ("km bord", 2), ("kilometraj", 2), ("piese", 1), ("placute", 1), ("filtru", 1), ("schimb ulei", 2), ("nr. inmatriculare", 1), ("factura", 1)],
        // A receipt printed with its warranty terms is still the receipt; "bon fiscal" outweighs warranty wording.
        .fiscalReceipt: [("bon fiscal", 6), ("numerar", 1), ("rest", 1), ("tva a", 1), ("card", 1), ("total", 1)],
        .warrantyCertificate: [("certificat de garantie", 4), ("termen de garantie", 3), ("garantie", 1), ("s/n", 1), ("serie produs", 2)],
        .itpReport: [("inspectie tehnica periodica", 4), ("inspectia tehnica periodica", 4), ("itp", 3), ("rar", 1), ("statie itp", 2), ("valabila pana la", 1)],
        .veterinaryRecord: [("vaccin", 2), ("antirabic", 3), ("microcip", 3), ("deparazitare", 3), ("medic veterinar", 3), ("cabinet veterinar", 3), ("pasaport pentru animale", 4), ("carnet de sanatate", 2)],
        .medicalResult: [("buletin de analize", 4), ("rezultat", 1), ("valori de referinta", 3), ("interval biologic", 3), ("hemoglobina", 2), ("glicemie", 2), ("colesterol", 2), ("medic", 1), ("clinica", 1)],
    ]

    /// Words only a bill prints: the amount to pay now. A contract's terms talk about
    /// due dates and payment too, so those aren't enough.
    static let billMarkers = ["total de plata", "sold de plata", "suma de plata", "total factura", "factura fiscala", "valoare de plata"]

    public static func classify(text: CaptureText, mrz: MRZParser.Result?) -> Classification {
        if let mrz {
            return Classification(kind: mrz.isPassport ? .passport : .identityCard, confidence: mrz.allChecksValid ? 0.98 : 0.8)
        }
        let haystack = text.joinedFolded
        var scores: [CaptureDocumentKind: Double] = [:]
        for (kind, words) in signals {
            scores[kind] = words.reduce(0) { total, signal in
                total + (CaptureText.containsWord(signal.0, inFolded: haystack, as: CaptureLexicon.wholeSignalWords.contains(signal.0) ? .word : nil) ? signal.1 : 0)
            }
        }
        // An RCA policy is also an insurance policy; prefer the specific kind when RCA terms are present.
        if let rca = scores[.rcaPolicy], rca >= 3 { scores[.insurancePolicy] = (scores[.insurancePolicy] ?? 0) * 0.5 }
        // A green card sent with its RCA policy (one PDF, the card as its last page) is the
        // policy: it sets the car's deadline. A green card alone never prints the policy's
        // own words, so where they weigh this much the card isn't a kind of its own.
        if let rca = scores[.rcaPolicy], rca >= Self.policyWithItsGreenCard { scores[.greenCard] = nil }
        // A contract mentions the gas, the POD and the client code a bill does; a bill
        // quotes its contract. What decides is whether there is something to pay.
        let isBill = billMarkers.contains { CaptureText.containsWord($0, inFolded: haystack) }
        if let contract = scores[.contract], contract >= 4, !isBill {
            scores[.utilityInvoice] = (scores[.utilityInvoice] ?? 0) * 0.5
        } else if isBill {
            scores[.contract] = (scores[.contract] ?? 0) * 0.5
        }
        // A fiscal receipt beats a generic invoice when "bon fiscal" is printed.
        if CaptureText.containsWord("bon fiscal", inFolded: haystack) { scores[.serviceInvoice] = (scores[.serviceInvoice] ?? 0) * 0.5 }
        // A whole card number printed on the page is the strongest sign of a bank card; a
        // receipt or a statement shows it masked, so it doesn't count there.
        if PaymentCardNumbers.containsCardNumber(text.joinedOriginal) { scores[.bankCard, default: 0] += cardNumberWeight }

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

    /// What a whole card number on the page weighs for a bank card.
    static let cardNumberWeight = 5.0

    /// What the RCA's own words weigh on a page that is the policy, whatever green card is
    /// printed with it: "RCA" and "răspundere civilă auto" together, or more.
    static let policyWithItsGreenCard = 7.0
}
