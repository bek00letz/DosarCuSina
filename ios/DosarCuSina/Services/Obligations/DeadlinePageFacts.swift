import Foundation
import SwiftData

/// What a deadline's page lists under its actions, each card only when it has something:
/// *Data trecută*, the last time it was done (its day, cost, note and who did it), and the
/// policy card, this deadline's own policy facts (number, claims phone, the policyholder's
/// class) and the documents on file. A chore shows neither until it has one; a card never
/// opens with a separator.
struct DeadlinePageFacts {
    /// A policy fact, in the order the card lists them.
    enum PolicyRow: Hashable {
        case policyNumber(String)
        case claimsPhone(String)
        /// The bonus-malus class of the person the policy insures, read from them.
        case ownerClass(String)
    }

    /// The last completion, newest first by `Obligation.history`.
    let lastCompletion: HistoryEntry?
    /// Only the facts it has.
    let policyRows: [PolicyRow]
    /// Documents filed with the deadline or with its last completion, newest first.
    let documents: [Attachment]

    init(lastCompletion: HistoryEntry?, policyNumber: String?, claimsPhone: String?, ownerClass: String?, documents: [Attachment]) {
        self.lastCompletion = lastCompletion
        self.policyRows = [policyNumber.map(PolicyRow.policyNumber), claimsPhone.map(PolicyRow.claimsPhone), ownerClass.map(PolicyRow.ownerClass)]
            .compactMap { $0 }
        self.documents = documents
    }

    /// The facts of `obligation`, by its blueprint's roles (`DeadlineFacts`): CASCO's page shows
    /// CASCO's policy, a car's RCA the class of the person it insures.
    @MainActor
    static func of(_ obligation: Obligation, template: TemplateDefinition?, in context: ModelContext) -> DeadlinePageFacts {
        let facts = DeadlineFacts.of(obligation, template: template)
        let ownerClass = facts.policyholder.flatMap { Policyholders.bonusMalus(ofPolicyholder: $0, among: Policyholders.people(in: context)) }
        return DeadlinePageFacts(lastCompletion: obligation.history.first, policyNumber: facts.policyNumber, claimsPhone: facts.claimsPhone,
                                 ownerClass: ownerClass, documents: documentsOnFile(obligation))
    }

    /// The documents filed with the deadline, and with the last time it was done, each once,
    /// newest first; archived ones are left out.
    static func documentsOnFile(_ obligation: Obligation) -> [Attachment] {
        var seen = Set<UUID>()
        let linked = (obligation.attachments ?? []) + (obligation.history.first?.attachments ?? [])
        return linked
            .filter { !$0.isArchived && seen.insert($0.id).inserted }
            .sorted { ($0.documentDay ?? CalendarDay($0.createdAt), $0.createdAt) > ($1.documentDay ?? CalendarDay($1.createdAt), $1.createdAt) }
    }

    /// *Data trecută* shows: it was done before.
    var showsLastTime: Bool { lastCompletion != nil }

    /// The policy card shows: a policy fact or a document.
    var showsPolicyCard: Bool { !policyRows.isEmpty || !documents.isEmpty }

    /// The policy card's heading: *Polița* when it holds a policy's facts, else *Acte în dosar*.
    var policyCardTitle: LocalizedStringResource {
        policyRows.isEmpty
            ? LocalizedStringResource("Acte în dosar", comment: "Deadline page: heading of the documents filed with it.")
            : LocalizedStringResource("Polița", comment: "Deadline page: heading of its policy's number, claims phone and class.")
    }

    /// *Acte în dosar* is named inside the card, under the policy's facts, only when both are there.
    var namesDocumentsInside: Bool { !policyRows.isEmpty && !documents.isEmpty }
}
