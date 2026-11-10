import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Bills filed before version 7: the number kept in the note moves to its place by itself,
/// and the same bill logged twice is joined only with the owner's OK, idempotently.
/// Placeholder data only.
@MainActor
@Suite("Repair: bills filed before")
struct BillRepairTests {

    private func repairs(_ context: ModelContext) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest,
                    ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "bill-repairs-\(UUID().uuidString)")!))
    }

    private func subscription(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.subscription))
        var values = FieldValues()
        values[SubscriptionFields.provider] = .text("ENGIE Romania S.A.")
        values[SubscriptionFields.service] = .text(ServiceKind.gas)
        return try AssetActions(context: context).create(name: "Gaz – ENGIE Romania S.A.", template: template, values: values)
    }

    /// A bill as an earlier version logged it: its number only in the note it wrote.
    @discardableResult
    private func oldBill(on gas: Asset, note: String?, day: String, total: Decimal, paper: (seed: UInt8, filed: String)? = nil,
                         in context: ModelContext) throws -> HistoryEntry {
        let entry = HistoryEntry(kind: .payment, title: "Factură ENGIE Romania S.A.", occurredAt: noon(day))
        entry.totalCost = Money(total)
        entry.note = note
        context.insert(entry)
        entry.asset = gas
        if let paper {
            let document = Attachment(fileName: "Factură.heic", contentType: "public.heic", data: Data([paper.seed]), kind: .invoice)
            document.createdAt = noon(paper.filed)
            context.insert(document)
            document.historyEntry = entry
            document.asset = gas
        }
        try UnitOfWork.save(context)
        return entry
    }

    private func bills(on gas: Asset) -> [HistoryEntry] {
        PaperIdentity.bills(of: gas)
    }

    // MARK: The number in the note

    @Test func theNumberMovesFromTheNoteToItsPlaceByItself() throws {
        let context = try makeContext()
        let gas = try subscription(context)
        let bill = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, in: context)
        let mine = try oldBill(on: gas, note: "Plătită la ghișeu", day: "2026-09-05", total: 199, in: context)

        let found = try repairs(context).detect()
        #expect(!found.contains { $0.step == .billNumbers }, "It changes only where the number is kept: nothing to ask")
        #expect(bill.reference == "EXM 0000001")
        #expect(bill.note == nil, "The note the app wrote goes; the page says the number as before")
        #expect(mine.reference == nil && mine.note == "Plătită la ghișeu", "A note of the person's stays as it is")

        #expect(try BillNumbersStep().migrate(in: context) == 0, "A second run changes nothing")
    }

    @Test(arguments: [
        ("Factura nr. EXM 0000001", "EXM 0000001"), ("Factura nr.   EXM-1  ", "EXM-1"),
        ("Factura nr. ", nil), ("Factura EXM 0000001", nil), ("Plătită", nil),
    ] as [(String, String?)])
    func theNoteTheAppWrote(note: String, number: String?) {
        #expect(BillNumbersStep.number(inNote: note) == number, "\(note)")
    }

    // MARK: The same bill twice

    @Test func theSameBillLoggedTwiceIsJoinedOnlyWithTheOwnersOK() throws {
        let context = try makeContext()
        let gas = try subscription(context)
        let first = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (1, "2026-10-06"), in: context)
        let second = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (2, "2026-10-20"), in: context)
        try oldBill(on: gas, note: "Factura nr. EXM 0000002", day: "2026-11-05", total: 245, in: context)
        let older = try #require(first.attachments?.first)
        let newer = try #require(second.attachments?.first)
        let list = repairs(context)

        let found = try list.detect().filter { $0.step == .sameBillTwice }
        #expect(found.count == 1, "Another number is another bill")
        let finding = try #require(found.first)
        #expect(finding.message == "„Gaz – ENGIE Romania S.A.” are factura din 5 octombrie 2026 de mai multe ori în Istoric. O las o singură dată?")
        #expect(finding.subject == .sameBill(keep: second.id, merge: [first.id]), "The one whose paper came last stays")
        #expect(bills(on: gas).count == 3, "Nothing changes before the OK")

        try list.apply(found)
        #expect(bills(on: gas).count == 2)
        #expect(bills(on: gas).map(\.id).contains(second.id))
        #expect(newer.historyEntry?.id == second.id && !newer.isArchived, "The newest paper is the bill's copy")
        #expect(older.historyEntry?.id == second.id, "The first paper stays with the bill")
        #expect(older.isArchived && older.supersededBy?.id == newer.id, "Archived beside it, never lost")
        #expect(try list.detect().filter { $0.step == .sameBillTwice }.isEmpty, "Found nothing once applied")
    }

    @Test func withoutNumbersTheDayAndTotalDecide() throws {
        let context = try makeContext()
        let gas = try subscription(context)
        try oldBill(on: gas, note: nil, day: "2026-10-05", total: 245, in: context)
        try oldBill(on: gas, note: nil, day: "2026-10-05", total: 245, in: context)
        try oldBill(on: gas, note: nil, day: "2026-10-05", total: 99, in: context)
        try oldBill(on: gas, note: nil, day: "2026-11-05", total: 245, in: context)
        let found = try repairs(context).detect().filter { $0.step == .sameBillTwice }
        #expect(found.count == 1)
        guard case .sameBill(_, let merge)? = found.first?.subject else { Issue.record("A bill logged twice"); return }
        #expect(merge.count == 1)
    }

    @Test func aBillNoLongerLoggedTwiceChangesNothing() throws {
        let context = try makeContext()
        let gas = try subscription(context)
        try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, in: context)
        let extra = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, in: context)
        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .sameBillTwice }
        #expect(found.count == 1)
        try HistoryActions(context: context).delete(extra)
        try list.apply(found)
        #expect(bills(on: gas).count == 1, "The finding no longer holds, so it changes nothing")
    }

    // MARK: What the extra photo made

    @discardableResult
    private func index(_ value: Double, on gas: Asset, day: String, paper: DosarCuSina.Attachment?, in context: ModelContext) throws -> MeasurementLog {
        let log = MeasurementLog(kind: .gas, name: "", value: value, unit: .cubicMetres, recordedAt: noon(day))
        context.insert(log)
        log.asset = gas
        paper?.measurement = log
        try UnitOfWork.save(context)
        return log
    }

    private func reminder(on gas: Asset, made: String, paid: Bool, papers: [DosarCuSina.Attachment], in context: ModelContext) throws -> Obligation {
        let bill = Obligation(title: "Factura de plătit", kind: .payment, dueDay: CalendarDay("2026-11-20"), calendar: .bucharest)
        bill.blueprintKey = SubscriptionFields.billBlueprint
        bill.createdAt = noon(made)
        if paid { bill.status = .done }
        context.insert(bill)
        bill.asset = gas
        for paper in papers { paper.obligation = bill }
        try UnitOfWork.save(context)
        return bill
    }

    private func readings(of gas: Asset) -> [Double] {
        (gas.measurements ?? []).filter { !$0.isDeleted }.sorted { ($0.recordedAt, $0.value) < ($1.recordedAt, $1.value) }.map(\.value)
    }

    private func billReminders(on gas: Asset) -> [Obligation] {
        (gas.obligations ?? []).filter { !$0.isDeleted && $0.blueprintKey == SubscriptionFields.billBlueprint }
    }

    /// Two photos of one bill, logged twice, each with the index and the reminder it made.
    private func billTwice(_ context: ModelContext, first: Double, second: Double) throws
        -> (gas: Asset, kept: HistoryEntry, papers: [DosarCuSina.Attachment]) {
        let gas = try subscription(context)
        let one = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (1, "2026-10-06"), in: context)
        let two = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (2, "2026-10-20"), in: context)
        let papers = [try #require(one.attachments?.first), try #require(two.attachments?.first)]
        try index(first, on: gas, day: "2026-10-05", paper: papers[0], in: context)
        try index(second, on: gas, day: "2026-10-05", paper: papers[1], in: context)
        return (gas, two, papers)
    }

    @Test func theJoinKeepsOneIndexTheFirstFiled() throws {
        let context = try makeContext()
        let (gas, kept, papers) = try billTwice(context, first: 12_345, second: 12_354)
        let list = repairs(context)
        try list.apply(try list.detect().filter { $0.step == .sameBillTwice })

        #expect(bills(on: gas).map(\.id) == [kept.id])
        #expect(readings(of: gas) == [12_345], "One index: the one filed first, as filing the bill once records")
        let log = try #require(gas.measurements?.first { !$0.isDeleted })
        #expect(papers.allSatisfy { $0.measurement?.id == log.id }, "Both copies point at it")
        #expect(try list.detect().filter { $0.step == .sameBillTwice }.isEmpty, "Idempotent")
    }

    @Test func theJoinKeepsTheIndexThatCounts() throws {
        let context = try makeContext()
        // A September index of 12.350: the first photo's 12.345 was set aside (the person kept the old one).
        let gas = try subscription(context)
        try index(12_350, on: gas, day: "2026-09-05", paper: nil, in: context)
        let one = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (1, "2026-10-06"), in: context)
        let two = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (2, "2026-10-20"), in: context)
        try index(12_345, on: gas, day: "2026-10-05", paper: try #require(one.attachments?.first), in: context)
        try index(12_400, on: gas, day: "2026-10-05", paper: try #require(two.attachments?.first), in: context)
        let list = repairs(context)
        try list.apply(try list.detect().filter { $0.step == .sameBillTwice })
        #expect(readings(of: gas) == [12_350, 12_400], "The index that counts stays; the one set aside goes")
    }

    @Test func theJoinKeepsOneReminderPaidStaysPaid() throws {
        let context = try makeContext()
        let (gas, _, papers) = try billTwice(context, first: 12_345, second: 12_345)
        let paid = try reminder(on: gas, made: "2026-10-06", paid: true, papers: [papers[0]], in: context)
        // The extra photo, after paying, asked to pay it again.
        _ = try reminder(on: gas, made: "2026-10-20", paid: false, papers: [papers[1]], in: context)
        let list = repairs(context)
        try list.apply(try list.detect().filter { $0.step == .sameBillTwice })

        #expect(billReminders(on: gas).map(\.id) == [paid.id], "One „Factura de plătit”")
        #expect(paid.status == .done, "Still paid")
        #expect(papers.allSatisfy { $0.obligation?.id == paid.id })
        #expect(gas.activeObligations.allSatisfy { $0.blueprintKey != SubscriptionFields.billBlueprint }, "Nothing left asking to pay it")
    }

    @Test func aReminderAnotherBillSharesStays() throws {
        let context = try makeContext()
        let (gas, _, papers) = try billTwice(context, first: 12_345, second: 12_345)
        let next = try oldBill(on: gas, note: "Factura nr. EXM 0000002", day: "2026-11-05", total: 199, paper: (3, "2026-11-06"), in: context)
        let mine = try reminder(on: gas, made: "2026-10-06", paid: false, papers: [papers[0]], in: context)
        // The next bill moved the extra photo's reminder on, so it is that bill's reminder now.
        let shared = try reminder(on: gas, made: "2026-10-20", paid: false, papers: [papers[1], try #require(next.attachments?.first)], in: context)
        let list = repairs(context)
        try list.apply(try list.detect().filter { $0.step == .sameBillTwice })
        #expect(Set(billReminders(on: gas).map(\.id)) == [shared.id], "The one the next bill uses stays, the extra one goes")
        #expect(mine.isDeleted || !billReminders(on: gas).contains { $0.id == mine.id })
        #expect(papers.allSatisfy { $0.obligation?.id == shared.id })
    }

    @Test func aBillJoinedBeforeIsOfferedAgainForItsExtraIndex() throws {
        let context = try makeContext()
        let gas = try subscription(context)
        // Joined by an earlier version: one entry, two copies, but each copy's index kept.
        let entry = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (1, "2026-10-06"), in: context)
        let older = try #require(entry.attachments?.first)
        let newer = DosarCuSina.Attachment(fileName: "Factură.pdf", contentType: "com.adobe.pdf", data: Data([2]), kind: .invoice)
        newer.createdAt = noon("2026-10-20")
        context.insert(newer)
        newer.historyEntry = entry
        newer.asset = gas
        older.supersededBy = newer
        older.isArchived = true
        try UnitOfWork.save(context)
        try index(12_345, on: gas, day: "2026-10-05", paper: older, in: context)
        try index(12_354, on: gas, day: "2026-10-05", paper: newer, in: context)

        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .sameBillTwice }
        let finding = try #require(found.first)
        #expect(found.count == 1)
        #expect(finding.subject == .sameBill(keep: entry.id, merge: []))
        #expect(finding.message == "Factura din 5 octombrie 2026 de la „Gaz – ENGIE Romania S.A.” are indexul sau termenul de plată de mai multe ori. Le las o singură dată?")
        #expect(readings(of: gas).count == 2, "Nothing changes before the OK")

        try list.apply(found)
        #expect(readings(of: gas) == [12_345])
        #expect(bills(on: gas).map(\.id) == [entry.id])
        #expect(!newer.isArchived && older.supersededBy?.id == newer.id, "The copies stay as they were")
        #expect(try list.detect().filter { $0.step == .sameBillTwice }.isEmpty)
    }

    @Test func aBillLoggedOnceWithOneIndexIsNotOffered() throws {
        let context = try makeContext()
        let gas = try subscription(context)
        let entry = try oldBill(on: gas, note: "Factura nr. EXM 0000001", day: "2026-10-05", total: 245, paper: (1, "2026-10-06"), in: context)
        try index(12_345, on: gas, day: "2026-10-05", paper: try #require(entry.attachments?.first), in: context)
        _ = try reminder(on: gas, made: "2026-10-06", paid: false, papers: [try #require(entry.attachments?.first)], in: context)
        #expect(try repairs(context).detect().filter { $0.step == .sameBillTwice }.isEmpty)
    }

    @Test func theNumberMovesBeforeTheJoinWithTheirOwnStoredIDs() throws {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        let numbers = try #require(ids.firstIndex(of: .billNumbers))
        let join = try #require(ids.firstIndex(of: .sameBillTwice))
        #expect(join == numbers + 1, "The number moves first, so the join can read it")
        #expect(ids.firstIndex(of: .policyNumberParts).map { $0 < numbers } == true, "Added after the steps before them")
        #expect(DataRepairStepID.billNumbers.rawValue == "bill-numbers")
        #expect(DataRepairStepID.sameBillTwice.rawValue == "same-bill-twice")
    }
}
