import Foundation
import SwiftData

// MARK: - The same visit logged twice

/// Before another photo of a visit's invoice was known as the same invoice, filing it again
/// through the visit form logged a second visit (or repair, or purchase) on the section.
/// Visits of one section whose papers the one rule (`PaperIdentity`) says are the same
/// invoice for sure (the same number from the same firm on the same day, or no number to
/// compare and the same day, total and firm) are offered to be joined, leaving what filing
/// the invoice once leaves: one visit (the one whose paper came last) with every paper, the
/// newest as the current copy and the rest archived beside it; its parts and jobs once; one
/// reading. Only visits that each have a paper are compared: a visit typed by hand was never
/// doubled by a photo. It asks, because it changes what Istoric and the section's counter show.
struct SameVisitTwiceStep: DataRepairStep {
    static let id = DataRepairStepID.sameVisitTwice
    var title: String { String(localized: "Vizite trecute de mai multe ori", comment: "Repair group: the same visit's invoice logged twice in Istoric.") }

    /// One visit logged more than once: the entry that stays and the ones joined into it.
    struct Group: Hashable, Sendable {
        var keep: UUID
        var merge: [UUID]
    }

    /// The visits logged more than once, per section.
    static func groups(in context: ModelContext, calendar: Calendar) throws -> [Group] {
        var groups: [Group] = []
        for section in try context.fetch(FetchDescriptor<Asset>()) where !section.isExample {
            let visits = PaperIdentity.visits(of: section)
                .filter { !$0.isExample && !papers(of: [$0]).isEmpty }
                .sorted { ($0.occurredAt, $0.id.uuidString) < ($1.occurredAt, $1.id.uuidString) }
            var placed = Set<UUID>()
            for (index, visit) in visits.enumerated() where !placed.contains(visit.id) {
                let identity = PaperIdentity(entry: visit, calendar: calendar)
                let same = [visit] + visits.dropFirst(index + 1).filter { other in
                    guard !placed.contains(other.id) else { return false }
                    // Only what is the same invoice for sure; the number alone may be another one.
                    let match = identity.match(PaperIdentity(entry: other, calendar: calendar))
                    return match == .number || match == .dayAndTotal
                }
                guard same.count > 1 else { continue }
                placed.formUnion(same.map(\.id))
                let keep = same.max { lastPaper(of: $0) < lastPaper(of: $1) } ?? visit
                groups.append(Group(keep: keep.id, merge: same.map(\.id).filter { $0 != keep.id }.sorted { $0.uuidString < $1.uuidString }))
            }
        }
        return groups
    }

    /// Every paper filed with `entries`.
    private static func papers(of entries: [HistoryEntry]) -> [Attachment] {
        entries.flatMap { ($0.attachments ?? []).filter { !$0.isDeleted } }
    }

    /// When the entry's newest paper was filed.
    private static func lastPaper(of entry: HistoryEntry) -> Date {
        (entry.attachments ?? []).filter { !$0.isDeleted }.map(\.createdAt).max() ?? .distantPast
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let entries = Dictionary(try scan.context.fetch(FetchDescriptor<HistoryEntry>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try Self.groups(in: scan.context, calendar: scan.calendar).compactMap { group in
            guard let kept = entries[group.keep] else { return nil }
            let name = kept.asset?.name ?? ""
            let date = DosarFormat.longDay(CalendarDay(kept.occurredAt, calendar: scan.calendar))
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(group.keep.uuidString):\(group.merge.map(\.uuidString).joined(separator: ","))",
                step: Self.id,
                message: String(localized: "Factura din \(date) e trecută de mai multe ori în istoricul „\(name)”. O las o singură dată?",
                                comment: "Repair: the same visit's invoice logged more than once in a section's history."),
                subject: .sameVisit(keep: group.keep, merge: group.merge)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = findings.compactMap { if case .sameVisit(let keep, let merge) = $0.subject { Group(keep: keep, merge: merge) } else { nil } }
        guard !approved.isEmpty else { return }
        // Only what still holds: the same groups found again now.
        let current = Set(try Self.groups(in: context, calendar: calendar))
        let entries = Dictionary(try context.fetch(FetchDescriptor<HistoryEntry>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let documents = AttachmentActions(context: context, calendar: calendar)
        for group in approved where current.contains(group) {
            guard let kept = entries[group.keep], let section = kept.asset else { continue }
            let extra = group.merge.compactMap { entries[$0] }
            Self.join(extra, into: kept, on: section, in: context)
            // Every paper stays with the visit; the newest is its current copy, the others are
            // archived beside it.
            let papers = Self.papers(of: [kept] + extra)
            for paper in papers { paper.historyEntry = kept }
            if let newest = papers.filter({ !$0.isArchived }).max(by: { $0.createdAt < $1.createdAt }) {
                for older in papers where older.id != newest.id && !older.isArchived { try documents.supersede(older, with: newest) }
            }
            for entry in extra { context.delete(entry) }
        }
    }

    /// What the extra visits recorded that the one that stays doesn't: their number, total,
    /// firm, rating, note and deadline where it has none, their parts and jobs it doesn't list,
    /// and one reading.
    @MainActor
    private static func join(_ extra: [HistoryEntry], into kept: HistoryEntry, on section: Asset, in context: ModelContext) {
        for entry in extra {
            if (kept.reference ?? "").isEmpty, let number = entry.reference, !number.isEmpty { kept.reference = number }
            if kept.totalCost == nil { kept.totalCost = entry.totalCost }
            if (kept.providers ?? []).isEmpty, let firms = entry.providers, !firms.isEmpty { kept.providers = firms }
            if kept.rating == nil { kept.rating = entry.rating }
            if (kept.note ?? "").isEmpty, let note = entry.note, !note.isEmpty { kept.note = note }
            if kept.obligation == nil { kept.obligation = entry.obligation }
            // Parts and jobs, once: one the visit already lists stays as it is.
            for item in entry.items ?? [] where !item.isDeleted {
                let listed = (kept.items ?? []).contains { !$0.isDeleted && itemKey($0) == itemKey(item) }
                if !listed { item.entry = kept }
            }
        }
        joinReadings(extra, into: kept, on: section, in: context)
    }

    /// The same part or job: its component, else its name as compared.
    private static func itemKey(_ item: ServiceItem) -> String {
        item.componentKey.map { "component:\($0)" } ?? "name:\(PaperIdentity.comparable(item.name) ?? "")"
    }

    /// One reading for the visit: its own, else the first extra visit's, moved to its moment.
    /// The readings the extra visits logged go.
    @MainActor
    private static func joinReadings(_ extra: [HistoryEntry], into kept: HistoryEntry, on section: Asset, in context: ModelContext) {
        let visits = [kept] + extra
        let logs = (section.measurements ?? []).filter { log in
            !log.isDeleted && visits.contains { HouseholdMutations.isReading(log, recordedBy: $0) }
        }
        if kept.metricReading == nil, let donor = extra.first(where: { $0.metricReading != nil }) {
            kept.metricReading = donor.metricReading
            logs.first { HouseholdMutations.isReading($0, recordedBy: donor) }?.recordedAt = kept.occurredAt
        }
        let stays = logs.first { HouseholdMutations.isReading($0, recordedBy: kept) }
        for log in logs where log.id != stays?.id { context.delete(log) }
        HouseholdMutations.syncHeroMetric(of: section, in: context)
    }
}
