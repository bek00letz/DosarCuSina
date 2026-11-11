import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What the app does by itself on what is missing waits for a binder still arriving from iCloud
/// (`CloudArrival`), and a household deadline with something of the person's on it stays.
@MainActor
@Suite("A binder arriving from iCloud")
struct SyncArrivalTests {
    private let today = CalendarDay("2026-11-11")

    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func declarations(in context: ModelContext) throws -> [Obligation] {
        let key = HouseholdRules.rentalDeclarationKey
        return try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
    }

    private func declaration(in context: ModelContext) -> Obligation {
        let blueprint = HouseholdRules.rentalDeclaration
        let obligation = Obligation(title: blueprint.title, kind: blueprint.kind, dueDay: CalendarDay("2027-05-25"),
                                    recurrence: blueprint.recurrence, reminders: blueprint.reminders)
        obligation.blueprintKey = blueprint.key
        context.insert(obligation)
        return obligation
    }

    // MARK: A binder still arriving

    @Test("A store that syncs is whole only once an import has finished and none is under way")
    func whenTheBinderIsWhole() {
        let arrival = CloudArrival(syncs: true)
        #expect(!arrival.isWhole, "Nothing has come yet")
        let setup = UUID(), first = UUID(), second = UUID()
        arrival.follow(event: setup, stage: .settingUp, hasEnded: false, succeeded: false)
        #expect(!arrival.follow(event: setup, stage: .settingUp, hasEnded: true, succeeded: true))
        #expect(!arrival.isWhole, "Setting up brings nothing")
        arrival.follow(event: first, stage: .importing, hasEnded: false, succeeded: false)
        #expect(!arrival.follow(event: first, stage: .importing, hasEnded: true, succeeded: false), "A failed import may have stopped half-way")
        #expect(!arrival.isWhole)
        arrival.follow(event: second, stage: .importing, hasEnded: false, succeeded: false)
        #expect(arrival.follow(event: second, stage: .importing, hasEnded: true, succeeded: true), "The steps that waited run now")
        #expect(arrival.isWhole)
        arrival.follow(event: UUID(), stage: .other, hasEnded: false, succeeded: false)
        #expect(arrival.isWhole, "Sending this device's changes brings nothing")
        arrival.follow(event: first, stage: .importing, hasEnded: false, succeeded: false)
        #expect(!arrival.isWhole, "A later import under way")
        #expect(CloudArrival(syncs: false).isWhole, "A store that doesn't sync is always whole")
    }

    @Test("Nothing of the household's goes while the binder is still arriving")
    func theDeclarationWaitsForItsTenancy() throws {
        let context = try makeContext()
        // The declaration came first; its tenancy is still on its way.
        _ = declaration(in: context)
        try context.save()
        let arrival = CloudArrival.of(context.container)
        let importing = UUID()
        arrival.follow(event: importing, stage: .importing, hasEnded: false, succeeded: false)

        #expect(try !LaunchData.reconcileHouseholdRules(in: context, today: today))
        #expect(try declarations(in: context).count == 1, "Kept while the import runs")

        arrival.follow(event: importing, stage: .importing, hasEnded: true, succeeded: true)
        #expect(try LaunchData.reconcileHouseholdRules(in: context, today: today))
        #expect(try declarations(in: context).isEmpty, "Once all of it has come, a declaration nobody used goes with no tenancy")
    }

    @Test("A declaration with something of the person's on it stays when the last tenancy goes")
    func aFiledDeclarationStays() throws {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let tenancy = try actions.create(name: "Apartament Exemplu – chiriaș", template: try template(BuiltInTemplates.Key.tenancy, in: context), values: FieldValues())
        let filed = try #require(try declarations(in: context).first)
        _ = try ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-05-20") }).complete(filed)

        try actions.delete(tenancy)
        let left = try declarations(in: context)
        #expect(left.count == 1, "Its completion is the person's record")
        #expect(left.first?.historyEntries?.count == 1)
    }
}
