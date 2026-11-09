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
        BillIdentity.bills(of: gas)
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
