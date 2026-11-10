import Foundation
import SwiftData

// MARK: - A bill's number kept in its note (runs by itself)

/// Before version 7, a bill filed from capture kept its invoice number only in its entry's
/// note, written by the app as "Factura nr. EXM 0000001". The number moves to its own place
/// (`HistoryEntry.reference`), where a bill is known by it (`PaperIdentity`), and the note the
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
/// (`PaperIdentity`) says are the same are offered to be joined, leaving what filing the bill
/// once leaves (`Join`): one entry (the one whose paper came last, with what was read then)
/// with every paper, the newest as the current copy and the rest archived beside it; one
/// meter index; one "Factura de plătit". A bill joined before the join took the extra index
/// and reminder away too is offered again for them. It asks, because it changes what Istoric,
/// the bill trend and the subscription's index show.
struct SameBillTwiceStep: DataRepairStep {
    static let id = DataRepairStepID.sameBillTwice
    var title: String { String(localized: "Facturi trecute de mai multe ori", comment: "Repair group: the same bill logged twice in Istoric.") }

    /// One bill logged more than once: the entry that stays and the ones joined into it
    /// (none, when only its index or its reminder is there more than once).
    struct Group: Hashable, Sendable {
        var keep: UUID
        var merge: [UUID]
    }

    /// What one bill's papers made, and what of it stays once they are joined.
    @MainActor
    struct Join {
        /// The meter readings the papers recorded on the subscription, the first filed first.
        var readings: [MeasurementLog]
        /// The reading that stays: the first filed that counts in the subscription's series
        /// (the person's answer to a lower index decided which one counts), else the first filed.
        var reading: MeasurementLog?
        /// The bill's "Factura de plătit" deadlines the papers are filed with.
        var deadlines: [Obligation]
        /// The one that stays: a paid one (paid stays paid), else one another bill's papers are
        /// filed with too, else the first made.
        var deadline: Obligation?
        /// The ones that go: the others still running that no other bill's papers are filed
        /// with. A paid one stays, as the record of a payment the person made.
        var extraDeadlines: [Obligation]

        /// Whether the papers made more than filing the bill once would.
        var hasLeftovers: Bool { readings.count > 1 || !extraDeadlines.isEmpty }

        init(papers: [Attachment], on subscription: Asset) {
            let byFiling = papers.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            var readings: [MeasurementLog] = []
            var deadlines: [Obligation] = []
            for paper in byFiling {
                if let log = paper.measurement, !log.isDeleted, log.asset?.id == subscription.id, !readings.contains(where: { $0.id == log.id }) {
                    readings.append(log)
                }
                if let bill = paper.obligation, !bill.isDeleted, bill.asset?.id == subscription.id,
                   bill.blueprintKey == SubscriptionFields.billBlueprint, !deadlines.contains(where: { $0.id == bill.id }) {
                    deadlines.append(bill)
                }
            }
            self.readings = readings
            self.reading = readings.first { log in
                HouseholdMutations.readingSeries(of: subscription, unit: log.measurementUnit).readings
                    .contains { $0.isSameReading(as: .init(date: log.recordedAt, metric: log.value)) }
            } ?? readings.first
            self.deadlines = deadlines
            let mine = Set(papers.map(\.id))
            func isShared(_ bill: Obligation) -> Bool {
                (bill.attachments ?? []).contains { !$0.isDeleted && !mine.contains($0.id) }
            }
            let byMaking = deadlines.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            let kept = byMaking.first { $0.status == .done } ?? byMaking.first(where: isShared) ?? byMaking.first
            self.deadline = kept
            self.extraDeadlines = byMaking.filter { $0.id != kept?.id && $0.status != .done && !isShared($0) }
        }
    }

    /// The bills logged more than once, or whose papers made more than one index or reminder,
    /// per subscription.
    static func groups(in context: ModelContext, calendar: Calendar) throws -> [Group] {
        let templates = try TemplateStore(context: context).templatesByKey()
        var groups: [Group] = []
        for subscription in try context.fetch(FetchDescriptor<Asset>()) where templates.plays(.subscription, subscription.templateKey) {
            let bills = PaperIdentity.bills(of: subscription).sorted { ($0.occurredAt, $0.id.uuidString) < ($1.occurredAt, $1.id.uuidString) }
            var placed = Set<UUID>()
            for (index, bill) in bills.enumerated() where !placed.contains(bill.id) {
                let identity = PaperIdentity(entry: bill, calendar: calendar)
                let same = [bill] + bills.dropFirst(index + 1).filter { other in
                    !placed.contains(other.id) && identity.match(PaperIdentity(entry: other, calendar: calendar)) != nil
                }
                placed.formUnion(same.map(\.id))
                guard same.count > 1 || Join(papers: papers(of: same), on: subscription).hasLeftovers else { continue }
                let keep = same.max { lastPaper(of: $0) < lastPaper(of: $1) } ?? bill
                groups.append(Group(keep: keep.id, merge: same.map(\.id).filter { $0 != keep.id }.sorted { $0.uuidString < $1.uuidString }))
            }
        }
        return groups
    }

    /// Every paper filed with `entries`.
    private static func papers(of entries: [HistoryEntry]) -> [Attachment] {
        entries.flatMap { ($0.attachments ?? []).filter { !$0.isDeleted } }
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
            let message = group.merge.isEmpty
                ? String(localized: "Factura din \(date) de la „\(name)” are indexul sau termenul de plată de mai multe ori. Le las o singură dată?",
                         comment: "Repair: a bill whose extra photo left a second meter index or a second bill reminder.")
                : String(localized: "„\(name)” are factura din \(date) de mai multe ori în Istoric. O las o singură dată?",
                         comment: "Repair: the same bill logged more than once in a subscription's history.")
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(group.keep.uuidString):\(group.merge.map(\.uuidString).joined(separator: ","))",
                step: Self.id,
                message: message,
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
            guard let kept = entries[group.keep], let subscription = kept.asset else { continue }
            let extra = group.merge.compactMap { entries[$0] }
            let papers = Self.papers(of: [kept] + extra)
            // What the papers made, read before anything moves.
            let join = Join(papers: papers, on: subscription)
            for paper in papers { paper.historyEntry = kept }
            for entry in extra where (kept.reference ?? "").isEmpty {
                if let number = entry.reference, !number.isEmpty { kept.reference = number }
            }
            // The newest paper is the bill's current copy; the others stay, archived beside it.
            if let newest = papers.filter({ !$0.isArchived }).max(by: { $0.createdAt < $1.createdAt }) {
                for older in papers where older.id != newest.id && !older.isArchived { try documents.supersede(older, with: newest) }
            }
            // One index: the papers share the one that stays, and the others go.
            if let reading = join.reading {
                let recorded = Set(join.readings.map(\.id))
                for paper in papers where paper.measurement.map({ recorded.contains($0.id) }) == true { paper.measurement = reading }
                for log in join.readings where log.id != reading.id { HouseholdMutations.removeReading(log, from: subscription, in: context) }
                HouseholdMutations.syncHeroMetric(of: subscription, in: context)
            }
            // One "Factura de plătit": the papers are filed with the one that stays, and the
            // extra ones still running go.
            if let deadline = join.deadline {
                let joined = Set(join.deadlines.map(\.id))
                for paper in papers where paper.obligation.map({ joined.contains($0.id) }) == true { paper.obligation = deadline }
                for bill in join.extraDeadlines { context.delete(bill) }
            }
            for entry in extra { context.delete(entry) }
        }
    }
}
