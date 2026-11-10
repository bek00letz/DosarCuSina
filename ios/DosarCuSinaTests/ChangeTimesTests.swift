import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// One rule for when a record last changed, kept by the unit of work as it saves, for every
/// kind of record: what a backup brought in with "Adaugă" compares.
@MainActor
@Suite("Change times")
struct ChangeTimesTests {
    let long = noon("2025-06-01")

    /// A section with a visit, a line item, a reading and a document with one page, saved
    /// with an old change time each, straight to the store.
    @MainActor
    struct Records {
        let context: ModelContext
        let car: Asset
        let visit: HistoryEntry
        let item: ServiceItem
        let reading: MeasurementLog
        let document: DosarCuSina.Attachment
        let page: AttachmentPage

        static func make(at time: Date) throws -> Records {
            let context = try makeContext()
            let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
            let visit = HistoryEntry(kind: .visit, title: "Revizie", occurredAt: time)
            let item = ServiceItem(name: "Filtru ulei")
            let reading = MeasurementLog(kind: .odometer, name: "", value: 100_000, recordedAt: time)
            let document = DosarCuSina.Attachment(fileName: "factura.heic", contentType: "public.heic", data: nil, kind: .invoice)
            let page = AttachmentPage(index: 0, imageData: Data([1, 2, 3]))
            for model in [car, visit, item, reading, document, page] as [any PersistentModel] { context.insert(model) }
            visit.asset = car
            item.entry = visit
            reading.asset = car
            document.asset = car
            page.attachment = document
            for record in [car, visit, item, reading, document] as [any ChangeTimed] { record.updatedAt = time }
            try context.save()
            return Records(context: context, car: car, visit: visit, item: item, reading: reading, document: document, page: page)
        }
    }

    @Test("A change to any kind of record gives it a new change time when it saves")
    func aChangeGivesANewTime() throws {
        let records = try Records.make(at: long)
        records.car.notes = "Cauciucuri de iarnă."
        records.visit.note = "Cu filtrul de aer."
        records.item.notes = "Original."
        records.reading.notes = "De pe bord."
        records.document.title = "Factură revizie"
        try UnitOfWork.save(records.context)
        for record in [records.car, records.visit, records.item, records.reading, records.document] as [any ChangeTimed] {
            #expect(record.updatedAt > long, "\(type(of: record)) changed")
        }
    }

    @Test("A section that only gets something new linked to it hasn't changed")
    func beingLinkedToIsNoChange() throws {
        let records = try Records.make(at: long)
        let second = HistoryEntry(kind: .repair, title: "Frâne", occurredAt: Date())
        records.context.insert(second)
        second.asset = records.car
        let invoice = DosarCuSina.Attachment(fileName: "frane.pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8))
        records.context.insert(invoice)
        invoice.historyEntry = records.visit
        try UnitOfWork.save(records.context)
        #expect(records.car.updatedAt == long)
        #expect(records.visit.updatedAt == long, "A visit that gets a document keeps its time: the document keeps the link")
        #expect(second.updatedAt > long, "What is made new has the time it was made")
    }

    @Test("A page is a change to its document: added, changed or taken away")
    func aPageChangesItsDocument() throws {
        let records = try Records.make(at: long)
        records.page.imageData = Data([9])
        try UnitOfWork.save(records.context)
        let changed = records.document.updatedAt
        #expect(changed > long)

        records.document.updatedAt = long
        try records.context.save()
        let back = AttachmentPage(index: 1, imageData: Data([4]))
        records.context.insert(back)
        back.attachment = records.document
        try UnitOfWork.save(records.context)
        #expect(records.document.updatedAt > long)

        records.document.updatedAt = long
        try records.context.save()
        records.context.delete(back)
        try UnitOfWork.save(records.context)
        #expect(records.document.updatedAt > long)
    }

    @Test("A step with a clock of its own gives its time, through the unit of work")
    func aStepsOwnTimeWins() throws {
        let records = try Records.make(at: long)
        let own = noon("2026-11-02")
        records.visit.note = "Corectat."
        try UnitOfWork.save(records.context, now: own)
        #expect(records.visit.updatedAt == own)
    }

    @Test("A time written by hand is no way around the unit of work: the change gets the step's time")
    func aHandWrittenTimeIsReplaced() throws {
        let records = try Records.make(at: long)
        records.visit.note = "Corectat."
        records.visit.updatedAt = noon("2020-01-01")
        try UnitOfWork.save(records.context, now: noon("2026-11-02"))
        #expect(records.visit.updatedAt == noon("2026-11-02"))
    }

    @Test("Writing a value a record already has changes nothing")
    func theSameValueIsNoChange() throws {
        let records = try Records.make(at: long)
        let note = records.visit.note
        let value = records.reading.value
        records.visit.note = note
        records.reading.value = value
        try UnitOfWork.save(records.context)
        #expect(records.visit.updatedAt == long)
        #expect(records.reading.updatedAt == long)
    }

    @Test("A unit of work gives every change in it a change time, saved once")
    func aUnitOfWorkKeepsChangeTimes() throws {
        let records = try Records.make(at: long)
        try UnitOfWork.perform(in: records.context) {
            records.item.notes = "Schimbat."
            records.reading.value = 100_500
        }
        #expect(records.item.updatedAt > long)
        #expect(records.reading.updatedAt > long)
        #expect(records.visit.updatedAt == long)
    }

    @Test("Undo puts change times back with everything else")
    func undoPutsChangeTimesBack() throws {
        let records = try Records.make(at: long)
        let receipt = try UnitOfWork.performUndoable(in: records.context) {
            records.visit.title = "Revizie anuală"
            records.page.imageData = Data([8])
        }.receipt
        #expect(records.visit.updatedAt > long)
        #expect(records.document.updatedAt > long)
        try receipt.undo()
        #expect(records.visit.updatedAt == long)
        #expect(records.document.updatedAt == long)
        #expect(records.visit.title == "Revizie")
    }

    @Test("A record from before change times were kept is older than any change")
    func unknownIsOlderThanAnyChange() {
        #expect(ChangeTime.unknown == .distantPast)
        #expect(HistoryEntry(kind: .note, title: "", occurredAt: Date()).updatedAt > ChangeTime.unknown, "A new record has the time it was made")
    }
}
