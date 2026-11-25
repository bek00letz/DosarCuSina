import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Locking travels, opening doesn't (database version 19): a category locked on one device is
/// locked on every device that hasn't opened it since, a new one included; opening it with Face ID
/// opens it only on the device that opens it; and each device sends up the locks it already had,
/// once (`LockPublishing`). Every value is a placeholder.
@MainActor
@Suite("Locks travel, opening stays")
struct LocksTravelTests {
    let earlier = noon("2026-11-20")
    let later = noon("2026-11-25")

    // MARK: Database version 19

    @Test func versionNineteenOnlyAddsWhenACategoryWasLockedEverywhere() throws {
        let eighteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV18.models))
        let nineteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: CurrentSchema.models))
        for (entity, hash) in eighteen.entityVersionHashesByName where entity != "CategoryTemplate" {
            #expect(nineteen.entityVersionHashesByName[entity] == hash, "\(entity) is as version 18 shipped it")
        }
        let before = try #require(eighteen.entitiesByName["CategoryTemplate"]), after = try #require(nineteen.entitiesByName["CategoryTemplate"])
        #expect(Set(after.attributesByName.keys).subtracting(before.attributesByName.keys) == ["lockedEverywhereAt"])
        #expect(after.attributesByName["lockedEverywhereAt"]?.isOptional == true, "Optional, as CloudKit needs")

        // The frozen version 18 is version 17 with the ids of what holds each record, and no cascade.
        let seventeen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV17.models))
        let ids: [String: Set<String>] = [
            "Obligation": ["assetID"], "Attachment": ["assetID"], "HistoryEntry": ["assetID"],
            "MeasurementLog": ["assetID"], "ServiceItem": ["entryID"], "AttachmentPage": ["attachmentID"],
        ]
        for (name, entity) in eighteen.entitiesByName {
            let old = try #require(seventeen.entitiesByName[name])
            #expect(Set(entity.attributesByName.keys).subtracting(old.attributesByName.keys) == ids[name, default: []], "\(name)")
            #expect(entity.relationshipsByName.values.allSatisfy { $0.deleteRule != .cascadeDeleteRule }, "\(name)")
        }
    }

    @Test func aStoreFromVersionEighteenOpensWithItsCategoriesNeverLockedEverywhere() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v18.store")
        do {
            let schema = Schema(versionedSchema: DosarSchemaV18.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let cars = DosarSchemaV18.CategoryTemplate(key: BuiltInTemplates.Key.vehicle)
            cars.isBuiltIn = true
            cars.homeOrder = 3
            context.insert(cars)
            try context.save()
        }
        let context = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let cars = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first)
        #expect(cars.homeOrder == 3)
        #expect(cars.lockedEverywhereAt == nil)
    }

    // MARK: The rule

    @Test func aLockMadeElsewhereLocksUnlessThisDeviceOpenedItSince() throws {
        let locks = SectionLocks(file: nil)
        let key = "custom.exemplu"
        #expect(!locks.isLocked(key, byDefault: false), "Never locked anywhere, never chosen here")
        #expect(locks.isLocked(key, byDefault: false, lockedEverywhereAt: earlier), "Locked on another device: locked here, a new device included")

        try locks.set(false, for: key, at: later)
        #expect(!locks.isLocked(key, byDefault: false, lockedEverywhereAt: earlier), "Opened here since: open here")
        #expect(locks.isLocked(key, byDefault: false, lockedEverywhereAt: noon("2026-11-26")), "Locked again elsewhere since: locked here again")

        try locks.set(true, for: key, at: later)
        #expect(locks.isLocked(key, byDefault: false, lockedEverywhereAt: nil), "Locked here stays locked here")
    }

    @Test func whenEachChoiceWasMadeIsKeptBesideTheChoices() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "locks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Dosar.store.section-locks.json")
        try SectionLocks(file: file).set(false, for: "custom.exemplu", at: later)

        let reopened = SectionLocks(file: file)
        #expect(!reopened.isLocked("custom.exemplu", byDefault: false, lockedEverywhereAt: earlier), "Its time came back with it")
        #expect(SectionLocks.timesFile(for: file).lastPathComponent.hasPrefix(file.lastPathComponent),
                "Named after the choices, so „Începe din nou” leaves both")

        try FileManager.default.removeItem(at: SectionLocks.timesFile(for: file))
        #expect(SectionLocks(file: file).isLocked("custom.exemplu", byDefault: false, lockedEverywhereAt: earlier),
                "A choice whose time is lost is older than any lock made elsewhere: locked")
    }

    // MARK: Locking and opening

    @Test func lockingACategoryLocksItEverywhereAndOpeningOpensItHereOnly() async throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let template = try store.createCustom(name: "Colecție", symbol: "star", pockets: [.documents])
        #expect(template.lockedEverywhereAt == nil, "Made open: nothing to send")

        try store.setSensitive(template, true)
        let lockedAt = try #require(template.lockedEverywhereAt, "Locking it is written on its record, which iCloud carries")
        #expect(template.isSensitive)

        try store.setSensitive(template, false, lowering: try await faceIDConfirmed())
        #expect(!template.isSensitive, "Open on this device")
        #expect(template.lockedEverywhereAt == lockedAt, "Opening never clears it: no device opens a section on another")

        try store.setSensitive(template, true)
        #expect(try #require(template.lockedEverywhereAt) >= lockedAt, "Locked again: the newest lock travels")
    }

    @Test func aCategoryOfOnesOwnMadeLockedIsLockedEverywhere() throws {
        let context = try makeContext()
        let template = try TemplateStore(context: context).createCustom(name: "Medical", symbol: "cross", pockets: [.documents], isSensitive: true)
        #expect(template.lockedEverywhereAt != nil)
        #expect(template.isSensitive)
    }

    // MARK: Sending up the locks a device already had

    @Test func eachDeviceSendsUpTheLocksItHadOnce() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let locked = try store.createCustom(name: "Colecție", symbol: "star", pockets: [.documents])
        let open = try store.createCustom(name: "Plante rare", symbol: "leaf", pockets: [.documents])
        // A lock chosen before locking travelled: on this device only, with no time.
        try SectionLocks.of(context.container).set(true, for: locked.key, at: earlier)
        #expect(locked.lockedEverywhereAt == nil)

        #expect(try LockPublishing.publish(in: context, now: later))
        #expect(locked.lockedEverywhereAt == earlier, "When this device locked it")
        #expect(open.lockedEverywhereAt == nil, "An open category sends nothing")
        #expect(try !LockPublishing.publish(in: context, now: later), "Once")
    }
}
