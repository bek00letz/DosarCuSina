import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What launch does to the household's data saves through `UnitOfWork`: kept when it
/// works, taken back whole when it doesn't, and nothing left unsaved on the context.
@MainActor
@Suite("Launch data")
struct LaunchDataTests {
    private struct SaveFailed: Error {}

    private func repairs() throws -> DataRepairCenter {
        DataRepairCenter(ledger: DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "launch-\(UUID().uuidString)"))))
    }

    /// A tenancy written by an earlier version without the household's declaration.
    private func tenancyWithoutDeclaration(in context: ModelContext) throws {
        context.insert(Asset(name: "Apartament Exemplu – chiriaș", templateKey: BuiltInTemplates.Key.tenancy))
        try context.save()
    }

    private func declarations(in container: ModelContainer) throws -> Int {
        let key = HouseholdRules.rentalDeclarationKey
        return try ModelContext(container).fetchCount(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
    }

    @Test("Launch installs the categories and saves the household's own deadlines")
    func launchSaves() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try tenancyWithoutDeclaration(in: context)

        LaunchData.prepare(in: context, today: CalendarDay("2026-11-09"), repairs: try repairs())

        #expect(!context.hasChanges, "Nothing is left unsaved")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<CategoryTemplate>()) == BuiltInTemplates.all.count)
        #expect(try declarations(in: container) == 1, "Saved, so another context sees it")

        LaunchData.prepare(in: context, today: CalendarDay("2026-11-10"), repairs: try repairs())
        #expect(try declarations(in: container) == 1, "A second launch changes nothing")
    }

    @Test("A save that fails at launch takes back only its own step")
    func failedSaveRollsBack() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        try tenancyWithoutDeclaration(in: context)

        UnitOfWork.failNextCommitForTesting(SaveFailed(), in: context)
        #expect(throws: SaveFailed.self) { try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-09")) }
        #expect(!context.hasChanges)
        #expect(try declarations(in: container) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Asset>()) == 1, "The tenancy stays")

        #expect(try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay("2026-11-09")))
        #expect(try declarations(in: container) == 1, "The next launch makes it")
    }
}
