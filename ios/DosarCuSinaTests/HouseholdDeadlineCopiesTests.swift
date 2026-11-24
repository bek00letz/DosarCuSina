import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Two phones with a tenancy each make their own rental income declaration; "Adaugă" brings
/// both copies together. The household keeps one, the same one whatever order they are read
/// in: the copy with the person's history on it, with everything the other recorded, never a
/// fresh copy the app just made.
@MainActor
@Suite("Copies of a household deadline")
struct HouseholdDeadlineCopiesTests {
    let calendar = Calendar.bucharest
    let then = noon("2026-06-01")
    static let smaller = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let larger = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    private func declaration(id: UUID, due: CalendarDay = CalendarDay("2027-05-25"), in context: ModelContext) -> Obligation {
        let blueprint = HouseholdRules.rentalDeclaration
        let obligation = Obligation(id: id, title: blueprint.title, kind: blueprint.kind, dueDay: due,
                                    recurrence: blueprint.recurrence, reminders: blueprint.reminders)
        obligation.blueprintKey = blueprint.key
        obligation.notes = blueprint.deadlineNote
        context.insert(obligation)
        return obligation
    }

    private func declarations(in context: ModelContext) throws -> [Obligation] {
        let key = HouseholdRules.rentalDeclarationKey
        return try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
    }

    /// A tenancy, and two copies of its declaration: one still due, one filed this year (due
    /// next year, with its completion and the document filed with it). Saved straight to the
    /// store, as an import leaves them, with an old change time each.
    private func merged(filedHasSmallerID: Bool, filedFirst: Bool) throws -> (ModelContext, filed: Obligation, due: Obligation, document: DosarCuSina.Attachment) {
        let context = try makeContext()
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        let ids = filedHasSmallerID ? (Self.smaller, Self.larger) : (Self.larger, Self.smaller)
        let filed: Obligation
        let due: Obligation
        if filedFirst {
            filed = declaration(id: ids.0, in: context)
            due = declaration(id: ids.1, in: context)
        } else {
            due = declaration(id: ids.1, in: context)
            filed = declaration(id: ids.0, in: context)
        }
        try context.save()
        try ObligationActions(context: context, calendar: calendar, now: { noon("2027-05-10") }).complete(filed)
        let document = DosarCuSina.Attachment(fileName: "declaratia-unica.pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8))
        context.insert(document)
        document.obligation = filed
        for record in [filed, due] { record.updatedAt = then }
        try context.save()
        return (context, filed, due, document)
    }

    @Test("The copy already filed stays, with its completion and its document, in any order",
          arguments: [true, false], [true, false])
    func theFiledCopyStays(filedHasSmallerID: Bool, filedFirst: Bool) throws {
        let (context, filed, _, document) = try merged(filedHasSmallerID: filedHasSmallerID, filedFirst: filedFirst)
        let filedID = filed.id

        #expect(try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2027-05-12")))

        let left = try declarations(in: context)
        #expect(left.count == 1)
        let kept = try #require(left.first)
        #expect(kept.id == filedID, "The declaration already filed is kept, so no reminder comes back for it")
        #expect(kept.dueDay == CalendarDay("2028-05-25"))
        #expect(kept.history.count == 1, "Its completion stays")
        #expect(document.obligation?.id == filedID)
        #expect(kept.updatedAt == then, "Keeping one copy is the app's own step: no new change time")
    }

    @Test("What the copy that goes recorded moves onto the one that stays")
    func theOtherCopysRecordsMove() throws {
        let (context, filed, due, _) = try merged(filedHasSmallerID: true, filedFirst: true)
        // The copy still due has a document of its own: it comes over.
        let receipt = DosarCuSina.Attachment(fileName: "recipisa.pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8))
        context.insert(receipt)
        receipt.obligation = due
        try context.save()
        let receiptTime = receipt.updatedAt

        try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2027-05-12"))

        #expect(receipt.obligation?.id == filed.id)
        #expect(receipt.updatedAt == receiptTime, "Moved by the app's own step: it keeps its change time")
        #expect(try context.fetchCount(FetchDescriptor<DosarCuSina.Attachment>()) == 2, "No document goes with the copy")
    }

    @Test("Copies just as far on: the one with the smallest id stays, on every phone", arguments: [true, false])
    func aTieKeepsTheSmallestID(smallerFirst: Bool) throws {
        let context = try makeContext()
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        for id in smallerFirst ? [Self.smaller, Self.larger] : [Self.larger, Self.smaller] { _ = declaration(id: id, in: context) }
        try context.save()

        try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-10"))

        #expect(try declarations(in: context).map(\.id) == [Self.smaller])
    }

    @Test("The overdue copy the person worked on stays over a fresh one, with its note, reminders and snooze, in any order",
          arguments: [true, false], [true, false])
    func theOverdueCopyStays(overdueHasSmallerID: Bool, overdueFirst: Bool) throws {
        let context = try makeContext()
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        let ids = overdueHasSmallerID ? (Self.smaller, Self.larger) : (Self.larger, Self.smaller)
        func overdue() -> Obligation {
            let copy = declaration(id: ids.0, due: CalendarDay("2026-05-25"), in: context)
            copy.notes = "Am cerut adeverința de la bancă."
            copy.reminders = copy.reminders.withLeadDays([14])
            copy.remindersCustomized = true
            copy.snoozedUntil = CalendarDay("2026-06-05")
            return copy
        }
        let first = overdueFirst ? overdue() : nil
        _ = declaration(id: ids.1, in: context)
        let overdueCopy = first ?? overdue()
        try context.save()
        let overdueID = overdueCopy.id

        try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-06-01"))

        let left = try declarations(in: context)
        #expect(left.map(\.id) == [overdueID], "The copy the person was working on stays")
        let stays = try #require(left.first)
        #expect(stays.dueDay == CalendarDay("2026-05-25"), "Still overdue: the fresh copy's later day never hides it")
        #expect(stays.notes == "Am cerut adeverința de la bancă.")
        #expect(stays.reminders.leadDays == [14])
        #expect(stays.snoozedUntil == CalendarDay("2026-06-05"))
    }

    @Test("Of two copies nobody touched, the one still open earliest stays")
    func theEarliestOpenCopyStays() throws {
        let context = try makeContext()
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        _ = declaration(id: Self.smaller, in: context)
        let earlier = declaration(id: Self.larger, due: CalendarDay("2026-05-25"), in: context)
        try context.save()
        let earlierID = earlier.id

        try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-06-01"))

        #expect(try declarations(in: context).map(\.id) == [earlierID])
    }

    @Test("What the person wrote on the copy that goes comes over when the copy that stays has none")
    func theNoteComesOver() throws {
        let (context, filed, due, _) = try merged(filedHasSmallerID: true, filedFirst: true)
        due.notes = "Chiriașul a plătit în avans."
        try context.save()
        let filedID = filed.id

        try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2027-05-12"))

        let left = try declarations(in: context)
        #expect(left.map(\.id) == [filedID], "The filed copy stays")
        #expect(left.first?.notes == "Chiriașul a plătit în avans.")
    }

    @Test("No declaration is made while the binder is still arriving: the person's own may be on its way")
    func noDeclarationWhileArriving() throws {
        let context = try makeContext()
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        try context.save()
        let container = context.container
        CloudArrival.awaitFirstDownload(in: container)

        #expect(try !LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-10")))
        #expect(try declarations(in: context).isEmpty)

        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: noon("2026-11-10"), succeeded: true), in: container)
        #expect(try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-10")))
        #expect(try declarations(in: context).count == 1, "Made once all of it has come")
    }

    @Test("Copies are joined only once the binder has arrived: a completion may still be on its way")
    func copiesWaitForTheBinder() throws {
        let context = try makeContext()
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        _ = declaration(id: Self.smaller, in: context)
        _ = declaration(id: Self.larger, in: context)
        try context.save()
        let container = context.container
        CloudArrival.awaitFirstDownload(in: container)

        _ = try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-10"))
        #expect(try declarations(in: context).count == 2, "Nothing goes while the binder is arriving")

        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: noon("2026-11-10"), succeeded: true), in: container)
        #expect(try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-10")))
        #expect(try declarations(in: context).count == 1)
    }

    @Test("Two copies of one record (one backup brought in on two phones) are left to the copy rule")
    func copiesOfOneRecordAreRecordsMeets() throws {
        let context = try makeContext()
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        let first = declaration(id: Self.smaller, in: context)
        let second = declaration(id: Self.smaller, in: context)
        try context.save()

        _ = try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-10"))
        let left = try declarations(in: context)
        #expect(left.count == 2, "The household rules can't tell them apart, so each phone would keep its own")
        #expect(left.contains { $0 === first } && left.contains { $0 === second })

        _ = try RecordsMeet.join(in: context)
        try context.save()
        #expect(try declarations(in: context).count == 1, "The copy rule joins them, the same way on every phone")
    }
}
