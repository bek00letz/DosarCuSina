import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Template store")
struct TemplateStoreTests {
    @Test func installsOnceAndKeepsPreferencesOnUpgrade() throws {
        let context = ModelContext(try makeInMemoryContainer())
        let store = TemplateStore(context: context)
        #expect(try store.installBuiltIns())
        #expect(try !store.installBuiltIns(), "A second install changes nothing")
        #expect(try store.all().count == BuiltInTemplates.all.count)

        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        try store.setOnHome(vehicle, false)
        try store.setSensitive(vehicle, true)

        var upgraded = BuiltInTemplates.vehicle
        upgraded.version += 1
        upgraded.name = "Vehicule"
        #expect(try store.installBuiltIns(catalog: [upgraded]))
        #expect(vehicle.name == "Vehicule")
        #expect(vehicle.builtInVersion == upgraded.version)
        #expect(vehicle.isOnHome == false)
        #expect(vehicle.isSensitive == true)
    }

    @Test func removesDuplicateBuiltInsFromSyncMerges() throws {
        let context = ModelContext(try makeInMemoryContainer())
        context.insert(CategoryTemplate(definition: BuiltInTemplates.home, isBuiltIn: true, homeOrder: 0))
        context.insert(CategoryTemplate(definition: BuiltInTemplates.home, isBuiltIn: true, homeOrder: 1))
        try context.save()
        try TemplateStore(context: context).installBuiltIns()
        let homeKey = BuiltInTemplates.Key.home
        #expect(try context.fetchCount(FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.key == homeKey })) == 1)
    }

    @Test func customCategoriesAreRealTemplates() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let bikes = try store.createCustom(name: "Scule", symbol: "wrench.and.screwdriver.fill", tint: .orange, sections: [
            FieldSection(key: "tools", title: "Unealtă", fields: [FieldDefinition(key: "tools.serial", label: "Serie", type: .text, role: .identifier)]),
        ])
        #expect(bikes.key.hasPrefix(TemplateDefinition.customKeyPrefix))
        #expect(bikes.homeOrder == BuiltInTemplates.all.count)

        let drill = Asset(name: "Bormașină", templateKey: bikes.key)
        context.insert(drill)
        try context.save()
        #expect(throws: TemplateStoreError.inUse(assetCount: 1)) { _ = try store.delete(bikes) }

        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        #expect(throws: TemplateStoreError.builtInCannotBeDeleted) { _ = try store.delete(vehicle) }
    }

    @Test func reorderingFollowsListMoves() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let firstKey = try store.all()[0].key
        try store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(try store.all()[2].key == firstKey)
        #expect(try store.all().map(\.homeOrder) == Array(0..<BuiltInTemplates.all.count))
    }

    @Test func mainstaysAreSensitiveOnlyWhereItMatters() {
        let sensitive = Set(BuiltInTemplates.all.filter(\.isSensitiveByDefault).map(\.key))
        #expect(sensitive == [BuiltInTemplates.Key.documents, BuiltInTemplates.Key.health])
        for template in [BuiltInTemplates.vehicle, BuiltInTemplates.home, BuiltInTemplates.documents, BuiltInTemplates.pet] {
            #expect(template.heroStyle != .standard, "\(template.key) has a purpose-built hero")
            #expect(!template.allFields.filter(\.isEssential).isEmpty, "\(template.key) has a quick add")
        }
    }
}

@MainActor
@Suite("Example household")
struct ExampleDataTests {
    @Test func examplesAreTaggedAndRemovedTogether() throws {
        let context = try makeContext()
        let real = Asset(name: "Mașina mea", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(real)
        try context.save()

        let service = ExampleDataService(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        try service.loadExamples()
        try service.loadExamples()
        let examples = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample }))
        #expect(examples.count == 12, "Loading twice doesn't duplicate")
        let obligations = try context.fetch(FetchDescriptor<Obligation>())
        #expect(!obligations.isEmpty)
        #expect(obligations.allSatisfy { $0.isExample })

        let snapshots = try ObligationSnapshot.fetchAll(in: context, calendar: .bucharest)
        #expect(ReminderPlanner.plan(snapshots, now: noon("2026-11-02"), calendar: .bucharest).isEmpty, "Examples never send real reminders")
        let digest = AttentionModel.digest(snapshots, now: noon("2026-11-02"), calendar: .bucharest)
        #expect(!digest.now.isEmpty, "Examples show what the Radar does")
        #expect(digest.now.contains { $0.urgency == .overdue })

        try service.removeExamples()
        #expect(try context.fetch(FetchDescriptor<Asset>()).map(\.name) == ["Mașina mea"])
        #expect(try context.fetchCount(FetchDescriptor<Obligation>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MeasurementLog>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HistoryEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ServiceItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Provider>()) == 0)
    }

    @Test func exampleCarHasAMeaningfulOdometerHistory() throws {
        let context = try makeContext()
        try ExampleDataService(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).loadExamples()
        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.templateKey == BuiltInTemplates.Key.vehicle })
        #expect(car.value("vehicle.odometer") == .number(142_500), "Older readings don't overwrite the current value")
        #expect((car.measurements ?? []).count == 3)
    }
}

/// Answers Face ID prompts the way a test tells it to.
final class FakeAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    enum Outcome { case succeed, fail, cancel }

    var outcome: Outcome
    var delay: Duration = .zero
    private let lock = NSLock()
    private var _prompts = 0
    var prompts: Int { lock.withLock { _prompts } }

    init(_ outcome: Outcome) { self.outcome = outcome }

    func biometryType() -> LABiometryType { .faceID }

    func evaluate(localizedReason: String) async throws -> Bool {
        lock.withLock { _prompts += 1 }
        if delay > .zero { try? await Task.sleep(for: delay) }
        switch outcome {
        case .succeed: return true
        case .fail: throw LAError(.authenticationFailed)
        case .cancel: throw LAError(.userCancel)
        }
    }
}

@MainActor
@Suite("Face ID locks")
struct BiometricVaultTests {
    private func vault(_ authenticator: FakeAuthenticator, appLock: Bool = false, clock: @escaping () -> Date = { Date() }) -> BiometricVaultManager {
        BiometricVaultManager(authenticator: authenticator, now: clock, appLockEnabled: { appLock }, observesAppLifecycle: false)
    }

    @Test func sectionLocksWorkWithOrWithoutTheAppLock() {
        let withoutAppLock = vault(FakeAuthenticator(.succeed), appLock: false)
        #expect(!withoutAppLock.isAppLocked)
        #expect(withoutAppLock.isLocked(sectionIsSensitive: true))
        #expect(!withoutAppLock.isLocked(sectionIsSensitive: false))

        let withAppLock = vault(FakeAuthenticator(.succeed), appLock: true)
        #expect(withAppLock.isAppLocked)
        #expect(withAppLock.isLocked(sectionIsSensitive: true))
    }

    @Test func oneAuthenticationOpensAppAndSections() async {
        let authenticator = FakeAuthenticator(.succeed)
        let manager = vault(authenticator, appLock: true)
        #expect(await manager.unlock(reason: "test") == .success)
        #expect(!manager.isAppLocked)
        #expect(!manager.isLocked(sectionIsSensitive: true), "No second prompt for a sensitive section")
        #expect(await manager.unlock(reason: "test") == .success)
        #expect(authenticator.prompts == 1)
    }

    @Test func failingOrCancellingOnlyKeepsTheSectionClosed() async {
        let authenticator = FakeAuthenticator(.fail)
        let manager = vault(authenticator)
        #expect(await manager.unlock(reason: "test") == .failed)
        #expect(manager.isLocked(sectionIsSensitive: true))
        #expect(!manager.isAppLocked, "A failed section unlock never locks the whole app")
        #expect(!manager.isAuthenticating)

        authenticator.outcome = .cancel
        #expect(await manager.unlock(reason: "test") == .cancelled)
        #expect(manager.isLocked(sectionIsSensitive: true))

        authenticator.outcome = .succeed
        #expect(await manager.unlock(reason: "test") == .success, "The person can retry")
        #expect(!manager.isLocked(sectionIsSensitive: true))
    }

    @Test func overlappingRequestsShareOnePrompt() async {
        let authenticator = FakeAuthenticator(.succeed)
        authenticator.delay = .milliseconds(100)
        let manager = vault(authenticator, appLock: true)
        async let first = manager.unlock(reason: "app")
        async let second = manager.unlock(reason: "section")
        let results = await [first, second]
        #expect(results == [.success, .success])
        #expect(authenticator.prompts == 1)
    }

    @Test func relocksOnlyAfterALongerBackgroundTrip() async {
        var clock = noon("2026-11-02")
        let manager = vault(FakeAuthenticator(.succeed), appLock: true, clock: { clock })
        await manager.unlock(reason: "test")

        manager.appDidEnterBackground()
        clock = clock.addingTimeInterval(BiometricVaultManager.relockAfterBackground - 5)
        manager.appWillEnterForeground()
        #expect(manager.isSessionUnlocked, "A quick switch to another app keeps it open")

        manager.appDidEnterBackground()
        clock = clock.addingTimeInterval(BiometricVaultManager.relockAfterBackground + 5)
        manager.appWillEnterForeground()
        #expect(!manager.isSessionUnlocked)
        #expect(manager.isAppLocked)
    }

    @Test func lockClosesTheSession() async {
        let manager = vault(FakeAuthenticator(.succeed))
        await manager.unlock(reason: "test")
        manager.lock()
        #expect(manager.isLocked(sectionIsSensitive: true))
    }

    @Test func masksTheMiddleOfIdentifiers() {
        #expect(BiometricVaultManager.mask("1800101990006") == "180•••••••006")
        #expect(BiometricVaultManager.mask("123") == "••••")
    }
}
