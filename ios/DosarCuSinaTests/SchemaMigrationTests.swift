import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A frozen schema version must keep exactly the shape its stores have on people's
/// phones, or a migration can't recognise them. These pin each frozen version, and
/// prove a store written by the version before opens with everything in it.
@MainActor
struct SchemaMigrationTests {
    /// Each entity's version hash, as Core Data computes it, base64.
    static func fingerprint(_ models: [any PersistentModel.Type]) -> [String: String] {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else { return [:] }
        return model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
    }

    /// Version 2 as it shipped, read from the shipped models before version 3 existed.
    static let versionTwo: [String: String] = [
        "Asset": "58a6RIU1oRUxD3p2eFaJmRdPZEPsiXxOu/r0Cdbm4z0=",
        "Attachment": "zD/yZCgadMdd5p994OVXoj/NyBuzEO45epzaa4J6Wb8=",
        "AttachmentPage": "JuCkdlh81AVcycaJFrC8aBf8R7nkEg6kKyfUIOP9QdI=",
        "CategoryTemplate": "YVKd3GclUkHBd4xpJ54GbQx35yrBKhoQoEg89e2ScZo=",
        "HistoryEntry": "PuXnfDrnwWK/La9Ngj9fOIPjAGMOxeYuOxGRZz3Tz5o=",
        "MeasurementLog": "mIGxZoQpHOMXhYrVjhP+5Mo5Qa9Gh9Y4Dzk9+PZ4hwc=",
        "Obligation": "Xum2PE0uCd+kj/oD/bGcZ/ZZOPlFS2+2EGGSQUHwpL0=",
        "Provider": "Wau7/mbwtsfNfdHqO47ak8Kxm2f/2Y0i9Loq3oOPy4c=",
        "ServiceItem": "oLmMn8P7Qhm9kwaqXLTT6ppsedzdzLP99yAFaoqtgCw=",
    ]

    @Test func theFrozenVersionTwoKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV2.models) == Self.versionTwo)
    }

    /// Version 3 as it shipped: version 2 with a firm's tax ID, a category's behaviour and a
    /// paper's last valid day. Every entity but deadlines is pinned again by version 4 below,
    /// which was made from the shipped models.
    static let versionThree: [String: String] = [
        "Asset": "58a6RIU1oRUxD3p2eFaJmRdPZEPsiXxOu/r0Cdbm4z0=",
        "Attachment": "djPOkwOcI2y3EekaK6X63Ktf1r+QFW98LFYaEkrkrwE=",
        "AttachmentPage": "JuCkdlh81AVcycaJFrC8aBf8R7nkEg6kKyfUIOP9QdI=",
        "CategoryTemplate": "6ISuox65O5PR9u6cYpQ9MKBEqdCrUMgGOFTuEMpsZhg=",
        "HistoryEntry": "PuXnfDrnwWK/La9Ngj9fOIPjAGMOxeYuOxGRZz3Tz5o=",
        "MeasurementLog": "mIGxZoQpHOMXhYrVjhP+5Mo5Qa9Gh9Y4Dzk9+PZ4hwc=",
        "Obligation": "Xum2PE0uCd+kj/oD/bGcZ/ZZOPlFS2+2EGGSQUHwpL0=",
        "Provider": "q0DxoXrt4EWS6yXxmvgMH5Z2iOyuc8aZ5QoFphvUZw4=",
        "ServiceItem": "oLmMn8P7Qhm9kwaqXLTT6ppsedzdzLP99yAFaoqtgCw=",
    ]

    @Test func versionThreeIsANewShape() {
        let three = Self.fingerprint(DosarSchemaV3.models)
        #expect(three["Provider"] != Self.versionTwo["Provider"])
        #expect(three["CategoryTemplate"] != Self.versionTwo["CategoryTemplate"])
        #expect(three["Attachment"] != Self.versionTwo["Attachment"])
        #expect(three["Asset"] == Self.versionTwo["Asset"], "Only what version 3 adds changes")
    }

    @Test func theFrozenVersionThreeKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV3.models) == Self.versionThree)
        #expect(Self.versionThree["Obligation"] == Self.versionTwo["Obligation"], "Version 3 didn't change deadlines")
    }

    @Test func versionFourChangesOnlyDeadlines() {
        let four = Self.fingerprint(DosarSchemaV4.models)
        for (entity, hash) in Self.versionThree where entity != "Obligation" {
            #expect(four[entity] == hash, "\(entity) is as version 3 shipped it")
        }
        #expect(four["Obligation"] != Self.versionThree["Obligation"], "A deadline keeps its travel margin")
    }

    /// Version 4 as it shipped: version 3 with a deadline's travel margin.
    static let versionFour: [String: String] = versionThree.merging(["Obligation": "u0tiMcTlS/moad/uiA4LliY6jt452A0rMNTLoP3U33Y="]) { $1 }

    @Test func theFrozenVersionFourKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV4.models) == Self.versionFour)
    }

    @Test func versionFiveChangesOnlyDeadlines() {
        let five = Self.fingerprint(DosarSchemaV5.models)
        for (entity, hash) in Self.versionFour where entity != "Obligation" {
            #expect(five[entity] == hash, "\(entity) is as version 4 shipped it")
        }
        #expect(five["Obligation"] != Self.versionFour["Obligation"], "A deadline knows whether the person set its reminders")
    }

    /// Version 5 as it shipped: version 4 with whether the person set a deadline's reminders.
    static let versionFive: [String: String] = versionFour.merging(["Obligation": "g6w9CXVyhDkfgNfidSWvzsICUSR70fTqF3h1Z55p2Y8="]) { $1 }

    @Test func theFrozenVersionFiveKeepsTheShapeItShippedWith() {
        #expect(Self.fingerprint(DosarSchemaV5.models) == Self.versionFive)
    }

    @Test func versionSixChangesOnlyDocuments() {
        let six = Self.fingerprint(DosarSchemaV6.models)
        for (entity, hash) in Self.versionFive where entity != "Attachment" {
            #expect(six[entity] == hash, "\(entity) is as version 5 shipped it")
        }
        #expect(six["Attachment"] != Self.versionFive["Attachment"], "A document keeps how its pages are shown")
    }

    @Test func aStoreFromVersionFiveOpensWithItsDocuments() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v5.store")
        let page = Data([0xFF, 0xD8, 0xFF, 0xD9])

        // Written by version 5: an identity card's photo, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV5.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let card = DosarSchemaV5.Asset(name: "Carte de identitate", templateKey: "documents")
            let photo = DosarSchemaV5.Attachment(fileName: "Carte de identitate.heic")
            photo.title = "Carte de identitate"
            let front = DosarSchemaV5.AttachmentPage(index: 0)
            front.imageData = page
            let reminder = DosarSchemaV5.Obligation(title: "Reînnoire")
            reminder.remindersCustomized = true
            context.insert(card)
            context.insert(photo)
            context.insert(front)
            context.insert(reminder)
            photo.asset = card
            front.attachment = photo
            reminder.asset = card
            try context.save()
        }

        // Opened by this version: the photo is kept as taken and shown whole, as before.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let photo = try #require(try context.fetch(FetchDescriptor<Attachment>()).first)
        #expect(photo.title == "Carte de identitate")
        #expect(photo.orderedPages.first?.imageData == page)
        #expect(photo.framingData == nil)
        #expect(photo.framing.isPlain)
        #expect(try context.fetch(FetchDescriptor<Obligation>()).first?.remindersCustomized == true)

        // The new attribute is kept.
        photo.framing = DocumentFraming(pages: [PageFraming(quarterTurns: 1)])
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Attachment>()).first?.framing[page: 0].shownQuarterTurns == 1)
    }

    @Test func aStoreFromVersionFourOpensWithItsDeadlines() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v4.store")
        let deadlineID = UUID()

        // Written by version 4: a passport's deadline with its cut-off, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV4.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let passport = DosarSchemaV4.Asset(name: "Pașaport", templateKey: "documents")
            passport.valuesData = StoredJSON.encode(FieldValues([DocumentType.typeFieldKey: .text(DocumentType.passport)]))
            let renewal = DosarSchemaV4.Obligation(title: "Reînnoire")
            renewal.id = deadlineID
            renewal.blueprintKey = BuiltInBlueprints.documentRenew
            renewal.kindRaw = ObligationKind.renewal.rawValue
            renewal.reminderLeadDays = [90, 0]
            renewal.consequenceRaw = Consequence.legal.rawValue
            renewal.followUpAfterLapse = true
            renewal.travelMarginDays = 180
            context.insert(passport)
            context.insert(renewal)
            renewal.asset = passport
            try context.save()
        }

        // Opened by this version: everything kept, and the reminders aren't marked as the person's.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let renewal = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(renewal.id == deadlineID)
        #expect(renewal.asset?.name == "Pașaport")
        #expect(renewal.reminders == ReminderProfile(leadDays: [90, 0], consequence: .legal, followUpAfterLapse: true, travelMarginDays: 180))
        #expect(!renewal.remindersCustomized)

        // The new attribute is kept.
        renewal.remindersCustomized = true
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Obligation>()).first?.remindersCustomized == true)
    }

    @Test func aStoreFromVersionThreeOpensWithItsDeadlines() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v3.store")
        let deadlineID = UUID()

        // Written by version 3: a passport's deadline, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let passport = DosarSchemaV3.Asset(name: "Pașaport", templateKey: "documents")
            passport.valuesData = StoredJSON.encode(FieldValues([DocumentType.typeFieldKey: .text(DocumentType.passport)]))
            let renewal = DosarSchemaV3.Obligation(title: "Reînnoire")
            renewal.id = deadlineID
            renewal.blueprintKey = BuiltInBlueprints.documentRenew
            renewal.kindRaw = ObligationKind.renewal.rawValue
            renewal.reminderLeadDays = [180, 60]
            renewal.consequenceRaw = Consequence.legal.rawValue
            renewal.followUpAfterLapse = true
            context.insert(passport)
            context.insert(renewal)
            renewal.asset = passport
            try context.save()
        }

        // Opened by this version: everything kept, no travel margin until the repair list adds it.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let renewal = try #require(try context.fetch(FetchDescriptor<Obligation>()).first)
        #expect(renewal.id == deadlineID)
        #expect(renewal.asset?.name == "Pașaport")
        #expect(renewal.reminders == ReminderProfile(leadDays: [180, 60], consequence: .legal, followUpAfterLapse: true))
        #expect(renewal.travelMarginDays == 0)

        // The new attribute is kept.
        renewal.travelMarginDays = 180
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Obligation>()).first?.reminders.travelMarginDays == 180)
    }

    @Test func aStoreFromVersionTwoOpensWithEverythingInIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v2.store")

        // Written by version 2, as a phone has it today.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let car = DosarSchemaV2.Asset(name: "VW Golf 2018", templateKey: "vehicle")
            car.valuesData = StoredJSON.encode(FieldValues(["vehicle.plate": .text("B-123-ABC")]))
            let firm = DosarSchemaV2.Provider(name: "ENGIE Romania S.A.")
            firm.trades = [ProviderTrade.mechanic.rawValue]
            let template = DosarSchemaV2.CategoryTemplate(key: "vehicle")
            template.name = "Mașini"
            let policy = DosarSchemaV2.Attachment(fileName: "Poliță RCA.pdf")
            context.insert(car)
            context.insert(firm)
            context.insert(template)
            context.insert(policy)
            firm.assets = [car]
            policy.asset = car
            try context.save()
        }

        // Opened by this version, through the migration plan.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first)
        #expect(car.name == "VW Golf 2018")
        #expect(car.values["vehicle.plate"] == .text("B-123-ABC"))
        let firm = try #require(try context.fetch(FetchDescriptor<Provider>()).first)
        #expect(firm.name == "ENGIE Romania S.A.")
        #expect(firm.taxID == nil)
        #expect(firm.assets?.map(\.id) == [car.id])
        let template = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first)
        #expect(template.behavior == .standard, "A category from before version 3 behaves as standard until the built-ins are upgraded")
        let policy = try #require(try context.fetch(FetchDescriptor<DosarSchemaV6.Attachment>()).first)
        #expect(policy.validUntil == nil)
        #expect(policy.asset?.id == car.id)

        // The new attributes are kept.
        firm.taxID = "12345678"
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<Provider>()).first?.taxID == "12345678")
    }
}
