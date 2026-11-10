import Foundation
import SwiftData

// MARK: - Deadlines whose travel cut-off isn't their document's

/// A deadline whose travel margin isn't the one its document gives: a passport added before
/// margins existed reminds 6 and 2 months before it expires and turns amber only in its last
/// month; a document changed from a passport to another type before reminders followed the
/// type still counts from a cut-off it doesn't have.
///
/// It is a check of the one rule (`DeadlineReminders`): a deadline follows its blueprint's
/// profile for its section's values, and one whose reminders the person set follows only its
/// travel margin. Applying gives it that profile through the same path Editează uses, so the
/// person's own leads, grace and follow-up stay. It asks, because it changes when the person
/// is reminded. Nothing names a document type: any blueprint whose profile has a margin, or
/// lost one, is covered.
struct TravelCutoffStep: DataRepairStep {
    static let id = DataRepairStepID.travelCutoff
    var title: String { String(localized: "Pașapoarte și călătorii", comment: "Repair group: passports get the day they stop being good for travel.") }

    struct Candidate {
        let obligation: Obligation
        let asset: Asset
        let template: TemplateDefinition
        let expected: ReminderProfile
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return try context.fetch(FetchDescriptor<Obligation>(sortBy: [SortDescriptor(\.createdAt)])).compactMap { obligation in
            guard !obligation.isExample, let asset = obligation.asset,
                  let template = templates[asset.templateKey]?.definition,
                  let expected = DeadlineReminders.expected(for: obligation, blueprint: template.blueprints.first { $0.key == obligation.blueprintKey },
                                                            values: asset.values),
                  obligation.travelMarginDays != expected.travelMarginDays else { return nil }
            return Candidate(obligation: obligation, asset: asset, template: template, expected: expected)
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).compactMap { candidate in
            let sentence = ReminderWording.sentence(candidate.expected)
            let message: String
            if candidate.expected.hasTravelCutoff {
                let due = candidate.obligation.dueDay(in: scan.calendar)
                guard let cutoff = candidate.expected.urgencyRule.travelCutoff(before: due, calendar: scan.calendar) else { return nil }
                let margin = DurationWording.lead(days: candidate.expected.travelMarginDays)
                message = String(localized: "„\(candidate.asset.name)” e bun de călătorit doar până pe \(DosarFormat.longDay(cutoff)), cu \(margin) înainte să expire. Schimb când te anunț? \(sentence)",
                                 comment: "Repair: a passport deadline gets the day it stops being good for travel, and reminders counted from it. Ends with the new reminder sentence.")
            } else {
                message = String(localized: "La „\(candidate.asset.name)” contează doar data de expirare. Schimb când te anunț? \(sentence)",
                                 comment: "Repair: a document that is no longer a passport stops counting reminders from a travel cut-off. Ends with the new reminder sentence.")
            }
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.obligation.id.uuidString):\(candidate.expected.travelMarginDays)",
                step: Self.id,
                message: message,
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
            DeadlineReminders.refresh(candidate.obligation, template: candidate.template)
        }
    }
}
