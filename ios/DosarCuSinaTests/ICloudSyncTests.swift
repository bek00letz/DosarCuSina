import CoreData
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// iCloud sync, everything that can be checked without iCloud: which builds sync and with which
/// configuration, the store opened to sync or not (examples keep it on the phone), the database's
/// shape CloudKit needs, the sealing keys shared through iCloud Keychain without losing this
/// device's own, what came from another device read from the store's history, and the app's own
/// steps meeting on two devices. Every value is a placeholder.
@MainActor
@Suite("iCloud sync")
struct ICloudSyncTests {
    // MARK: Which builds sync

    @Test("Development builds sync, TestFlight and the App Store wait for the switch, a test run never")
    func whichBuildsSync() {
        #expect(PersistenceController.syncIsBuiltIn(debug: true, shipsInRelease: false, testHost: false))
        #expect(!PersistenceController.syncIsBuiltIn(debug: false, shipsInRelease: false, testHost: false))
        #expect(PersistenceController.syncIsBuiltIn(debug: false, shipsInRelease: true, testHost: false))
        #expect(!PersistenceController.syncIsBuiltIn(debug: true, shipsInRelease: true, testHost: true))
        #expect(!PersistenceController.syncShipsInReleaseBuilds, "Sync reaches TestFlight only when the owner says the data layout has settled")
        #expect(!PersistenceController.syncIsBuiltIn, "The host of a test run reaches no iCloud")
    }

    @Test("A store that syncs uses only the person's private iCloud database")
    func theConfiguration() {
        let url = URL.temporaryDirectory.appending(path: "config-\(UUID().uuidString).store")
        #expect(PersistenceController.configuration(storeURL: url, inMemory: false, syncs: true).cloudKitContainerIdentifier == "iCloud.com.ar.dosarcusina.app")
        #expect(PersistenceController.configuration(storeURL: url, inMemory: false, syncs: false).cloudKitContainerIdentifier == nil)
        #expect(PersistenceController.configuration(storeURL: nil, inMemory: true, syncs: true).cloudKitContainerIdentifier == nil, "Tests and previews never sync")
    }

    @Test("The choice, from the build, the person and the examples", arguments: [
        (true, true, false, PersistenceController.SyncState.on),
        (true, true, true, .waitingForExamples),
        (true, false, false, .off),
        (true, false, true, .off),
        (false, true, false, .notInThisBuild),
    ])
    func theChoice(builtIn: Bool, wanted: Bool, examples: Bool, expected: PersistenceController.SyncState) {
        #expect(PersistenceController.choice(builtIn: builtIn, wanted: wanted, holdsExamples: examples) == expected)
    }

    @Test func theAppCanBeWokenForChangesFromICloud() throws {
        let modes = try #require(Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String])
        #expect(modes.contains("remote-notification"))
    }

    // MARK: Opening the store

    /// A controller over in-memory stores, recording whether each was opened to sync.
    private final class Opened: @unchecked Sendable {
        var syncs: [Bool] = []
        var examples = false
        var wanted = true
        /// How many times the store said it opened to sync (the sealing key shared).
        var keyShared = 0
    }

    private func controller(_ opened: Opened) -> PersistenceController {
        PersistenceController(
            storeURL: URL.temporaryDirectory.appending(path: "sync-\(UUID().uuidString).store"),
            isProtectedDataAvailable: { true },
            makeContainer: { _, syncs in
                opened.syncs.append(syncs)
                let container = try makeInMemoryContainer()
                if syncs { ContainerRetirement.markSyncing(container) }
                return container
            },
            buildSyncs: true,
            personWantsSync: { opened.wanted },
            holdsExamples: { _ in opened.examples },
            // This phone downloaded the account's binder before: examples may come in.
            memory: InMemorySyncMemory(firstDownloadFinishedFor: PersistenceController.SignedIn().id),
            didOpenToSync: { opened.keyShared += 1 }
        )
    }

    @Test func theSealingKeyIsSharedEachTimeTheStoreOpensToSyncAndOnlyThen() async {
        let opened = Opened()
        opened.examples = true
        let persistence = controller(opened)
        await persistence.settleSync()
        #expect(opened.keyShared == 0, "Not while the binder stays on the phone")

        opened.examples = false
        await persistence.settleSync()
        #expect(persistence.sync == .on)
        #expect(opened.keyShared == 1, "As soon as it opens to sync")

        opened.wanted = false
        await persistence.settleSync()
        #expect(opened.keyShared == 1, "Not when sync is turned off")

        opened.wanted = true
        await persistence.settleSync()
        #expect(opened.keyShared == 2, "Again when it is turned on")
    }

    @Test func aStoreWithoutExamplesOpensToSync() async {
        let opened = Opened()
        let persistence = controller(opened)
        await persistence.settleSync()
        #expect(persistence.sync == .on)
        #expect(opened.syncs == [false, true], "Opened without iCloud first, then to sync")
    }

    @Test func examplesKeepTheBinderOnThePhoneUntilTheyGo() async {
        let opened = Opened()
        opened.examples = true
        let persistence = controller(opened)
        await persistence.settleSync()
        #expect(persistence.sync == .waitingForExamples)
        #expect(!opened.syncs.contains(true), "Never opened to sync while examples are there")

        await persistence.settleSync()
        #expect(opened.syncs.count == 1, "Nothing changed, nothing opens again")

        opened.examples = false
        await persistence.settleSync()
        #expect(persistence.sync == .on)
        #expect(opened.syncs.last == true)
    }

    @Test func examplesComingInOpenTheStoreWithoutICloudFirst() async throws {
        let opened = Opened()
        let persistence = controller(opened)
        await persistence.settleSync()
        #expect(persistence.sync == .on)
        let local = try await persistence.loadingExamples { $0 }
        #expect(!PersistenceController.syncs(local))
        #expect(persistence.sync == .waitingForExamples)
        #expect(opened.syncs.last == false)
    }

    @Test func turningSyncOffKeepsEverythingOnThePhone() async {
        let opened = Opened()
        let persistence = controller(opened)
        await persistence.settleSync()
        opened.wanted = false
        await persistence.settleSync()
        #expect(persistence.sync == .off)
        #expect(opened.syncs.last == false)
        #expect(persistence.container != nil)
    }

    @Test(arguments: [PersistenceController.SyncState.on, .off, .waitingForExamples])
    func settingsSaysWhatSyncsInPlainWords(state: PersistenceController.SyncState) {
        let text = SyncWording.footer(for: state)
        #expect(!text.isEmpty)
        #expect(!text.contains("!"))
        #expect(!text.contains("CloudKit"), "No jargon")
    }

    // MARK: The database's shape

    @Test("Every model is shaped as CloudKit needs: defaults or optional, nothing unique, relationships optional with inverses")
    func everyModelIsCloudKitShaped() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV14.models))
        for entity in model.entities {
            #expect(entity.uniquenessConstraints.flatMap { $0 }.isEmpty, "\(entity.name ?? "") has nothing unique")
            for (name, attribute) in entity.attributesByName {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name ?? "").\(name) is optional or has a default")
            }
            for (name, relationship) in entity.relationshipsByName {
                #expect(relationship.isOptional, "\(entity.name ?? "").\(name) is optional")
                #expect(relationship.inverseRelationship != nil, "\(entity.name ?? "").\(name) has an inverse")
                #expect(relationship.deleteRule != .denyDeleteRule, "\(entity.name ?? "").\(name) doesn't deny")
            }
        }
    }

    // MARK: What came from another device

    @Test func onlyWhatAnotherDeviceWroteIsReadAsComingFromIt() throws {
        let folder = URL.temporaryDirectory.appending(path: "history-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try PersistenceController.makeContainer(storeURL: folder.appending(path: "Dosar.store"))
        let start = SyncedChanges.latestToken(in: container)

        // Saved here, through the unit of work: the app's own.
        let here = PersistenceController.context(in: container)
        let mine = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        here.insert(mine)
        try UnitOfWork.save(here)

        // Written under the store by iCloud, as the system does with another device's change.
        let fromICloud = ModelContext(container)
        fromICloud.author = "NSCloudKitMirroringDelegate.import"
        let theirs = Asset(name: "Apartament Exemplu", templateKey: BuiltInTemplates.Key.vehicle)
        fromICloud.insert(theirs)
        try fromICloud.save()

        let (changes, token) = try SyncedChanges.changes(in: container, after: start)
        let theirID = theirs.persistentModelID
        let myID = mine.persistentModelID
        #expect(changes.changed.contains(theirID))
        #expect(!changes.changed.contains(myID), "A change made here is the app's own")
        #expect(token != nil)

        // Read once: the next read starts after it.
        let (again, _) = try SyncedChanges.changes(in: container, after: token)
        #expect(again.isEmpty)

        fromICloud.delete(theirs)
        try fromICloud.save()
        let (deleted, _) = try SyncedChanges.changes(in: container, after: token)
        #expect(deleted.deleted.contains(theirID))
    }

    /// What a notification brought, kept for the test.
    private final class Received: @unchecked Sendable {
        var changes: [SearchChanges] = []
    }

    @Test func whatCameIsToldToEverythingThatFollowsTheBinder() async throws {
        let folder = URL.temporaryDirectory.appending(path: "told-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try PersistenceController.makeContainer(storeURL: folder.appending(path: "Dosar.store"))
        let synced = SyncedChanges(container: container)
        let received = Received()
        let observer = NotificationCenter.default.addObserver(forName: SyncedChanges.didArrive, object: container, queue: nil) { note in
            if let changes = note.userInfo?[SyncedChanges.changesKey] as? SearchChanges { received.changes.append(changes) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Nothing came: nothing is told.
        await synced.read()
        #expect(received.changes.isEmpty)

        let fromICloud = ModelContext(container)
        fromICloud.author = "NSCloudKitMirroringDelegate.import"
        let theirs = Asset(name: "Apartament Exemplu", templateKey: BuiltInTemplates.Key.vehicle)
        fromICloud.insert(theirs)
        try fromICloud.save()
        await synced.read()
        #expect(received.changes.count == 1)
        #expect(received.changes.first?.changed.contains(theirs.persistentModelID) == true)
        // The app's own steps that make two binders one ran: the built-in categories are there once.
        let key = BuiltInTemplates.Key.vehicle
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == key })) == 1)
    }

    @Test func aChangeFromAnotherDeviceIsNeverTakenBackByAnUndoHere() throws {
        let folder = URL.temporaryDirectory.appending(path: "undo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try PersistenceController.makeContainer(storeURL: folder.appending(path: "Dosar.store"))
        let context = container.mainContext
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        try UnitOfWork.save(context)
        let renamed = try UnitOfWork.performUndoable(in: context) {
            car.name = "VW Golf"
            try UnitOfWork.save(context)
        }

        // The other device renames it again, under the store.
        let fromICloud = ModelContext(container)
        fromICloud.author = "NSCloudKitMirroringDelegate.import"
        let id = car.id
        let theirs = try #require(try fromICloud.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first)
        theirs.name = "VW Golf de pe celălalt telefon"
        try fromICloud.save()

        #expect(throws: (any Error).self) { try renamed.receipt.undo() }
        let now = try #require(try PersistenceController.context(in: container).fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first)
        #expect(now.name == "VW Golf de pe celălalt telefon", "The other device's change stays")
    }

    // MARK: Examples and backups

    @Test func aBackupsExamplesStayOutOfABinderThatSyncs() throws {
        let source = try makeInMemoryContainer()
        try ExampleDataService(context: source.mainContext).loadExamples()
        let real = Asset(name: "Dacia Logan 2015", templateKey: BuiltInTemplates.Key.vehicle)
        source.mainContext.insert(real)
        try UnitOfWork.save(source.mainContext)
        let package = try DossierArchiveReader.read(try DossierArchiveService(container: source, calendar: .bucharest).exportData(exportedAt: noon("2026-11-10")))
        #expect(package.assets.contains { $0.isExample })

        let target = try makeInMemoryContainer()
        _ = try DossierArchiveService.write(package, mode: .replace, container: target, calendar: .bucharest, keepsExamples: false)
        let context = ModelContext(target)
        #expect(try context.fetchCount(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample })) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Obligation>(predicate: #Predicate { $0.isExample })) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Provider>(predicate: #Predicate { $0.isExample })) == 0)
        #expect(try context.fetch(FetchDescriptor<Asset>()).contains { $0.id == real.id }, "The person's own comes in")
    }

    // MARK: Two devices' own steps meeting

    @Test func twoCopiesOfABuiltInCategoryBecomeOneWithThePersonsChoices() throws {
        let context = try makeContext()
        let key = BuiltInTemplates.Key.vehicle
        let mine = try #require(try TemplateStore(context: context).template(forKey: key))
        mine.createdAt = noon("2026-01-01")
        mine.updatedAt = ChangeTime.unknown
        // The other device's copy, installed later, moved there.
        let definition = try #require(BuiltInTemplates.definition(for: key))
        let theirs = CategoryTemplate(definition: definition, isBuiltIn: true, homeOrder: 9)
        theirs.createdAt = noon("2026-03-01")
        theirs.updatedAt = noon("2026-04-01")
        theirs.isOnHome = false
        context.insert(theirs)
        try context.save()

        // Records with one key meet as one (`RecordsMeet`), then the catalog has nothing to do.
        let names = [mine.copyID, theirs.copyID].compactMap { $0 }
        try RecordsMeet.join(in: context)
        #expect(try !TemplateStore(context: context).installBuiltIns())
        let copies = try context.fetch(FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == key }))
        let kept = try #require(copies.first)
        #expect(copies.count == 1)
        #expect(kept.copyID == names.min { $0.uuidString < $1.uuidString },
                "The copy with the smallest name stays, on every device alike")
        #expect(kept.homeOrder == 9)
        #expect(!kept.isOnHome)
    }

    @Test func twoDevicesHouseholdDeadlinesMeetAsOne() throws {
        // Each device has the tenancy and makes its own rental income declaration.
        func device() throws -> ModelContainer {
            let container = try makeInMemoryContainer()
            let context = container.mainContext
            try TemplateStore(context: context).installBuiltIns()
            return container
        }
        let first = try device()
        let tenancy = Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy)
        first.mainContext.insert(tenancy)
        try UnitOfWork.save(first.mainContext)
        try LaunchData.reconcileHouseholdRules(in: first.mainContext, today: CalendarDay("2026-11-10"))
        let second = try device()
        let service = DossierArchiveService(container: first, calendar: .bucharest)
        try DossierArchiveService(container: second, calendar: .bucharest).importArchive(try service.exportData(exportedAt: noon("2026-11-10")), mode: .merge)
        // The second device made its own copy before the first one's arrived.
        let key = HouseholdRules.rentalDeclarationKey
        let blueprint = HouseholdRules.rentalDeclaration
        let own = Obligation(title: blueprint.title, kind: blueprint.kind, dueDay: CalendarDay("2027-05-25"), recurrence: blueprint.recurrence, reminders: blueprint.reminders)
        own.blueprintKey = key
        second.mainContext.insert(own)
        try second.mainContext.save()
        // And each gets the other's.
        try service.importArchive(try DossierArchiveService(container: second, calendar: .bucharest).exportData(exportedAt: noon("2026-11-10")), mode: .merge)

        var kept: [UUID] = []
        for container in [first, second] {
            try LaunchData.reconcileHouseholdRules(in: container.mainContext, today: CalendarDay("2026-11-10"))
            let left = try container.mainContext.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
            #expect(left.count == 1)
            kept += left.map(\.id)
        }
        #expect(Set(kept).count == 1, "Both devices keep the same copy, so their results meet")
    }
}
