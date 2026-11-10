import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Whose change a step is decides the change times it gives: the person's edits get the
/// step's clock, what the app does by itself (the catalog, the repair list, the household's
/// own deadlines) gives none, so a backup's copy with the person's change is never taken for
/// the older one. And every import has the repair list look again, and launch logs what fails.
@MainActor
@Suite("Whose change it is")
struct ChangeOriginTests {
    let long = noon("2025-06-01")
    let today = noon("2026-11-10")
    private struct SaveFailed: Error {}

    private func repairs() throws -> DataRepairCenter {
        DataRepairCenter(ledger: DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "change-origin-\(UUID().uuidString)"))))
    }

    /// A phone: its own container, with the built-in categories installed as launch does.
    private func phone() throws -> (ModelContainer, ModelContext) {
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        try TemplateStore(context: context).installBuiltIns()
        return (container, context)
    }

    // MARK: The person's step

    @Test("The person's edit gets the step's clock, and writing the same again changes nothing")
    func aPersonsEditStampsOnce() throws {
        let context = try makeContext()
        let vehicles = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-01") })
            .create(name: "VW Golf 2018", template: vehicles, values: FieldValues())
        #expect(car.updatedAt == noon("2026-11-01"), "What a step makes has the time it was made, by the step's clock")

        try AssetActions(context: context, calendar: .bucharest, now: { today }).update(car, name: "VW Golf 2018 alb", values: car.values, notes: nil)
        #expect(car.updatedAt == today)

        try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-12-01") }).update(car, name: car.name, values: car.values, notes: car.notes)
        #expect(car.updatedAt == today, "Saving it as it was is no change")
    }

    @Test("A step's clock is the change time it gives, opened or joined")
    func aStepsClockIsItsTime() throws {
        let records = try ChangeTimesTests.Records.make(at: long)
        records.visit.note = "Corectat."
        try UnitOfWork.save(records.context, now: today)
        #expect(records.visit.updatedAt == today)

        // A unit opened without a clock takes the first a step inside it gives.
        let later = noon("2026-11-20")
        try UnitOfWork.perform(in: records.context) {
            records.item.notes = "Schimbat."
            try UnitOfWork.save(records.context, now: later)
        }
        #expect(records.item.updatedAt == later)
    }

    // MARK: The app's own step

    @Test("The app's own step changes no change time; what it makes has the time it was made")
    func anAppMadeStepDoesntStamp() throws {
        let records = try ChangeTimesTests.Records.make(at: long)
        let made = HistoryEntry(kind: .note, title: "Notă", occurredAt: today)
        try UnitOfWork.perform(in: records.context, origin: .app, now: today) {
            records.visit.note = "Scris altfel."
            records.page.imageData = Data([5])
            records.context.insert(made)
            made.asset = records.car
        }
        #expect(records.visit.updatedAt == long)
        #expect(records.document.updatedAt == long, "A page the app changed is no change of the document either")
        #expect(made.updatedAt == today)
    }

    @Test("An app-made step inside the person's is part of the person's step")
    func anAppMadeStepJoinsThePersons() throws {
        let records = try ChangeTimesTests.Records.make(at: long)
        try UnitOfWork.perform(in: records.context, now: today) {
            try UnitOfWork.perform(in: records.context, origin: .app) { records.visit.note = "Din editare." }
        }
        #expect(records.visit.updatedAt == today)
    }

    // MARK: Built-in categories

    @Test("A built-in category the catalog installs has no change time")
    func installedBuiltInsHaveNoChange() throws {
        let (_, context) = try phone()
        for template in try TemplateStore(context: context).all() where template.isBuiltIn {
            #expect(template.updatedAt == ChangeTime.unknown, "\(template.key)")
        }
    }

    @Test("A catalog upgrade doesn't make a built-in category newer")
    func aCatalogUpgradeIsNoChange() throws {
        let (_, context) = try phone()
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let version = documents.builtInVersion
        // Installed by an earlier catalog, its order chosen long ago.
        documents.builtInVersion = version - 1
        documents.summary = "Definiția de altădată"
        documents.updatedAt = long
        try context.save()

        #expect(try TemplateStore(context: context).installBuiltIns())
        #expect(documents.builtInVersion == version, "Upgraded")
        #expect(documents.updatedAt == long, "Its change time is the person's last choice, not the update")
    }

    @Test("Only the person's choices are a change of a built-in category")
    func onlyThePersonsChoicesCount() throws {
        let (_, context) = try phone()
        let store = TemplateStore(context: context)
        let pets = try #require(try store.template(forKey: BuiltInTemplates.Key.pet))
        pets.summary = "Altă descriere"
        try UnitOfWork.save(context, now: today)
        #expect(pets.updatedAt == ChangeTime.unknown, "What the catalog defines is no choice of the person's")

        try store.setOnHome(pets, !pets.isOnHome)
        #expect(pets.updatedAt > ChangeTime.unknown)
    }

    @Test("After an app update, the order chosen on another phone comes in with Adaugă")
    func aBackupsOrderWinsOverAnUpgrade() throws {
        // The other phone: the person moved the first category to the end.
        let (otherContainer, otherContext) = try phone()
        let otherStore = TemplateStore(context: otherContext)
        let moved = try #require(try otherStore.all().first)
        try otherStore.move(fromOffsets: IndexSet(integer: 0), toOffset: try otherStore.all().count)
        let order = moved.homeOrder
        let backup = try DossierArchiveService(container: otherContainer, calendar: .bucharest).exportData()

        // This phone: every built-in upgraded by an app update.
        let (container, context) = try phone()
        for template in try TemplateStore(context: context).all() where template.isBuiltIn { template.builtInVersion -= 1 }
        try context.save()
        #expect(try TemplateStore(context: context).installBuiltIns())

        var service = DossierArchiveService(container: container, calendar: .bucharest)
        service.repairs = try repairs()
        try service.importArchive(backup, mode: .merge)

        let here = try #require(try TemplateStore(context: PersistenceController.context(in: container)).template(forKey: moved.key))
        #expect(here.homeOrder == order, "The other phone's choice is newer than an upgrade")
    }

    // MARK: Imports and launch

    /// A backup with a firm kept twice: a repair the list offers.
    private func backupWithAFirmTwice() throws -> Data {
        let (container, context) = try phone()
        let actions = ProviderActions(context: context)
        try actions.create(name: "Service Exemplu SRL", trades: [.mechanic])
        try actions.create(name: "Service Exemplu SRL", trades: [.mechanic])
        return try DossierArchiveService(container: container, calendar: .bucharest).exportData()
    }

    @Test("Every import has the repair list look again", arguments: [ArchiveImportMode.merge, .replace])
    func anImportRunsRepairs(mode: ArchiveImportMode) throws {
        let backup = try backupWithAFirmTwice()
        let center = try repairs()
        var service = DossierArchiveService(container: try makeInMemoryContainer(), calendar: .bucharest)
        service.repairs = center
        try service.importArchive(backup, mode: mode)
        #expect(center.pending.contains { $0.step == .duplicateProviders })
    }

    @Test("An import away from the main thread has the repair list look again too")
    func anImportAwayRunsRepairs() async throws {
        let package = try DossierArchiveReader.read(try backupWithAFirmTwice())
        let center = try repairs()
        var service = DossierArchiveService(container: try makeInMemoryContainer(), calendar: .bucharest)
        service.repairs = center
        try await service.importPackageAway(package, mode: .merge)
        #expect(center.pending.contains { $0.step == .duplicateProviders })
    }

    @Test("A launch step that fails is logged, and the next ones still run")
    func aFailedLaunchStepIsLogged() throws {
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        try context.save()

        UnitOfWork.failNextCommitForTesting(SaveFailed(), in: context)
        #expect(LaunchData.prepare(in: context, today: CalendarDay("2026-11-10"), repairs: try repairs()) == [.builtInCategories])
        #expect(try context.fetchCount(FetchDescriptor<CategoryTemplate>()) == 0, "Taken back whole")
        let key = HouseholdRules.rentalDeclarationKey
        #expect(try context.fetchCount(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key })) == 1,
                "The household's own deadlines still made")

        #expect(LaunchData.prepare(in: context, today: CalendarDay("2026-11-10"), repairs: try repairs()).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<CategoryTemplate>()) == BuiltInTemplates.all.count, "Tried again at the next launch")
    }
}
