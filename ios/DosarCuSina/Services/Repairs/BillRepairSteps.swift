import Foundation
import SwiftData

// MARK: - A bill's number kept in its note (runs by itself)

/// Before version 7, a bill filed from capture kept its invoice number only in its entry's
/// note, written by the app as "Factura nr. EXM 0000001". The number moves to its own place
/// (`HistoryEntry.reference`), where a bill is known by it (`BillIdentity`), and the note the
/// app wrote goes. The bill's page says the same as before ("Factura nr. EXM 0000001"), so it
/// runs without asking. A note the person changed is left alone.
struct BillNumbersStep: DataRepairStep {
    static let id = DataRepairStepID.billNumbers
    var title: String { String(localized: "Numerele facturilor", comment: "Repair group: invoice numbers kept in a bill's note by older builds.") }
    var runsByItself: Bool { true }

    /// What earlier versions wrote before the number, in the source language they wrote it in.
    static let notePrefix = "Factura nr. "

    /// The number an earlier version wrote in a bill's note; nil for any other note.
    static func number(inNote note: String?) -> String? {
        guard let note, note.hasPrefix(notePrefix) else { return nil }
        let number = note.dropFirst(notePrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty || number.contains(where: \.isNewline) ? nil : number
    }

    /// How many bills changed.
    @discardableResult
    func migrate(in context: ModelContext) throws -> Int {
        let payment = HistoryKind.payment.rawValue
        var changed = 0
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.kindRaw == payment }))
        where !entry.isCompletion && (entry.reference ?? "").isEmpty {
            guard let number = Self.number(inNote: entry.note) else { continue }
            entry.reference = number
            entry.note = nil
            changed += 1
        }
        return changed
    }

    func runByItself(in context: ModelContext) throws {
        try migrate(in: context)
    }
}

// MARK: - The same bill logged twice

/// Before another photo of a bill was known as the same bill, filing it again logged it a
/// second time in its subscription's history. Bills of one subscription that the one rule
/// (`BillIdentity`) says are the same are offered to be joined: one entry stays (the one
/// whose paper came last, with what was read then), the others' papers move to it, the
/// newest as the current copy and the rest archived beside it, and the extra entries go. It
/// asks, because it changes what Istoric and the bill trend show. A reading or a reminder an
/// extra photo made stays as it is.
struct SameBillTwiceStep: DataRepairStep {
    static let id = DataRepairStepID.sameBillTwice
    var title: String { String(localized: "Facturi trecute de mai multe ori", comment: "Repair group: the same bill logged twice in Istoric.") }

    /// One bill logged more than once: the entry that stays and the ones joined into it.
    struct Group: Hashable, Sendable {
        var keep: UUID
        var merge: [UUID]
    }

    /// The bills logged more than once, per subscription.
    static func groups(in context: ModelContext, calendar: Calendar) throws -> [Group] {
        let templates = try TemplateStore(context: context).templatesByKey()
        var groups: [Group] = []
        for subscription in try context.fetch(FetchDescriptor<Asset>()) where templates.plays(.subscription, subscription.templateKey) {
            let bills = BillIdentity.bills(of: subscription).sorted { ($0.occurredAt, $0.id.uuidString) < ($1.occurredAt, $1.id.uuidString) }
            var placed = Set<UUID>()
            for (index, bill) in bills.enumerated() where !placed.contains(bill.id) {
                let identity = BillIdentity(entry: bill, calendar: calendar)
                let same = [bill] + bills.dropFirst(index + 1).filter { other in
                    !placed.contains(other.id) && identity.match(BillIdentity(entry: other, calendar: calendar)) != nil
                }
                guard same.count > 1 else { continue }
                placed.formUnion(same.map(\.id))
                let keep = same.max { lastPaper(of: $0) < lastPaper(of: $1) } ?? bill
                groups.append(Group(keep: keep.id, merge: same.map(\.id).filter { $0 != keep.id }.sorted { $0.uuidString < $1.uuidString }))
            }
        }
        return groups
    }

    /// When the entry's newest paper was filed; an entry without one counts as oldest.
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
                message: String(localized: "„\(name)” are factura din \(date) de mai multe ori în Istoric. O las o singură dată?",
                                comment: "Repair: the same bill logged more than once in a subscription's history."),
                subject: .sameBill(keep: group.keep, merge: group.merge)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = findings.compactMap { if case .sameBill(let keep, let merge) = $0.subject { Group(keep: keep, merge: merge) } else { nil } }
        guard !approved.isEmpty else { return }
        // Only what still holds: the same groups found again now.
        let current = Set(try Self.groups(in: context, calendar: calendar))
        let entries = Dictionary(try context.fetch(FetchDescriptor<HistoryEntry>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let documents = AttachmentActions(context: context, calendar: calendar)
        for group in approved where current.contains(group) {
            guard let kept = entries[group.keep] else { continue }
            let extra = group.merge.compactMap { entries[$0] }
            let papers = ([kept] + extra).flatMap { ($0.attachments ?? []).filter { !$0.isDeleted } }
            for paper in papers { paper.historyEntry = kept }
            for entry in extra where (kept.reference ?? "").isEmpty {
                if let number = entry.reference, !number.isEmpty { kept.reference = number }
            }
            // The newest paper is the bill's current copy; the others stay, archived beside it.
            if let newest = papers.filter({ !$0.isArchived }).max(by: { $0.createdAt < $1.createdAt }) {
                for older in papers where older.id != newest.id && !older.isArchived { try documents.supersede(older, with: newest) }
            }
            for entry in extra { context.delete(entry) }
        }
    }
}
