import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Each device decides for itself what it keeps behind Face ID: a section's lock lives beside the
/// store, never in it, so iCloud never carries it and a lock opened on one device can't open a
/// section on another. Every value is a placeholder.
/// How many times something was told, for the test.
private final class Count: @unchecked Sendable {
    var value = 0
}

@MainActor
@Suite("Section locks stay on each device")
struct SectionLocksTests {
    private func store(_ folder: URL) throws -> ModelContainer {
        let container = try PersistenceController.makeContainer(storeURL: folder.appending(path: "Dosar.store"))
        try TemplateStore(context: container.mainContext).installBuiltIns()
        return container
    }

    private func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "locks-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func theLockIsNotInTheStore() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV14.models))
        let categories = try #require(model.entitiesByName["CategoryTemplate"])
        #expect(categories.attributesByName["isSensitive"] == nil, "iCloud never carries a lock")
    }

    @Test func aFirstRunLocksActeAndSanatateAsBefore() throws {
        let context = try makeContext()
        let locked = Set(try TemplateStore(context: context).all().filter(\.isSensitive).map(\.key))
        #expect(locked == SectionLocks.lockedByDefault)
        #expect(locked.contains(BuiltInTemplates.Key.documents))
    }

    @Test func aChangeFromAnotherDeviceNeverChangesThisDevicesLock() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try store(folder)
        let context = container.mainContext
        let key = BuiltInTemplates.Key.vehicle
        let vehicles = try #require(try TemplateStore(context: context).template(forKey: key))
        try TemplateStore(context: context).setSensitive(vehicles, true)
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        try TemplateStore(context: context).setSensitive(documents, false)

        // The other device changes the same categories' records, as iCloud writes them under the store.
        let fromICloud = ModelContext(container)
        fromICloud.author = "NSCloudKitMirroringDelegate.import"
        for template in try fromICloud.fetch(FetchDescriptor<CategoryTemplate>()) {
            template.homeOrder += 10
            template.isOnHome = false
        }
        try fromICloud.save()

        let fresh = Dictionary(uniqueKeysWithValues: try PersistenceController.context(in: container).fetch(FetchDescriptor<CategoryTemplate>()).map { ($0.key, $0) })
        #expect(fresh[key]?.isSensitive == true, "Locked here, it stays locked")
        #expect(fresh[BuiltInTemplates.Key.documents]?.isSensitive == false, "Opened here, it stays open")

        // Reopened, the same: the choice is kept beside the store.
        let reopened = try PersistenceController.makeContainer(storeURL: folder.appending(path: "Dosar.store"))
        #expect(try TemplateStore(context: reopened.mainContext).template(forKey: key)?.isSensitive == true)
    }

    @Test func twoDevicesLockEachForItself() throws {
        let here = try makeContext()
        let there = try makeContext()
        let key = BuiltInTemplates.Key.vehicle
        try TemplateStore(context: here).setSensitive(try #require(try TemplateStore(context: here).template(forKey: key)), true)
        #expect(try TemplateStore(context: there).template(forKey: key)?.isSensitive == false)
        try TemplateStore(context: there).setSensitive(try #require(try TemplateStore(context: there).template(forKey: BuiltInTemplates.Key.documents)), false)
        #expect(try TemplateStore(context: here).template(forKey: BuiltInTemplates.Key.documents)?.isSensitive == true)
    }

    @Test func lockingChangesNoRecordAndIsToldToWhatFollowsIt() throws {
        let context = try makeContext()
        let vehicles = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let before = vehicles.updatedAt
        let told = Count()
        let observer = NotificationCenter.default.addObserver(forName: SectionLocks.didChange, object: SectionLocks.of(context.container), queue: nil) { _ in told.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        try TemplateStore(context: context).setSensitive(vehicles, true)
        #expect(told.value == 1)
        #expect(!context.hasChanges)
        #expect(vehicles.updatedAt == before, "Nothing for iCloud or a backup's merge to carry")
    }

    @Test func aCategoryMadeLockedStaysLocked() throws {
        let context = try makeContext()
        let made = try TemplateStore(context: context).createCustom(name: "Caiet", symbol: "book", tint: .gray, sections: [], isSensitive: true)
        let key = made.key
        let fresh = try #require(try PersistenceController.context(in: context.container).fetch(FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == key })).first)
        #expect(fresh.isSensitive)
    }

    @Test func whatShowsOutsideFollowsThisDevicesLocks() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let vehicles = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf 2018", template: vehicles, values: FieldValues())
        let itp = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2027-03-01"))
        context.insert(itp)
        itp.asset = car
        try UnitOfWork.save(context)
        #expect(try ObligationSnapshot.fetchForOutside(in: context).first { $0.id == itp.id }?.isSensitive == false)

        try store.setSensitive(vehicles, true)
        // Reminders, the badge, widgets and Spotlight read these.
        #expect(try ObligationSnapshot.fetchForOutside(in: context).first { $0.id == itp.id }?.isSensitive == true)
        // Caută shows it as locked.
        let index = try SearchIndexBuilder(context: PersistenceController.context(in: context.container)).build()
        #expect(index.search("Golf").contains { $0.document.isSensitive })
    }

    @Test(arguments: [ArchiveImportMode.merge, .replace])
    func aBackupMayLockACategoryHereButNeverOpenOne(mode: ArchiveImportMode) throws {
        let source = try makeInMemoryContainer()
        let sourceContext = PersistenceController.context(in: source)
        try TemplateStore(context: sourceContext).installBuiltIns()
        let sourceStore = TemplateStore(context: sourceContext)
        try sourceStore.setSensitive(try #require(try sourceStore.template(forKey: BuiltInTemplates.Key.vehicle)), true)
        try sourceStore.setSensitive(try #require(try sourceStore.template(forKey: BuiltInTemplates.Key.documents)), false)
        let data = try DossierArchiveService(container: source, calendar: .bucharest).exportData(exportedAt: noon("2026-11-10"))

        let here = try makeContext()
        try DossierArchiveService(container: here.container, calendar: .bucharest).importArchive(data, mode: mode)
        let store = TemplateStore(context: PersistenceController.context(in: here.container))
        #expect(try store.template(forKey: BuiltInTemplates.Key.vehicle)?.isSensitive == true, "Locked in the backup: locked here too")
        #expect(try store.template(forKey: BuiltInTemplates.Key.documents)?.isSensitive == true, "Open in the backup: still locked here")
    }
}
