import Foundation
import SwiftData

/// Repairs for data that earlier versions filed wrongly, before capture had one filer.
/// None of them runs by itself: each finds what it would change (`…Candidates`) so the
/// repair list (`DataRepairs`) can show it and ask, and repairs only what was approved.
/// Each is idempotent: running it again changes nothing more.
@MainActor
public struct CaptureRepairs {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Documents moved with their old links

    /// A document whose deadline or history entry belongs to another section than the
    /// document itself: it was moved here ("A photo already in the binder moves to where
    /// it's added now") and kept its links to the old place.
    public struct StaleDocumentLinks: Identifiable, Hashable, Sendable {
        public let attachmentID: UUID
        public let obligationID: UUID?
        public let historyEntryID: UUID?
        public var id: UUID { attachmentID }
    }

    /// Every document that still points at another section's deadline or history entry.
    public func staleDocumentLinkCandidates() throws -> [StaleDocumentLinks] {
        try context.fetch(FetchDescriptor<Attachment>()).compactMap { attachment in
            guard let home = attachment.asset?.id else { return nil }
            let staleObligation = attachment.obligation.flatMap { $0.asset?.id != home ? $0.id : nil }
            let staleEntry = attachment.historyEntry.flatMap { $0.asset?.id != home ? $0.id : nil }
            guard staleObligation != nil || staleEntry != nil else { return nil }
            return StaleDocumentLinks(attachmentID: attachment.id, obligationID: staleObligation, historyEntryID: staleEntry)
        }
    }

    /// Drops the old place's links from the documents the owner approved, in one save.
    /// The document stays where it is now, with its pages and everything read from it.
    public func dropStaleDocumentLinks(_ approved: [StaleDocumentLinks]) throws {
        let ids = Set(approved.map(\.attachmentID))
        try UnitOfWork.perform(in: context) {
            for attachment in try context.fetch(FetchDescriptor<Attachment>()) where ids.contains(attachment.id) {
                let home = attachment.asset?.id
                if let obligation = attachment.obligation, obligation.asset?.id != home { attachment.obligation = nil }
                if let entry = attachment.historyEntry, entry.asset?.id != home { attachment.historyEntry = nil }
            }
            try UnitOfWork.save(context)
        }
    }

    // MARK: Visits saved without their invoice

    /// A visit logged without a document while an invoice for it sits loose in the same
    /// section: the visit form was given a photo already in the binder and saved
    /// without it. The invoice is the only one filed in the week before the visit,
    /// or on its day, and belongs to no history entry.
    public struct VisitWithoutInvoice: Identifiable, Hashable, Sendable {
        public let visitID: UUID
        public let invoiceID: UUID
        public var id: UUID { visitID }
    }

    /// Visits that may have lost their invoice, each with the one invoice that fits.
    /// A visit with two possible invoices isn't offered: the owner would have to guess.
    public func visitsWithoutInvoiceCandidates(calendar: Calendar = .dosar) throws -> [VisitWithoutInvoice] {
        let visitKinds: Set<HistoryKind> = [.maintenance, .repair]
        var used = Set<UUID>()
        var found: [VisitWithoutInvoice] = []
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>()).sorted(by: { $0.occurredAt < $1.occurredAt }) {
            guard visitKinds.contains(entry.kind), entry.obligation == nil, (entry.attachments ?? []).isEmpty,
                  let asset = entry.asset else { continue }
            let visitDay = CalendarDay(entry.occurredAt, calendar: calendar)
            let weekBefore = visitDay.adding(days: -7, calendar: calendar)
            let loose = (asset.attachments ?? []).filter { invoice in
                guard invoice.kind == .invoice, invoice.historyEntry == nil, !used.contains(invoice.id) else { return false }
                let filed = CalendarDay(invoice.documentDate ?? invoice.createdAt, calendar: calendar)
                return filed >= weekBefore && filed <= visitDay
            }
            guard loose.count == 1, let invoice = loose.first else { continue }
            used.insert(invoice.id)
            found.append(VisitWithoutInvoice(visitID: entry.id, invoiceID: invoice.id))
        }
        return found
    }

    /// Links each approved invoice to its visit, in one save. An invoice already linked
    /// to an entry is left alone.
    public func linkInvoices(_ approved: [VisitWithoutInvoice]) throws {
        try UnitOfWork.perform(in: context) {
            let entries = Dictionary(try context.fetch(FetchDescriptor<HistoryEntry>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let documents = Dictionary(try context.fetch(FetchDescriptor<Attachment>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for pair in approved {
                guard let entry = entries[pair.visitID], let invoice = documents[pair.invoiceID], invoice.historyEntry == nil else { continue }
                invoice.historyEntry = entry
                if invoice.provider == nil { invoice.provider = entry.providers?.first }
            }
            try UnitOfWork.save(context)
        }
    }

    // MARK: The same firm twice

    /// Firms kept twice under the same name (the visit form and capture each made one):
    /// the one kept first, and the copies that would merge into it.
    public struct DuplicateProviders: Identifiable, Hashable, Sendable {
        public let keptID: UUID
        public let duplicateIDs: [UUID]
        public var id: UUID { keptID }
    }

    /// Every group of firms that are the same by `ProviderActions.findOrCreate`'s rule: the
    /// same CUI, or names that read the same. A chain counts as one group (A and B share a
    /// CUI, B and C a name).
    public func duplicateProviderCandidates() throws -> [DuplicateProviders] {
        let providers = try context.fetch(FetchDescriptor<Provider>()).filter { !$0.isExample }
        // Each firm starts in a group of its own; a shared name or CUI joins two groups.
        var group = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.id) })
        func root(_ id: UUID) -> UUID {
            var current = id
            while let parent = group[current], parent != current { current = parent }
            return current
        }
        var firstByKey: [String: UUID] = [:]
        for provider in providers {
            let keys = ["name:" + SearchText.normalize(provider.name)] + (ProviderTaxID.normalized(provider.taxID).map { ["cui:" + $0] } ?? [])
            for key in keys {
                if let other = firstByKey[key] {
                    let (a, b) = (root(other), root(provider.id))
                    if a != b { group[b] = a }
                } else {
                    firstByKey[key] = provider.id
                }
            }
        }
        let groups = Dictionary(grouping: providers) { root($0.id) }
        return groups.values.filter { $0.count > 1 }.compactMap { group in
            let ordered = group.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            guard let kept = ordered.first else { return nil }
            return DuplicateProviders(keptID: kept.id, duplicateIDs: ordered.dropFirst().map(\.id))
        }.sorted { $0.keptID.uuidString < $1.keptID.uuidString }
    }

    /// Merges each approved group into the firm kept first, in one save: its sections,
    /// jobs, parts and documents move over, its trades join, details it lacks are filled
    /// in, and the copies go. A group already merged changes nothing.
    public func mergeDuplicateProviders(_ approved: [DuplicateProviders]) throws {
        try UnitOfWork.perform(in: context) {
            let providers = Dictionary(try context.fetch(FetchDescriptor<Provider>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for group in approved {
                guard let kept = providers[group.keptID] else { continue }
                for id in group.duplicateIDs {
                    guard let copy = providers[id], copy.id != kept.id, !copy.isDeleted else { continue }
                    for asset in copy.assets ?? [] where !(kept.assets ?? []).contains(where: { $0.id == asset.id }) {
                        kept.assets = (kept.assets ?? []) + [asset]
                    }
                    for entry in copy.historyEntries ?? [] {
                        var people = (entry.providers ?? []).filter { $0.id != copy.id }
                        if !people.contains(where: { $0.id == kept.id }) { people.append(kept) }
                        entry.providers = people
                    }
                    for item in copy.suppliedItems ?? [] { item.supplier = kept }
                    for attachment in copy.attachments ?? [] { attachment.provider = kept }
                    kept.trades = Array(Set(kept.trades + copy.trades)).sorted()
                    kept.phone = kept.phone ?? copy.phone
                    kept.email = kept.email ?? copy.email
                    kept.address = kept.address ?? copy.address
                    kept.notes = kept.notes ?? copy.notes
                    kept.manualRating = kept.manualRating ?? copy.manualRating
                    kept.wouldCallAgain = kept.wouldCallAgain ?? copy.wouldCallAgain
                    kept.contactIdentifier = kept.contactIdentifier ?? copy.contactIdentifier
                    kept.taxID = kept.taxID ?? copy.taxID
                    kept.updatedAt = Date()
                    context.delete(copy)
                }
            }
            try UnitOfWork.save(context)
        }
    }
}
