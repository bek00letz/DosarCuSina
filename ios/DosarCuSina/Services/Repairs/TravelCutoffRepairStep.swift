import Foundation
import SwiftData

// MARK: - Deadlines without their document's travel cut-off

/// A deadline whose document type now has a travel margin it was made without: a passport
/// added before the margin existed reminds 6 and 2 months before it expires and turns
/// amber only in its last month. The repair gives it its blueprint's profile for the
/// document's type (`ObligationBlueprint.reminders(for:)`): the margin, and leads counted
/// back from the cut-off. Grace and the follow-up after it lapses stay as they are.
///
/// It asks, because it changes when the person is reminded. Nothing names a document type:
/// any blueprint whose profile for these values has a margin is covered.
struct TravelCutoffStep: DataRepairStep {
    static let id = DataRepairStepID.travelCutoff
    var title: String { String(localized: "Pașapoarte și călătorii", comment: "Repair group: passports get the day they stop being good for travel.") }

    struct Candidate {
        let obligation: Obligation
        let asset: Asset
        let expected: ReminderProfile
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return try context.fetch(FetchDescriptor<Obligation>(sortBy: [SortDescriptor(\.createdAt)])).compactMap { obligation in
            guard obligation.status == .active || obligation.status == .paused, !obligation.isExample,
                  let key = obligation.blueprintKey, let asset = obligation.asset,
                  let blueprint = templates[asset.templateKey]?.definition.blueprints.first(where: { $0.key == key }) else { return nil }
            let expected = blueprint.reminders(for: asset.values)
            guard expected.travelMarginDays > 0, obligation.travelMarginDays != expected.travelMarginDays else { return nil }
            return Candidate(obligation: obligation, asset: asset, expected: expected)
        }
    }

    /// The profile it gets: the blueprint's leads and margin, the person's grace and follow-up.
    static func repaired(_ current: ReminderProfile, expected: ReminderProfile) -> ReminderProfile {
        ReminderProfile(leadDays: expected.leadDays, consequence: current.consequence, graceDays: current.graceDays,
                        followUpAfterLapse: current.followUpAfterLapse, travelMarginDays: expected.travelMarginDays)
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).compactMap { candidate in
            let due = candidate.obligation.dueDay(in: scan.calendar)
            guard let cutoff = candidate.expected.urgencyRule.travelCutoff(before: due, calendar: scan.calendar) else { return nil }
            let margin = DurationWording.lead(days: candidate.expected.travelMarginDays)
            let sentence = ReminderWording.sentence(Self.repaired(candidate.obligation.reminders, expected: candidate.expected))
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.obligation.id.uuidString):\(candidate.expected.travelMarginDays)",
                step: Self.id,
                message: String(localized: "„\(candidate.asset.name)” e bun de călătorit doar până pe \(DosarFormat.longDay(cutoff)), cu \(margin) înainte să expire. Schimb când te anunț? \(sentence)",
                                comment: "Repair: a passport deadline gets the day it stops being good for travel, and reminders counted from it. Ends with the new reminder sentence."),
                subject: .travelCutoff(obligationID: candidate.obligation.id, marginDays: candidate.expected.travelMarginDays)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> String? in
            guard case .travelCutoff(let id, let margin) = finding.subject else { return nil }
            return "\(id.uuidString):\(margin)"
        })
        for candidate in try Self.candidates(in: context)
        where approved.contains("\(candidate.obligation.id.uuidString):\(candidate.expected.travelMarginDays)") {
            candidate.obligation.reminders = Self.repaired(candidate.obligation.reminders, expected: candidate.expected)
            candidate.obligation.updatedAt = Date()
        }
    }
}
