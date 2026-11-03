import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// "Done" and "amână" from outside the app: reminder buttons, widgets, Siri and
/// Shortcuts all go through `IntentEngine`, act only on the cycle the person saw,
/// and end with reminders and the widget planned again.
@MainActor
@Suite("Actions from outside the app")
struct OutsideActionsTests {
    let calendar = Calendar.bucharest

    private struct Household {
        let container: ModelContainer
        let rent: Obligation
        let center: FakeNotificationCenter
        let coordinator: SideEffectsCoordinator
        let failures: OutsideActionFailures
        let folder: URL
    }

    /// Rent due 5 November, monthly, already done once in the app: now due 5 December.
    private func household(now: Date) async throws -> Household {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let actions = ObligationActions(context: context, calendar: calendar, now: { now })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-11-05"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate))
        try actions.complete(rent)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let center = FakeNotificationCenter(status: .authorized)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        let coordinator = SideEffectsCoordinator(
            container: container,
            notificationClient: center,
            widgetWriter: WidgetSnapshotWriter(directory: folder),
            preferences: AppPreferences(defaults: defaults),
            calendar: calendar,
            now: { now }
        )
        return Household(container: container, rent: rent, center: center, coordinator: coordinator,
                         failures: OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)"), folder: folder)
    }

    /// Sends one request through the real entry point of `surface`.
    private func send(_ request: OutsideRequest, to home: Household, now: Date) async {
        switch request.surface {
        case .notification:
            let responder = NotificationResponder(containerProvider: { home.container }, navigator: AppNavigator(),
                                                  sideEffects: { _ in home.coordinator }, failures: home.failures)
            let action = request.action == .complete ? ReminderActions.complete : ReminderActions.snooze
            await responder.handle(action: action, payload: ReminderPayload(obligationId: request.obligationId, cycle: request.cycle), calendar: calendar)
        case .widget:
            let queue = WidgetCompletionQueue(fileURL: home.folder.appending(path: WidgetCompletionQueue.fileName))
            queue.enqueue(WidgetCompletion(obligationId: request.obligationId, dueDay: request.cycle?.isoString ?? "", requestedAt: now))
            IntentEngine.applyQueuedWidgetCompletions(queue: queue, in: home.container.mainContext, failures: home.failures, calendar: calendar)
            #expect(queue.pending().isEmpty, "A stale tap leaves the queue")
        case .shortcut:
            await #expect(throws: Never.self) {
                try await IntentEngine.perform(request, container: home.container, sideEffects: { _ in home.coordinator },
                                               failures: home.failures, calendar: calendar, now: { now })
            }
        }
    }

    @Test(arguments: OutsideSurface.allCases)
    func aStaleTapChangesNothing(surface: OutsideSurface) async throws {
        let now = noon("2026-11-06")
        let home = try await household(now: now)
        let before = home.rent.history.count

        // "Am rezolvat" on the November reminder, or "Gata" on a widget that still showed November.
        await send(OutsideRequest(obligationId: home.rent.id, cycle: CalendarDay("2026-11-05"), action: .complete, surface: surface), to: home, now: now)
        #expect(home.rent.dueDay(in: calendar) == CalendarDay("2026-12-05"), "December stays open")
        #expect(home.rent.history.count == before)

        // A tap that can't say which cycle it was for changes nothing either.
        await send(OutsideRequest(obligationId: home.rent.id, cycle: nil, action: .complete, surface: surface), to: home, now: now)
        #expect(home.rent.dueDay(in: calendar) == CalendarDay("2026-12-05"))
        #expect(home.rent.history.count == before)
        #expect(home.failures.all().isEmpty, "A stale tap isn't a failure")
    }

    @Test(arguments: OutsideSurface.allCases)
    func aTapForTheOpenCycleCompletesItAndPlansAgain(surface: OutsideSurface) async throws {
        let now = noon("2026-12-03")
        let home = try await household(now: now)
        await home.center.deliver(DeliveredReminder(identifier: ReminderPlanner.identifier(obligationId: home.rent.id, suffix: "d2"),
                                                    obligationId: home.rent.id, cycle: CalendarDay("2026-12-05")))

        await send(OutsideRequest(obligationId: home.rent.id, cycle: CalendarDay("2026-12-05"), action: .complete, surface: surface), to: home, now: now)
        #expect(home.rent.dueDay(in: calendar) == CalendarDay("2027-01-05"))

        if surface == .widget {
            // The queue is applied by the app, whose own coordinator follows the save.
            await home.coordinator.reconcileNow()
        }
        #expect(home.coordinator.lastReconciledAt != nil)
        #expect(await home.center.deliveredReminders.isEmpty, "The December reminder already shown is cleared")
        let pending = await home.center.pendingReminders.keys
        #expect(!pending.isEmpty)
        #expect(pending.allSatisfy { $0.contains(home.rent.id.uuidString.lowercased()) })
    }

    @Test func aNotificationSnoozeActsOnItsCycleOnly() async throws {
        let now = noon("2026-12-03")
        let home = try await household(now: now)
        await send(OutsideRequest(obligationId: home.rent.id, cycle: CalendarDay("2026-11-05"), action: .snooze(days: 3), surface: .notification), to: home, now: now)
        #expect(home.rent.snoozedUntil == nil)
        await send(OutsideRequest(obligationId: home.rent.id, cycle: CalendarDay("2026-12-05"), action: .snooze(days: 3), surface: .notification), to: home, now: now)
        #expect(home.rent.snoozedUntil != nil)
    }

    @Test func remindersCarryTheirCycleAndOldOnesAreReadFromTheirIdentifier() {
        let id = UUID()
        let carried = ReminderPayload(
            identifier: ReminderPlanner.identifier(obligationId: id, suffix: "d7"),
            userInfo: ["obligationId": id.uuidString, "dueDay": "2026-11-10"],
            deliveredAt: noon("2026-11-03"),
            calendar: calendar
        )
        #expect(carried.obligationId == id)
        #expect(carried.cycle == CalendarDay("2026-11-10"))

        // Planned before reminders carried their cycle: the lead day and the delivery day give it.
        let old = ReminderPayload(identifier: ReminderPlanner.identifier(obligationId: id, suffix: "d7"), userInfo: [:], deliveredAt: noon("2026-11-03"), calendar: calendar)
        #expect(old.cycle == CalendarDay("2026-11-10"))
        let lapse = ReminderPayload(identifier: ReminderPlanner.identifier(obligationId: id, suffix: "lapse"), userInfo: [:], deliveredAt: noon("2026-11-11"), calendar: calendar)
        #expect(lapse.cycle == CalendarDay("2026-11-10"))
        let snooze = ReminderPayload(identifier: ReminderPlanner.identifier(obligationId: id, suffix: "snooze"), userInfo: [:], deliveredAt: noon("2026-11-11"), calendar: calendar)
        #expect(snooze.cycle == nil, "Can't be told, so its buttons change nothing")
    }

    @Test func shownRemindersForClosedCyclesAreCleared() async {
        let open = UUID()
        let done = UUID()
        let center = FakeNotificationCenter(status: .authorized)
        await center.deliver(DeliveredReminder(identifier: "obligation.\(open.uuidString.lowercased()).d7", obligationId: open, cycle: CalendarDay("2026-11-10")))
        await center.deliver(DeliveredReminder(identifier: "obligation.\(open.uuidString.lowercased()).lapse", obligationId: open, cycle: CalendarDay("2026-10-10")))
        await center.deliver(DeliveredReminder(identifier: "obligation.\(done.uuidString.lowercased()).d1", obligationId: done, cycle: CalendarDay("2026-11-04")))
        await center.deliver(DeliveredReminder(identifier: ReminderPlanner.continueIdentifier, obligationId: nil, cycle: nil))
        await center.deliver(DeliveredReminder(identifier: "someone.else", obligationId: nil, cycle: nil))

        let outcome = await NotificationReconciler(client: center).apply([], badgeCount: 0, openCycles: [open: CalendarDay("2026-11-10")], allowPermissionPrompt: false)
        #expect(outcome.clearedDelivered == 3)
        #expect(await center.deliveredReminders.map(\.identifier) == ["obligation.\(open.uuidString.lowercased()).d7", "someone.else"])
    }

    @Test func aTapThatCantBeSavedIsKeptForUrmeaza() async throws {
        let failures = OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)")
        let id = UUID()
        let request = OutsideRequest(obligationId: id, cycle: CalendarDay("2026-11-10"), action: .complete, surface: .notification)
        await #expect(throws: IntentError.self) {
            try await IntentEngine.perform(request, container: nil, failures: failures)
        }
        #expect(failures.all().map(\.obligationId) == [id])

        // Siri says it at once, so nothing waits for Urmează.
        let quiet = OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)")
        await #expect(throws: IntentError.self) {
            try await IntentEngine.perform(OutsideRequest(obligationId: id, cycle: nil, action: .complete, surface: .shortcut), container: nil, failures: quiet)
        }
        #expect(quiet.all().isEmpty)

        // Shown while that cycle is open; forgotten once it closes.
        let open = snapshot("RCA", kind: .insurance, due: "2026-11-10")
        let other = OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)")
        other.record(OutsideRequest(obligationId: open.id, cycle: CalendarDay("2026-11-10"), action: .complete, surface: .widget), at: noon("2026-11-03"))
        #expect(other.current(in: [open]).map(\.failure.obligationId) == [open.id])
        var moved = open
        moved.dueDay = CalendarDay("2027-11-10")
        #expect(other.current(in: [moved]).isEmpty)
        #expect(other.all().isEmpty)
    }

    @Test func examplesNeverLeaveTheAppOrChangeFromOutside() throws {
        let context = try makeContext()
        try ExampleDataService(context: context, calendar: calendar, now: { noon("2026-11-02") }).loadExamples()
        let all = try ObligationSnapshot.fetchAll(in: context, calendar: calendar)
        #expect(all.contains { $0.isExample })
        #expect(try ObligationSnapshot.fetchForOutside(in: context, calendar: calendar).isEmpty, "Siri, Shortcuts, widgets and reminders see no examples")

        let example = try #require(try context.fetch(FetchDescriptor<Obligation>()).first { $0.isExample && $0.status == .active })
        let outcome = try IntentEngine.apply(OutsideRequest(obligationId: example.id, cycle: example.dueDay(in: calendar), action: .complete, surface: .shortcut),
                                             in: context, calendar: calendar)
        #expect(outcome == .skipped)
    }

    @Test func likelyDoubleCompletionsAreFoundNotChanged() throws {
        typealias C = LikelyDoubleCompletions.Completion
        let first = C(id: UUID(), occurredAt: noon("2026-11-03"), cycle: CalendarDay("2026-11-05"), next: CalendarDay("2026-12-05"))
        let stale = C(id: UUID(), occurredAt: noon("2026-11-04"), cycle: CalendarDay("2026-12-05"), next: CalendarDay("2027-01-05"))
        #expect(LikelyDoubleCompletions.isLikely(latest: stale, previous: first, calendar: calendar))

        let nextMonth = C(id: UUID(), occurredAt: noon("2026-12-04"), cycle: CalendarDay("2026-12-05"), next: CalendarDay("2027-01-05"))
        #expect(!LikelyDoubleCompletions.isLikely(latest: nextMonth, previous: first, calendar: calendar), "A month apart is two real payments")
        let movedByHand = C(id: UUID(), occurredAt: noon("2026-11-04"), cycle: CalendarDay("2026-12-20"), next: CalendarDay("2027-01-20"))
        #expect(!LikelyDoubleCompletions.isLikely(latest: movedByHand, previous: first, calendar: calendar), "Only consecutive cycles")
        let lateThenOnTime = C(id: UUID(), occurredAt: noon("2026-11-04"), cycle: CalendarDay("2026-11-05"), next: CalendarDay("2026-12-05"))
        let late = C(id: UUID(), occurredAt: noon("2026-11-03"), cycle: CalendarDay("2026-10-05"), next: CalendarDay("2026-11-05"))
        #expect(!LikelyDoubleCompletions.isLikely(latest: lateThenOnTime, previous: late, calendar: calendar), "Catching up on a late month is real")

        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-03") })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-11-05"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate))
        try actions.complete(rent, on: noon("2026-11-03"))
        try actions.complete(rent, on: noon("2026-11-04"))
        let found = try LikelyDoubleCompletions.find(in: context, calendar: calendar)
        #expect(found.map(\.obligationId) == [rent.id])
        #expect(found.first?.historyEntryId == rent.history.first?.id)
        #expect(rent.history.count == 2, "Finding changes nothing")

        // Only with the person's OK, and safe to run twice.
        let candidate = try #require(found.first)
        #expect(try LikelyDoubleCompletions.undoSecond(candidate, in: context, calendar: calendar))
        #expect(rent.history.count == 1)
        #expect(rent.dueDay(in: calendar) == CalendarDay("2026-12-05"))
        #expect(try !LikelyDoubleCompletions.undoSecond(candidate, in: context, calendar: calendar))
        #expect(rent.history.count == 1)
        #expect(try LikelyDoubleCompletions.find(in: context, calendar: calendar).isEmpty)
    }

    /// The review's probe, turned around: an old "Am rezolvat" left in Notification
    /// Center, tapped after the deadline was done in the app, closes nothing.
    @Test func aStaleNotificationNoLongerClosesTheNextCycle() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let actions = ObligationActions(context: context, calendar: calendar)
        let rca = try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay(Date(), calendar: calendar), for: nil,
                                     recurrence: .interval(.years(1), anchor: .dueDate))
        let first = rca.dueDay(in: calendar)
        // The reminder shown today, as the notification center hands it back.
        let identifier = ReminderPlanner.identifier(obligationId: rca.id, suffix: "d0")
        let payload = ReminderPayload(identifier: identifier, userInfo: ["obligationId": rca.id.uuidString, "dueDay": first.isoString],
                                      deliveredAt: Date(), calendar: calendar)
        // Done in the app.
        try actions.complete(rca)
        #expect(rca.dueDay(in: calendar) == RecurrenceEngine.add(.years(1), to: first, calendar: calendar))

        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let coordinator = SideEffectsCoordinator(container: container, notificationClient: FakeNotificationCenter(status: .authorized),
                                                 widgetWriter: WidgetSnapshotWriter(directory: folder), calendar: calendar)
        let responder = NotificationResponder(containerProvider: { container }, navigator: AppNavigator(),
                                              sideEffects: { _ in coordinator }, failures: OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)"))
        await responder.handle(action: ReminderActions.complete, payload: payload, calendar: calendar)
        #expect(rca.history.count == 1, "The stale tap completed nothing")
        #expect(rca.dueDay(in: calendar) == RecurrenceEngine.add(.years(1), to: first, calendar: calendar), "Next year's cycle stays open")
    }
}
