import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Obligation and asset actions")
struct ActionsTests {
    let calendar = Calendar.bucharest

    private func car(in context: ModelContext, today: String = "2026-11-02") throws -> (Asset, AssetActions) {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let actions = AssetActions(context: context, calendar: calendar, now: { noon(today) })
        var values = FieldValues()
        values["vehicle.plate"] = .text("B-123-ABC")
        values["vehicle.year"] = .number(2018)
        values["vehicle.odometer"] = .number(100_000)
        let asset = try actions.create(name: "Mașina de test", template: template, values: values)
        return (asset, actions)
    }

    @Test func completingARepeatingObligationKeepsHistoryAndMovesTheDate() throws {
        let context = try makeContext()
        let (asset, _) = try car(in: context)
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        let rca = try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-10"), for: asset,
                                     recurrence: .interval(.years(1), anchor: .dueDate))

        let entry = try actions.complete(rca, cost: Money(1_200)).value

        #expect(rca.status == .active)
        #expect(rca.dueDay == CalendarDay("2027-11-10"))
        #expect(rca.history.count == 1)
        #expect(entry.totalCost == Money(1_200))
        #expect(entry.cycleDueDay == CalendarDay("2026-11-10"))
        #expect(entry.kind == .payment)
        #expect(entry.asset?.id == asset.id, "The completion lands in the asset's history")
        #expect(asset.timeline.map(\.id) == [entry.id])
        #expect(try context.fetchCount(FetchDescriptor<Obligation>()) == 1, "Completing never copies the obligation")
    }

    @Test func completingAOneOffClosesIt() throws {
        let context = try makeContext()
        let (asset, _) = try car(in: context)
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        let kit = try actions.create(title: "Trusă", kind: .legal, dueDay: CalendarDay("2026-12-01"), for: asset)
        try actions.complete(kit)
        #expect(kit.status == .done)
        #expect(throws: ObligationActionError.notActive) { try actions.complete(kit) }
    }

    @Test func undoRestoresTheObligationExactly() throws {
        let context = try makeContext()
        let (asset, _) = try car(in: context)
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        let itp = try actions.create(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-11-05"), for: asset, recurrence: .legal(.vehicleITP))
        let first = try actions.complete(itp)
        let second = try actions.complete(itp)

        #expect(throws: UndoError.changedSince, "The first step's deadline changed again since") { try first.receipt.undo() }
        try second.receipt.undo()
        try first.receipt.undo()
        #expect(throws: UndoError.unavailable) { try first.receipt.undo() }

        #expect(itp.dueDay == CalendarDay("2026-11-05"))
        #expect(itp.status == .active)
        #expect(itp.history.isEmpty)
    }

    @Test func undoReopensAOneOff() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        let task = try actions.create(title: "Cazier", kind: .renewal, dueDay: CalendarDay("2026-11-20"), for: nil)
        try actions.complete(task).receipt.undo()
        #expect(task.status == .active)
    }

    @Test func snoozeHidesUntilTheChosenDay() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        let item = try actions.create(title: "Udat", kind: .routine, dueDay: CalendarDay("2026-11-02"), for: nil)
        try actions.snooze(item, days: 3)
        #expect(item.snoozedUntil == CalendarDay("2026-11-05"))
        #expect(item.isSnoozed(at: noon("2026-11-04")))
        #expect(!item.isSnoozed(at: noon("2026-11-05")))
        try actions.complete(item)
        #expect(item.snoozedUntil == nil)
    }

    @Test func blueprintsThatAskForADateNeedOne() throws {
        let context = try makeContext()
        let (asset, _) = try car(in: context)
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let itp = try #require(template.blueprints.first { $0.key == "vehicle.itp" })
        #expect(throws: ObligationActionError.missingFirstDueDate(blueprintKey: "vehicle.itp")) {
            try actions.create(from: itp, for: asset)
        }
        let created = try actions.create(from: itp, for: asset, firstDue: CalendarDay("2027-01-15"))
        #expect(created.blueprintKey == "vehicle.itp")
        #expect(created.kind == .legal)
    }

    @Test func counterObligationsTrackTheReadingTakenWhenDone() throws {
        let context = try makeContext()
        let (asset, _) = try car(in: context)
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        let service = try actions.create(title: "Revizie", kind: .maintenance, dueDay: CalendarDay("2026-11-02"), for: asset,
                                         recurrence: .metric(every: 15_000, unit: .kilometres, fallback: .years(1)))
        try actions.complete(service, metricReading: 101_000)
        #expect(service.dueMetric == 116_000)
        #expect(asset.value("vehicle.odometer") == .number(101_000), "The reading updates the odometer")
    }

    @Test func creatingAnAssetCreatesTheChosenObligationsInOneGo() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let actions = AssetActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        var values = FieldValues()
        values["document.type"] = .text("Pașaport")
        values["document.expiry"] = .date(CalendarDay("2028-04-01"))
        let planned = actions.plannedObligations(for: template, values: values)
        #expect(planned.first?.firstDue == CalendarDay("2028-04-01"))

        let passport = try actions.create(name: "Pașaport", template: template, values: values, obligations: planned)
        #expect(passport.activeObligations.count == 1)

        // Changing the expiry moves the renewal with it.
        values["document.expiry"] = .date(CalendarDay("2033-04-01"))
        try actions.update(passport, name: "Pașaport", values: values, notes: nil)
        #expect(passport.activeObligations.first?.dueDay == CalendarDay("2033-04-01"))
    }

    @Test func weightReadingsKeepTheLatestValueOnThePet() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.pet))
        let actions = AssetActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        var values = FieldValues()
        values["pet.weight"] = .number(4.2)
        let cat = try actions.create(name: "Pisica de test", template: template, values: values)
        try actions.recordMeasurement(on: cat, kind: .bodyWeight, value: 4.0, unit: .kilograms, at: noon("2026-06-01"))
        #expect(cat.value("pet.weight") == .number(4.2), "An older reading doesn't replace a newer one")
        try actions.recordMeasurement(on: cat, kind: .bodyWeight, value: 4.6, unit: .kilograms, at: noon("2026-11-02"))
        #expect(cat.value("pet.weight") == .number(4.6))
    }

    /// Changed on purpose: the buttons used to complete whatever cycle was current.
    /// They now carry the cycle they were about, go through the one way in for
    /// outside actions, and an old one changes nothing.
    @Test func notificationButtonsUseTheSameEngineForTheirOwnCycle() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let actions = ObligationActions(context: context)
        let item = try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay(Date()), for: nil,
                                      recurrence: .interval(.years(1), anchor: .dueDate))
        let before = item.dueDay
        let navigator = AppNavigator()
        let center = FakeNotificationCenter(status: .authorized)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let coordinator = SideEffectsCoordinator(container: container, notificationClient: center, widgetWriter: WidgetSnapshotWriter(directory: folder))
        let failures = OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)")
        let responder = NotificationResponder(containerProvider: { container }, navigator: navigator, sideEffects: { _ in coordinator }, failures: failures)

        await responder.handle(action: ReminderActions.complete, payload: ReminderPayload(obligationId: item.id, cycle: before))
        #expect(item.history.count == 1)
        #expect(item.dueDay == RecurrenceEngine.add(.years(1), to: before))
        #expect(coordinator.lastReconciledAt != nil, "Reminders are planned again after the button")

        await responder.handle(action: ReminderActions.complete, payload: ReminderPayload(obligationId: item.id, cycle: before))
        #expect(item.history.count == 1, "A second tap for the same cycle changes nothing")

        await responder.handle(action: ReminderActions.snooze, payload: ReminderPayload(obligationId: item.id, cycle: before))
        #expect(item.snoozedUntil == nil, "Nor does a snooze for a closed cycle")
        await responder.handle(action: ReminderActions.snooze, payload: ReminderPayload(obligationId: item.id, cycle: item.dueDay))
        #expect(item.snoozedUntil != nil)

        await responder.handle(action: "com.apple.UNNotificationDefaultActionIdentifier",
                               payload: ReminderPayload(obligationId: item.id, cycle: nil, deepLink: DeepLink.url(for: .obligation(item.id))))
        #expect(navigator.pendingRoute == .obligation(item.id))
        #expect(failures.all().isEmpty)
    }
}
