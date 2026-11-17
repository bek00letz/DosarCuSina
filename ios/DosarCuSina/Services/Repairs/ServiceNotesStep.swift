import Foundation
import SwiftData

// MARK: - A service's rule kept as a deadline's note

/// Before a service of a category of one's own said its rule only where it is offered, worked out
/// each time (`ObligationBlueprint.shownNote`), its blueprint stored the rule as a note („La
/// 10.000 de km sau o dată pe an, ce vine întâi.”) and every deadline made from it kept a copy in
/// its notes. That copy was written with the phone's region, so it could read „La 10,000 de km”,
/// and it stops being true once how often changes, while the deadline's page already says how it
/// repeats (*Se repetă*). This finds a service deadline whose note is still such a copy, whatever
/// number it carries, and takes the note away, asking first. A note the person wrote, or changed,
/// isn't such a copy and stays.
struct ServiceNotesStep: DataRepairStep {
    static let id = DataRepairStepID.serviceNotes
    var title: String { String(localized: "Revizii", comment: "Repair group: service deadlines of a category of one's own that keep their rule as a note.") }

    /// Every way an earlier version wrote the rule, compared as values are (`RomanianText.compact`,
    /// so a number grouped any way, „10,000”, „10.000” or „10 000”, is the same digits): every so
    /// many kilometres, engine hours or months, in each of the plural forms the catalog gave it.
    static let earlierNotes = try! NSRegularExpression(
        pattern: #"^(?:LA(?:[0-9]+(?:DE)?KM|UNKILOMETRU|[0-9]+(?:DE)?OREDEMOTOR|OORADEMOTOR)SAUODATAPEANCEVINEINTAI|ODATA(?:LA[0-9]+(?:DE)?LUNI|PELUNA))$"#)

    /// Whether `note` is the rule an earlier version copied into a service deadline.
    static func isEarlierRule(_ note: String) -> Bool {
        let compact = RomanianText.compact(note)
        return earlierNotes.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) != nil
    }

    static func candidates(in context: ModelContext) throws -> [Obligation] {
        try context.fetch(FetchDescriptor<Obligation>(sortBy: [SortDescriptor(\.createdAt)])).filter { obligation in
            guard !obligation.isExample, let key = obligation.blueprintKey, CategorySwitches.isServiceBlueprint(key),
                  let notes = obligation.notes else { return false }
            return isEarlierRule(notes)
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { obligation in
            let notes = obligation.notes ?? ""
            let place = obligation.asset.map { "„\($0.name)”" } ?? "„\(obligation.title)”"
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(obligation.id.uuidString):\(RomanianText.compact(notes))",
                step: Self.id,
                message: String(localized: "La \(place), notița de la „\(obligation.title)” spune doar cât de des se face: „\(notes)”. O scot? Asta se vede oricum la Se repetă, mereu la zi.",
                                comment: "Repair: a service deadline of a category of one's own keeps its rule as a note, written by an earlier version. The first argument is the section, the second the deadline, the third the note."),
                subject: .serviceNote(obligationID: obligation.id)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> UUID? in
            guard case .serviceNote(let id) = finding.subject else { return nil }
            return id
        })
        // Checked again: a note changed since the list was made stays.
        for obligation in try Self.candidates(in: context) where approved.contains(obligation.id) {
            obligation.notes = nil
        }
    }
}
