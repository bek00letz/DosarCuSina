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
        #expect(throws: TemplateStoreError.inUse(assetCount: 1)) { try store.delete(bikes) }

        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        #expect(throws: TemplateStoreError.builtInCannotBeDeleted) { try store.delete(vehicle) }
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
        #expect(examples.count == 8, "Loading twice doesn't duplicate")
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
    var succeeds: Bool
    private(set) var prompts = 0

    init(succeeds: Bool) { self.succeeds = succeeds }

    func canAuthenticate() -> Bool { true }
    func biometryType() -> LABiometryType { .faceID }

    func evaluate(localizedReason: String) async throws -> Bool {
        prompts += 1
        if succeeds { return true }
        throw LAError(.authenticationFailed)
    }
}

@MainActor
@Suite("Face ID lock")
struct BiometricVaultTests {
    @Test func unlocksPerCategoryAndRelocksWhenIdle() async {
        var clock = noon("2026-11-02")
        let authenticator = FakeAuthenticator(succeeds: true)
        let vault = BiometricVaultManager(authenticator: authenticator, now: { clock })

        #expect(vault.needsUnlock(templateKey: "documents", isSensitive: true, lockEnabled: true))
        #expect(!vault.needsUnlock(templateKey: "vehicle", isSensitive: false, lockEnabled: true))
        #expect(!vault.needsUnlock(templateKey: "documents", isSensitive: true, lockEnabled: false), "The master switch turns it off")

        #expect(await vault.unlock("documents", reason: "test"))
        #expect(vault.isUnlocked("documents"))
        #expect(!vault.isUnlocked("health"), "Each category unlocks on its own")
        #expect(await vault.unlock("documents", reason: "test"))
        #expect(authenticator.prompts == 1, "An open category doesn't ask again")

        clock = clock.addingTimeInterval(200)
        vault.noteActivity("documents")
        clock = clock.addingTimeInterval(200)
        #expect(vault.isUnlocked("documents"), "Activity keeps it open")
        clock = clock.addingTimeInterval(301)
        #expect(!vault.isUnlocked("documents"), "Idle time locks it")
    }

    @Test func failedAuthenticationKeepsItLocked() async {
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(succeeds: false))
        #expect(await !vault.unlock("health", reason: "test"))
        #expect(!vault.isUnlocked("health"))
    }

    @Test func lockAllClosesEverything() async {
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(succeeds: true))
        await vault.unlock("documents", reason: "test")
        await vault.unlock("health", reason: "test")
        vault.lockAll()
        #expect(vault.unlockedKeys.isEmpty)
    }

    @Test func masksTheMiddleOfIdentifiers() {
        #expect(BiometricVaultManager.mask("1800101990006") == "180•••••••006")
        #expect(BiometricVaultManager.mask("123") == "••••")
    }
}
