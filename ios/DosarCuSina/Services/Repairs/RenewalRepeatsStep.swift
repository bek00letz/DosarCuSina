import Foundation
import SwiftData

// MARK: - Deadlines that close when done, kept repeating

/// A deadline whose closing replaces a document with a new one (`CompletionShape.replacesDocument`:
/// a personal document's renewal, a health file's European health card) closes when it is done,
/// whatever its repeat (`ObligationActions.complete`): the new document reminds of its own. A
/// health card deadline an earlier catalog made still repeats every two years, as its blueprint
/// said then, so its page says it repeats though closing it closes it. This finds every such
/// deadline still kept with a repeat, by what its completion does rather than by its name, and
/// stops it repeating, as its blueprint now says, asking first.
///
/// A correction, not a suggestion (`isSuggestion` stays false): the stored rule was saved by an
/// earlier catalog and now says something untrue on the deadline's page; nothing about it is a
/// better way of doing something that was right. Closing already ignores the repeat, so applying
/// it changes no reminder and no due day, only what the page says.
struct RenewalRepeatsStep: DataRepairStep {
    static let id = DataRepairStepID.renewalRepeats
    var title: String { String(localized: "Documente reînnoite", comment: "Repair group: deadlines that close when a document is replaced with a new one, kept repeating by an earlier version.") }

    static func candidates(in context: ModelContext) throws -> [Obligation] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return try context.fetch(FetchDescriptor<Obligation>(sortBy: [SortDescriptor(\.createdAt)])).filter { obligation in
            guard !obligation.isExample, obligation.recurrence.repeats else { return false }
            let template = obligation.asset.flatMap { templates[$0.templateKey] }?.definition
            return obligation.completion(template: template).replacesDocument
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { obligation in
            let place = obligation.asset?.name ?? obligation.title
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(obligation.id.uuidString)",
                step: Self.id,
                message: String(localized: "La „\(place)”, „\(obligation.title)” spune că se repetă, dar se închide când îl bifezi: documentul nou are termenul lui. Opresc repetarea?",
                                comment: "Repair: a deadline that closes when its document is replaced (a European health card) still repeats, as an earlier version made it. The first argument is the section, the second the deadline."),
                subject: .stopsRepeating(obligationID: obligation.id)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> UUID? in
            guard case .stopsRepeating(let id) = finding.subject else { return nil }
            return id
        })
        // Checked again: one that no longer repeats changes nothing.
        for obligation in try Self.candidates(in: context) where approved.contains(obligation.id) {
            obligation.recurrence = .none
        }
    }
}
