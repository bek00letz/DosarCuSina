import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A deletion that arrives from another device never takes with it what this device added
/// meanwhile (database version 18): the database only lets go of the links, each record keeps
/// the id of what held it (`ParentLinks`), goes back to a copy with that id, or waits in the
/// repair list to be kept in „Recuperate” (`LostRecordsStep`); and the app's own deletions
/// still take what a record holds (`RecordContents`). Every value is a placeholder.
@MainActor
@Suite("What a deletion from another device leaves")
struct ParentLinksTests {
    // MARK: Database version 18

    @Test func versionEighteenOnlyAddsWhatHoldsEachRecordByID() throws {
        let seventeen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV17.models))
        let eighteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV18.models))
        let added: [String: Set<String>] = [
            "Obligation": ["assetID"], "Attachment": ["assetID"], "HistoryEntry": ["assetID"],
            "MeasurementLog": ["assetID"], "ServiceItem": ["entryID"], "AttachmentPage": ["attachmentID"],
        ]
        #expect(Set(eighteen.entitiesByName.keys) == Set(seventeen.entitiesByName.keys))
        for (name, after) in eighteen.entitiesByName {
            let before = try #require(seventeen.entitiesByName[name])
            let new = Set(after.attributesByName.keys).subtracting(before.attributesByName.keys)
            #expect(new == added[name, default: []], "\(name)")
            for key in new { #expect(after.attributesByName[key]?.isOptional == true, "\(name).\(key) may be empty, as CloudKit needs") }
            #expect(Set(after.relationshipsByName.keys) == Set(before.relationshipsByName.keys), "\(name) keeps its links")
            for relationship in after.relationshipsByName.values {
                #expect(relationship.deleteRule != .cascadeDeleteRule, "\(name).\(relationship.name): the app deletes what a record holds, never the database")
            }
        }
        // The frozen version 17 is version 16 with the lessons' category, nothing more.
        let sixteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV16.models))
        for (name, hash) in sixteen.entityVersionHashesByName where name != "IssuerLesson" {
            #expect(seventeen.entityVersionHashesByName[name] == hash, "\(name) is as version 16 shipped it")
        }
        let lessons = try #require(seventeen.entitiesByName["IssuerLesson"]), before = try #require(sixteen.entitiesByName["IssuerLesson"])
        #expect(Set(lessons.attributesByName.keys).subtracting(before.attributesByName.keys) == ["categoryKey"])
    }

    @Test func aStoreFromVersionSeventeenOpensWithEverythingAndNoIDsYet() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v17.store")
        let edited = noon("2026-10-01")
        do {
            let schema = Schema(versionedSchema: DosarSchemaV17.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let car = DosarSchemaV17.Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
            car.updatedAt = edited
            let itp = DosarSchemaV17.Obligation(title: "ITP")
            itp.dueDayISO = "2027-07-15"
            for model in [car, itp] as [any PersistentModel] { context.insert(model) }
            itp.asset = car
            try context.save()
        }
        let context = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first)
        #expect(car.updatedAt == edited, "An upgrade isn't a change")
        let itp = try #require(car.obligations?.first)
        #expect(itp.dueDay == CalendarDay("2027-07-15"))
        #expect(itp.assetID == nil, "Written as it is next saved, never all at once")
    }

    // MARK: The ids follow the links

    @Test func everySaveWritesWhatHoldsEachRecord() throws {
        let context = try makeContext()
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        let other = Asset(name: "Dacia Logan 2020", templateKey: BuiltInTemplates.Key.vehicle)
        let itp = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2027-07-15"))
        let invoice = DosarCuSina.Attachment(fileName: "factura.pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8))
        let page = AttachmentPage(index: 0, imageData: Data([1]))
        let visit = HistoryEntry(kind: .visit, title: "Revizie", occurredAt: noon("2026-10-01"))
        let oil = ServiceItem(name: "Ulei")
        for model in [car, other, itp, invoice, page, visit, oil] as [any PersistentModel] { context.insert(model) }
        itp.asset = car
        invoice.asset = car
        page.attachment = invoice
        visit.asset = car
        oil.entry = visit
        try UnitOfWork.save(context)
        #expect(itp.assetID == car.id && invoice.assetID == car.id && visit.assetID == car.id)
        #expect(page.attachmentID == invoice.id && oil.entryID == visit.id)

        try UnitOfWork.perform(in: context) {
            itp.asset = other
            invoice.asset = nil
            try UnitOfWork.save(context)
        }
        #expect(itp.assetID == other.id, "Moved: the id follows")
        #expect(invoice.assetID == nil, "Let go of by the app: no section to go back to")
    }

    // MARK: A deletion from another device

    /// A car with an ITP, a document with its page and a visit with its part, saved as the app
    /// saves them; then the car deleted as iCloud brings another device's deletion in: on the
    /// context, outside the app's steps.
    private func carDeletedElsewhere() throws -> (ModelContext, carID: UUID) {
        let context = try makeContext()
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        let itp = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2027-07-15"))
        let invoice = DosarCuSina.Attachment(fileName: "factura.pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8))
        let page = AttachmentPage(index: 0, imageData: Data([1]))
        let visit = HistoryEntry(kind: .visit, title: "Revizie", occurredAt: noon("2026-10-01"))
        let oil = ServiceItem(name: "Ulei")
        let reading = MeasurementLog(kind: .odometer, name: "Kilometraj", value: 45_724)
        for model in [car, itp, invoice, page, visit, oil, reading] as [any PersistentModel] { context.insert(model) }
        itp.asset = car
        invoice.asset = car
        page.attachment = invoice
        visit.asset = car
        oil.entry = visit
        reading.asset = car
        try UnitOfWork.save(context)
        let id = car.id
        context.delete(car)
        try context.save()
        return (context, id)
    }

    @Test func aDeletionFromAnotherDeviceLeavesWhatTheSectionHeld() throws {
        let (context, carID) = try carDeletedElsewhere()
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 0)
        let itp = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(itp.asset == nil && itp.assetID == carID, "It stays, and still names its section")
        #expect(try context.fetchCount(FetchDescriptor<DosarCuSina.Attachment>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AttachmentPage>()) == 1, "A document's pages stay with it")
        #expect(try context.fetchCount(FetchDescriptor<ServiceItem>()) == 1, "A visit's parts stay with it")
        #expect(try context.fetchCount(FetchDescriptor<MeasurementLog>()) == 1)
    }

    @Test("A copy of the section with its id takes everything back, as two copies joined on another device leave it")
    func everythingGoesBackToACopyWithItsID() throws {
        let (context, carID) = try carDeletedElsewhere()
        let kept = Asset(id: carID, name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(kept)
        try context.save()

        #expect(try ParentLinks.rehome(in: context))
        #expect(kept.obligations?.count == 1)
        #expect(kept.attachments?.count == 1)
        #expect(kept.history?.count == 1)
        #expect(kept.measurements?.count == 1)
        #expect(try ParentLinks.loose(in: context).isEmpty)
        #expect(try !ParentLinks.rehome(in: context), "Nothing left to put back")
    }

    @Test func whatLostItsSectionIsKeptInRecuperate() throws {
        let (context, _) = try carDeletedElsewhere()
        let repairs = DataRepairs(context: context, calendar: .bucharest,
                                  ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "repairs-\(UUID().uuidString)")!))
        let found = try repairs.detect().filter { $0.step == .lostRecords }
        #expect(found.count == 4, "A deadline, a document, a visit and a reading; never a part or a page")
        #expect(found.allSatisfy { !$0.message.contains("ITP") && !$0.message.contains("factura") }, "The section's lock isn't known: nothing is named")

        try repairs.apply(found)
        let section = try #require(Asset.find(LostRecordsStep.sectionID.uuidString, in: context))
        #expect(section.templateKey == LostRecordsStep.categoryKey)
        #expect(section.obligations?.count == 1 && section.attachments?.count == 1 && section.history?.count == 1 && section.measurements?.count == 1)
        #expect(try repairs.detect().filter { $0.step == .lostRecords }.isEmpty)
        #expect(try TemplateStore(context: context).templatesByKey()[LostRecordsStep.categoryKey]?.isCustom == true)
    }

    @Test func nothingIsOfferedWhileTheBinderIsArriving() throws {
        let (context, _) = try carDeletedElsewhere()
        CloudArrival.awaitFirstDownload(in: context.container)
        #expect(try LostRecordsStep.lost(in: context).isEmpty, "The section, or its deletion of them, may be on its way")
        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: noon("2026-11-10"), succeeded: true), in: context.container)
        #expect(try LostRecordsStep.lost(in: context).count == 4)
    }

    // MARK: The app's own deletions

    @Test func deletingASectionHereStillTakesWhatItHeld() throws {
        let context = try makeContext()
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        let itp = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2027-07-15"))
        let invoice = DosarCuSina.Attachment(fileName: "factura.pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8))
        let page = AttachmentPage(index: 0, imageData: Data([1]))
        let visit = HistoryEntry(kind: .visit, title: "Revizie", occurredAt: noon("2026-10-01"))
        let oil = ServiceItem(name: "Ulei")
        for model in [car, itp, invoice, page, visit, oil] as [any PersistentModel] { context.insert(model) }
        itp.asset = car
        invoice.asset = car
        page.attachment = invoice
        visit.asset = car
        oil.entry = visit
        try UnitOfWork.save(context)

        let receipt = try AssetActions(context: context).delete(car)
        for count in [try context.fetchCount(FetchDescriptor<Obligation>()), try context.fetchCount(FetchDescriptor<DosarCuSina.Attachment>()),
                      try context.fetchCount(FetchDescriptor<AttachmentPage>()), try context.fetchCount(FetchDescriptor<HistoryEntry>()),
                      try context.fetchCount(FetchDescriptor<ServiceItem>())] {
            #expect(count == 0)
        }
        try receipt.undo()
        let back = try #require(try context.fetch(FetchDescriptor<Asset>()).first)
        #expect(back.obligations?.count == 1 && back.attachments?.first?.pages?.count == 1 && back.history?.first?.items?.count == 1,
                "Undo brings all of it back, with every link")
    }

    @Test("What the app deletes with a record is every relationship it says it holds, of the schema's own")
    func whatARecordHoldsIsTheSchemasRelationships() {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        for (type, names) in RecordContents.owned {
            let entity = schema.entities.first { $0.name == type }
            #expect(entity != nil, "\(type) is a model")
            #expect(names.isSubset(of: Set(entity?.relationships.map(\.name) ?? [])), "\(type): each is one of its relationships")
        }
    }

    @Test func deletingADocumentOrAVisitTakesItsPagesOrParts() throws {
        let context = try makeContext()
        let invoice = DosarCuSina.Attachment(fileName: "factura.pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8))
        let page = AttachmentPage(index: 0, imageData: Data([1]))
        let visit = HistoryEntry(kind: .visit, title: "Revizie", occurredAt: noon("2026-10-01"))
        let oil = ServiceItem(name: "Ulei")
        for model in [invoice, page, visit, oil] as [any PersistentModel] { context.insert(model) }
        page.attachment = invoice
        oil.entry = visit
        try UnitOfWork.save(context)

        try AttachmentActions(context: context).delete(invoice)
        #expect(try context.fetchCount(FetchDescriptor<AttachmentPage>()) == 0)
        try HistoryActions(context: context).delete(visit)
        #expect(try context.fetchCount(FetchDescriptor<ServiceItem>()) == 0)
    }
}
