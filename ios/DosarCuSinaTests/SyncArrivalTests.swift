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

    @Test("A binder is whole once its first download has finished and no download is under way")
    func whenTheBinderIsWhole() throws {
        let container = try makeInMemoryContainer()
        let arrival = CloudArrival.of(container)
        #expect(arrival.isWhole, "A container nothing is said about has nothing on its way")
        CloudArrival.firstDownload(pending: true, in: container)
        #expect(!arrival.isWhole, "The first download hasn't finished on this phone")
        CloudArrival.follow(SyncEvent(kind: .setup, finishedAt: nil, succeeded: false), in: container)
        CloudArrival.follow(SyncEvent(kind: .setup, finishedAt: noon("2026-11-11"), succeeded: true), in: container)
        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: nil, succeeded: false), in: container)
        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: noon("2026-11-11"), succeeded: true), in: container)
        #expect(!arrival.isWhole, "Still waiting until the phone knows the first download finished")
        CloudArrival.firstDownload(pending: false, in: container)
        #expect(arrival.isWhole)
        CloudArrival.follow(SyncEvent(kind: .upload, finishedAt: nil, succeeded: false), in: container)
        #expect(arrival.isWhole, "Sending this device's changes brings nothing")
        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: nil, succeeded: false), in: container)
        #expect(!arrival.isWhole, "A later batch under way")
        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: noon("2026-11-11"), succeeded: false, problem: .offline), in: container)
        #expect(arrival.isWhole, "Nothing more is coming down for now")
    }

    @Test("Nothing of the household's goes while the binder is still arriving, and it settles once it has")
    func theDeclarationWaitsForItsTenancy() throws {
        let context = try makeContext()
        // The declaration came first; its tenancy is still on its way.
        _ = declaration(in: context)
        try context.save()
        let container = context.container
        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: nil, succeeded: false), in: container)

        #expect(try !LaunchData.reconcileHouseholdRules(in: context, today: today))
        #expect(try declarations(in: context).count == 1, "Kept while the download runs")

        let told = Told()
        let observer = NotificationCenter.default.addObserver(forName: CloudArrival.didBecomeWhole, object: container, queue: nil) { _ in told.value = true }
        defer { NotificationCenter.default.removeObserver(observer) }
        CloudArrival.follow(SyncEvent(kind: .download, finishedAt: noon("2026-11-11"), succeeded: true), in: container)
        #expect(told.value, "The steps that waited are told they can run")
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

/// Whether a notification came, kept for a test.
private final class Told: @unchecked Sendable {
    var value = false
}
