import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Locks stay on when they can't be read, "Începe din nou" keeps this device's locks, and turning
/// a lock off asks for Face ID every time. Every value is a placeholder.
@MainActor
@Suite("Locks hold")
struct LocksHoldTests {
    private let vehicle = BuiltInTemplates.Key.vehicle
    private let home = BuiltInTemplates.Key.home
    private let documents = BuiltInTemplates.Key.documents
    private let notebook = "custom.0b6c6f43-0000-4000-8000-00000000c0de"
    private let fromAnotherDevice = "custom.0b6c6f43-0000-4000-8000-0000000000aa"

    private func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "locks-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func locked(_ locks: SectionLocks, _ key: String) -> Bool {
        locks.isLocked(key, byDefault: SectionLocks.lockedByDefault.contains(key))
    }

    /// A category of one's own that arrives as iCloud writes it: this device made no choice for it.
    private func arrives(_ key: String, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(CategoryTemplate(definition: TemplateDefinition(key: key, name: "Caiet", symbol: "book", tint: .gray, sections: []), isBuiltIn: false, homeOrder: 50))
        try context.save()
    }

    private func template(_ key: String, in container: ModelContainer) throws -> CategoryTemplate {
        try #require(try PersistenceController.context(in: container).fetch(FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == key })).first)
    }

    // MARK: Locks that can't be read stay on

    @Test func aLockFileThatCantBeReadKeepsEveryLockOnAndIsNeverWrittenOver() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Dosar.store.section-locks.json")
        let unreadable = Data("{\"vehicle\": tr".utf8)
        try unreadable.write(to: file)

        let locks = SectionLocks(file: file)
        #expect(locks.needsChoosingAgain)
        for key in [notebook, documents, vehicle, home, fromAnotherDevice] {
            #expect(locked(locks, key), "Every category is locked until the locks are chosen again: \(key)")
        }

        // A change sets the unread file aside and starts a new one that remembers the wait.
        try locks.set(true, for: vehicle)
        try locks.set(false, for: home)
        #expect(locked(locks, home), "Nothing opens while the locks wait")
        let setAside = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).filter { $0.contains(".unread-") }
        #expect(setAside.count == 1)
        #expect(try Data(contentsOf: folder.appending(path: try #require(setAside.first))) == unreadable, "What couldn't be read is kept as it was")
        let reopened = SectionLocks(file: file)
        #expect(reopened.needsChoosingAgain, "Still waiting after a relaunch")
        for key in [notebook, vehicle, home] { #expect(locked(reopened, key)) }
        #expect(reopened.all[SectionLocks.waitKey] == nil, "The wait isn't a category")

        // Kept: every lock stays on, and the wait ends.
        try reopened.chooseAgain([notebook: true, vehicle: true, documents: true, home: true])
        let chosen = SectionLocks(file: file)
        #expect(!chosen.needsChoosingAgain)
        for key in [notebook, vehicle, documents, home] { #expect(locked(chosen, key)) }
        #expect(!locked(chosen, fromAnotherDevice), "A category from another device starts open again")
    }

    @Test func aLockFileThatReadsLaterIsReadAgain() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Dosar.store.section-locks.json")
        try Data("not yet".utf8).write(to: file)
        let locks = SectionLocks(file: file)
        #expect(locks.needsChoosingAgain)

        try Data("{\"vehicle\":true,\"documents\":false}".utf8).write(to: file)
        locks.readAgainIfUnread()
        #expect(!locks.needsChoosingAgain)
        #expect(locked(locks, vehicle))
        #expect(!locked(locks, documents))
        #expect(!locked(locks, notebook))
    }

    @Test func aChoiceThatCantBeKeptSaysSoAndChangesNothing() throws {
        let folder = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        let locks = SectionLocks(file: folder.appending(path: "Dosar.store.section-locks.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        #expect(throws: (any Error).self) { try locks.set(true, for: vehicle) }
        #expect(!locked(locks, vehicle), "Nothing shows as locked that isn't kept")
    }

    @Test func aStoreWhoseLocksCantBeReadOpensWithEveryCategoryLocked() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar.store")
        try Data("{".utf8).write(to: SectionLocks.file(forStoreAt: url))
        let container = try PersistenceController.makeContainer(storeURL: url)
        try TemplateStore(context: container.mainContext).installBuiltIns()
        try arrives(fromAnotherDevice, in: container)

        #expect(SectionLocks.of(container).needsChoosingAgain)
        let store = TemplateStore(context: container.mainContext)
        for category in try store.all() {
            #expect(category.isSensitive, "Every category stays locked, built-ins included: \(category.key)")
        }
        #expect(try template(fromAnotherDevice, in: container).isSensitive)
        #expect(throws: LockLowering.Needed.self) { try store.setSensitive(try template(vehicle, in: container), false) }

        try store.keepLocksAsTheyAre(lowering: try await faceIDConfirmed())
        #expect(!SectionLocks.of(container).needsChoosingAgain)
        for category in try store.all() {
            #expect(category.isSensitive, "Kept on, as the list showed it: \(category.key)")
        }
        // Then each one opens again with Face ID.
        try store.setSensitive(try template(vehicle, in: container), false, lowering: try await faceIDConfirmed())
        #expect(try !template(vehicle, in: container).isSensitive)
        try arrives(notebook, in: container)
        #expect(try !template(notebook, in: container).isSensitive, "Once chosen again, a new one from another device starts open")
    }

    @Test func locksAnOlderBuildMovedAsideKeepEveryCategoryLocked() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Dosar.store.section-locks.json")
        try Data("{\"vehicle\":true,\"home\":false,\"\(notebook)\":true}".utf8)
            .write(to: folder.appending(path: "unreadable-20261101T120000-Dosar.store.section-locks.json"))

        let locks = SectionLocks(file: file)
        #expect(locks.needsChoosingAgain)
        for key in [vehicle, home, notebook, documents, fromAnotherDevice] {
            #expect(locked(locks, key), "Every category is locked until chosen again: \(key)")
        }
    }

    // MARK: "Începe din nou" keeps this device's locks

    @Test func startingFreshKeepsThisDevicesLocks() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar.store")
        do {
            let container = try PersistenceController.makeContainer(storeURL: url)
            let store = TemplateStore(context: container.mainContext)
            try store.installBuiltIns()
            try store.setSensitive(try template(vehicle, in: container), true)
            try store.setSensitive(try template(documents, in: container), false, lowering: try await faceIDConfirmed())
            let notebook = try store.createCustom(name: "Caiet", symbol: "book", tint: .gray, sections: [], isSensitive: true)
            #expect(notebook.isSensitive)
        }
        let choices = SectionLocks.of(try PersistenceController.makeContainer(storeURL: url)).all
        let made = try #require(choices.keys.first(where: { $0.hasPrefix("custom.") }))

        PersistenceController.moveStoreAside(at: url)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("unreadable-") && $0.hasSuffix("Dosar.store") }, "The store went aside")
        #expect(exists(SectionLocks.file(forStoreAt: url)), "The locks stayed")

        // A fresh binder, then the person's own categories coming back from iCloud.
        let fresh = try PersistenceController.makeContainer(storeURL: url)
        try TemplateStore(context: fresh.mainContext).installBuiltIns()
        try arrives(made, in: fresh)
        #expect(try template(vehicle, in: fresh).isSensitive)
        #expect(try !template(documents, in: fresh).isSensitive)
        #expect(try template(made, in: fresh).isSensitive, "A category of one's own locked here comes back locked")
    }

    // MARK: Turning a lock off asks every time

    @Test func turningALockOffAsksEveryTimeEvenWithTheSessionOpen() async throws {
        let authenticator = FakeAuthenticator(.succeed)
        let vault = BiometricVaultManager(authenticator: authenticator, appLockEnabled: { true }, observesAppLifecycle: false)
        #expect(await vault.unlock(reason: "Test") == .success)
        #expect(vault.isSessionUnlocked)
        #expect(await vault.confirmLowering(reason: "Test") != nil)
        #expect(await vault.confirmLowering(reason: "Test") != nil)
        #expect(authenticator.prompts == 3, "Asked each time, the session open or not")
        #expect(vault.isSessionUnlocked, "The session stays as it was")

        authenticator.outcome = .cancel
        #expect(await vault.confirmLowering(reason: "Test") == nil)
        authenticator.outcome = .fail
        #expect(await vault.confirmLowering(reason: "Test") == nil)
        #expect(vault.isSessionUnlocked)
    }

    @Test func aSectionLockGoesOffOnlyWithFaceIDAndOnWithout() async throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let acte = try #require(try store.template(forKey: documents))
        #expect(throws: LockLowering.Needed.self) { try store.setSensitive(acte, false) }
        #expect(acte.isSensitive)
        #expect(throws: LockLowering.Needed.self) { try acte.setLock(false) }
        #expect(throws: LockLowering.Needed.self) { try store.update(acte, with: TemplateDefinition(key: documents, name: acte.name, symbol: acte.symbol, tint: .gray, isSensitiveByDefault: false, sections: [])) }
        #expect(acte.isSensitive, "Every way of turning it off asks")

        try store.setSensitive(acte, false, lowering: try await faceIDConfirmed())
        #expect(!acte.isSensitive)
        try store.setSensitive(acte, true)
        #expect(acte.isSensitive, "Turning one on needs nothing")
    }

    @Test func theAppLockGoesOffOnlyWithFaceID() async throws {
        let preferences = AppPreferences(defaults: try #require(UserDefaults(suiteName: "LocksHoldTests.\(UUID().uuidString)")))
        try preferences.setAppLock(true)
        #expect(preferences.appLockEnabled)
        #expect(throws: LockLowering.Needed.self) { try preferences.setAppLock(false) }
        #expect(preferences.appLockEnabled)
        try preferences.setAppLock(false, lowering: try await faceIDConfirmed())
        #expect(!preferences.appLockEnabled)
        try preferences.setAppLock(false)
    }
}
