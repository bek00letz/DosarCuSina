import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Two phones with a tenancy each make their own rental income declaration; "Adaugă" brings
/// both copies together. The household keeps one, the same one whatever order they are read
/// in: the copy furthest on, with everything the other recorded.
@MainActor
@Suite("Copies of a household deadline")
struct HouseholdDeadlineCopiesTests {
    let calendar = Calendar.bucharest
    let then = noon("2026-06-01")
    static let smaller = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let larger = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    private func declaration(id: UUID, in context: ModelContext) -> Obligation {
        let blueprint = HouseholdRules.rentalDeclaration
        let obligation = Obligation(id: id, title: blueprint.title, kind: blueprint.kind, dueDay: CalendarDay("2027-05-25"),
                                    recurrence: blueprint.recurrence, reminders: blueprint.reminders)
        obligation.blueprintKey = blueprint.key
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
}
