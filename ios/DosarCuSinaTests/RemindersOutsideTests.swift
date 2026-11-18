import AppIntents
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What reminders, the badge, the widget and Siri do while the app isn't on screen: a deadline
/// whose closing asks a new day or a new document is closed only in the app's "Am rezolvat"; a
/// widget's "Gata" takes that deadline's reminders away at once; the badge moves as days pass;
/// a reminder shown before its category was locked leaves Notification Center; and a locked app
/// lists nothing in Siri and Shortcuts.
@MainActor
@Suite("Reminders and actions outside the app")
struct RemindersOutsideTests {
    let calendar = Calendar.bucharest

    private struct Household {
        let container: ModelContainer
        let center: FakeNotificationCenter
        let coordinator: SideEffectsCoordinator
        let failures: OutsideActionFailures
        let folder: URL
    }

    private func household(now: Date) throws -> Household {
        let container = try makeInMemoryContainer()
        try TemplateStore(context: container.mainContext).installBuiltIns()
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let center = FakeNotificationCenter(status: .authorized)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        let coordinator = SideEffectsCoordinator(
            container: container,
            notificationClient: center,
            widgetWriter: WidgetSnapshotWriter(directory: folder),
            preferences: AppPreferences(defaults: defaults),
            calendar: { calendar },
            now: { now }
        )
        return Household(container: container, center: center, coordinator: coordinator,
                         failures: OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)"), folder: folder)
    }

    // MARK: Closing that asks a new day or a new document

    @Test func onlyKindsThatAskNothingTheAppAloneAsksCloseOutside() {
        let inTheApp = CompletionKind.allCases.filter { !$0.shape.closesOutsideTheApp }
        #expect(Set(inTheApp) == [.newDocument, .documentReplaced, .newHealthCard, .newContract, .newLease, .safetyKit])
        for kind in CompletionKind.allCases {
            let shape = kind.shape
            #expect(shape.closesOutsideTheApp == (shape.newEnd == nil && shape.replacement == nil), "\(kind)")
        }
    }

    /// A one-off renewal of one's own, which asks the new expiry: closed from outside, it would
    /// close for good and never remind again.
    @Test(arguments: OutsideSurface.allCases)
    func aDeadlineThatAsksANewDayIsLeftForTheAppsAmRezolvat(surface: OutsideSurface) async throws {
        let now = noon("2026-12-03")
        let home = try household(now: now)
        let actions = ObligationActions(context: home.container.mainContext, calendar: calendar, now: { now })
        let kit = try actions.create(title: "Trusa medicală", kind: .renewal, dueDay: CalendarDay("2026-12-05"), for: nil)
        #expect(kit.completion(in: home.container.mainContext).newEnd == .expires)
        let cycle = CalendarDay("2026-12-05")
        let request = OutsideRequest(obligationId: kit.id, cycle: cycle, action: .complete, surface: surface)
        #expect(try IntentEngine.needsTheApp(request, in: home.container.mainContext))
        #expect(try !IntentEngine.asksFaceID(request, in: home.container.mainContext), "Its sheet asks behind the lock instead")

        let navigator = AppNavigator(isAppLocked: { false })
        switch surface {
        case .notification:
            let responder = NotificationResponder(containerProvider: { home.container }, navigator: navigator,
                                                  sideEffects: { _ in home.coordinator }, failures: home.failures)
            await responder.handle(action: ReminderActions.complete, payload: ReminderPayload(obligationId: kit.id, cycle: cycle), calendar: calendar)
            #expect(navigator.pendingRoute == .completion(kit.id, cycle: cycle), "Its „Am rezolvat”, for that cycle")
            #expect(home.failures.all().isEmpty)
        case .widget:
            let queue = WidgetCompletionQueue(fileURL: home.folder.appending(path: WidgetCompletionQueue.fileName))
            queue.enqueue(WidgetCompletion(obligationId: kit.id, dueDay: cycle.isoString, requestedAt: now))
            IntentEngine.applyQueuedWidgetCompletions(queue: queue, in: home.container.mainContext, failures: home.failures, calendar: calendar, now: { now })
            #expect(queue.pending().isEmpty)
            #expect(home.failures.all().map(\.obligationId) == [kit.id], "It waits in Urmează")
        case .shortcut:
            let outcome = try await IntentEngine.perform(request, container: home.container, sideEffects: { _ in home.coordinator },
                                                         failures: home.failures, calendar: calendar, now: { now })
            #expect(outcome == .needsTheApp)
        }
        #expect(kit.status == .active, "Never closed for good from outside")
        #expect(kit.dueDay == cycle)
        #expect(kit.history.isEmpty)

        // „Amână” still works where it is.
        let snooze = OutsideRequest(obligationId: kit.id, cycle: cycle, action: .snooze(days: 3), surface: surface)
        #expect(try IntentEngine.apply(snooze, in: home.container.mainContext, calendar: calendar, now: { now }) == .snoozed(until: CalendarDay("2026-12-06")))
    }

    @Test func itsRemindersAndWidgetRowOpenTheApp() throws {
        let kit = snapshot("Trusa medicală", kind: .renewal, due: "2026-12-05")
        let rent = snapshot("Chirie", kind: .payment, due: "2026-12-05")
        #expect(kit.closesInTheApp)
        #expect(!rent.closesInTheApp)

        let reminder = ReminderPlanner.reminder(for: kit, on: CalendarDay("2026-12-04"), fireDate: noon("2026-12-04"),
                                                identifierSuffix: "d1", calendar: calendar, locale: .dosarDefault)
        #expect(reminder.closesInTheApp)
        #expect(ReminderActions.category(isProtected: false, closesInTheApp: true) == ReminderActions.inAppCategoryIdentifier)
        #expect(ReminderActions.category(isProtected: true, closesInTheApp: true) == ReminderActions.protectedCategoryIdentifier)
        #expect(ReminderActions.completeOptions(isProtected: false, closesInTheApp: true).contains(.foreground), "„Am rezolvat” opens the app")
        #expect(!ReminderActions.completeOptions(isProtected: false, closesInTheApp: false).contains(.foreground))
        #expect(ReminderActions.snoozeOptions(isProtected: false).isEmpty, "„Amână” stays on the Lock Screen")

        let feed = WidgetFeed.make(from: [kit, rent], now: noon("2026-12-03"), calendar: calendar)
        let rows = WidgetContent.rows(feed: feed, completed: [], now: noon("2026-12-03"), calendar: calendar, protectedTitle: "", limit: 8)
        #expect(rows.first { $0.id == kit.id }?.canComplete == false, "No „Gata” where closing asks a new day")
        #expect(rows.first { $0.id == rent.id }?.canComplete == true)

        // A snapshot from before the flag was written offers „Gata” as before.
        var older = try #require(feed.items.first { $0.obligationId == kit.id })
        older.closesInTheApp = nil
        let oldRows = WidgetContent.rows(feed: WidgetFeed(generatedAt: .now, needsActionCount: 0, items: [older]), completed: [],
                                         now: noon("2026-12-03"), calendar: calendar, protectedTitle: "", limit: 8)
        #expect(oldRows.first?.canComplete == true)
    }

    @Test func theSheetWaitsForTheNewDay() {
        let shape = CompletionKind.safetyKit.shape
        var draft = CompletionDraft()
        #expect(draft.lacksNewDay(shape: shape), "Saving waits for the kit's new expiry")
        draft.newExpiry = noon("2036-12-05")
        #expect(!draft.lacksNewDay(shape: shape))
        #expect(!CompletionDraft().lacksNewDay(shape: CompletionKind.itp.shape), "A kind that asks no new day doesn't wait")
    }

    @Test func itsLinkOpensAmRezolvatOverItsPage() throws {
        let id = UUID()
        let route = AppRoute.completion(id, cycle: CalendarDay("2026-12-05"))
        #expect(DeepLink.route(from: DeepLink.url(for: route)) == route)
        #expect(DeepLink.route(from: try #require(URL(string: "dosarcusina://complete/\(id.uuidString)"))) == nil, "Without its cycle it opens nothing")
        let plan = ShellRouting.plan(for: route)
        #expect(plan.tab == .upcoming)
        #expect(plan.path == [.obligation(id)])
        #expect(plan.sheet == .completion(obligationID: id, cycle: CalendarDay("2026-12-05")))
        #expect(route.lock == .drawnByItsScreen)
    }

    // MARK: The widget's „Gata” takes its reminders away at once

    @Test func theWidgetsGataRunsInTheApp() {
        let type: any LiveActivityIntent.Type = CompleteFromWidgetIntent.self
        #expect(type == CompleteFromWidgetIntent.self)
    }

    @Test func aWidgetTapTakesThatDeadlinesRemindersAwayAtOnce() async throws {
        let now = noon("2026-12-03")
        let home = try household(now: now)
        let actions = ObligationActions(context: home.container.mainContext, calendar: calendar, now: { now })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-12-05"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate))
        await home.coordinator.reconcileNow()
        let december = await home.center.pendingReminders
        #expect(!december.isEmpty)
        await home.center.deliver(DeliveredReminder(identifier: ReminderPlanner.identifier(obligationId: rent.id, suffix: "d2"),
                                                    obligationId: rent.id, cycle: CalendarDay("2026-12-05")))

        await WidgetCompletionHandler.handle(WidgetCompletion(obligationId: rent.id, dueDay: "2026-12-05", requestedAt: now),
                                             container: home.container, queue: nil, sideEffects: { _ in home.coordinator },
                                             failures: home.failures, calendar: calendar, now: { now })
        #expect(rent.dueDay == CalendarDay("2027-01-05"))
        let after = await home.center.pendingReminders
        for (identifier, reminder) in after where identifier.contains(rent.id.uuidString.lowercased()) {
            #expect(reminder.fingerprint?.contains("2027-01-05") == true, "Only January's reminders are left")
        }
        #expect(await home.center.deliveredReminders.isEmpty, "The December reminder already shown goes too")
    }

    @Test func aWidgetTapBeforeTheBinderOpensWaitsInTheQueue() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = WidgetCompletionQueue(fileURL: folder.appending(path: WidgetCompletionQueue.fileName))
        let tap = WidgetCompletion(obligationId: UUID(), dueDay: "2026-12-05", requestedAt: noon("2026-12-03"))
        let failures = OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)")
        await WidgetCompletionHandler.handle(tap, container: nil, queue: queue, failures: failures)
        #expect(queue.pending() == [tap], "Applied once the binder opens")
        #expect(failures.all().isEmpty)
    }

    // MARK: The badge moves with the days

    @Test func theBadgeIsPlannedForTheDaysItChanges() {
        let now = noon("2026-12-03")
        // Due on the 5th, nothing late before: the badge is 0 until the 5th starts, 1 from then.
        let rent = snapshot("Chirie", kind: .payment, due: "2026-12-05", offsets: [2, 0], grace: 0)
        let reminders = ReminderPlanner.plan([rent], now: now, calendar: calendar)
        let plan = BadgePlanner.plan(reminders, obligations: [rent], now: now, calendar: calendar)

        let onTheDay = plan.filter { !$0.showsAlert }
        #expect(onTheDay.map(\.identifier) == [BadgePlanner.identifierPrefix + "2026-12-05"])
        #expect(onTheDay.first?.badge == 1)
        #expect(onTheDay.first?.fireDate == CalendarDay("2026-12-05").startDate(in: calendar), "As the day starts")
        for reminder in plan where reminder.showsAlert {
            let day = CalendarDay(reminder.fireDate, calendar: calendar)
            #expect(reminder.badge == BadgePlanner.count([rent], on: day, calendar: calendar), "Each reminder carries its day's badge")
            #expect(reminder.fingerprint.hasSuffix("|b\(reminder.badge ?? -1)"))
        }
        #expect(BadgePlanner.count([rent], on: CalendarDay("2026-12-04"), calendar: calendar) == 0)
    }

    @Test func theBadgeTakesOnlyTheRoomTheRemindersLeave() {
        let now = noon("2026-12-03")
        let rent = snapshot("Chirie", kind: .payment, due: "2026-12-05", offsets: [0], grace: 0)
        let reminders = ReminderPlanner.plan([rent], now: now, calendar: calendar)
        let full = BadgePlanner.plan(reminders, obligations: [rent], now: now, calendar: calendar, limit: reminders.count)
        #expect(full.allSatisfy(\.showsAlert), "No room left: the reminders carry the badge alone")
        #expect(full.count == reminders.count)
    }

    @Test func aBadgeAloneNeverAsksForPermission() async {
        let center = FakeNotificationCenter(status: .notDetermined)
        let badgeOnly = BadgePlanner.badgeOnly(1, on: CalendarDay("2036-12-05"), calendar: calendar)
        await NotificationReconciler(client: center).apply([badgeOnly], badgeCount: 0, prompt: .inContext)
        #expect(await center.promptCount == 0, "Nothing to remind about, nothing to ask")
    }

    // MARK: A lock turned on clears what Notification Center still names

    @Test func aShownReminderThatNamesANowLockedDeadlineGoes() async {
        let itp = UUID()
        let cycle = CalendarDay("2026-12-05")
        let center = FakeNotificationCenter(status: .authorized)
        let named = DeliveredReminder(identifier: ReminderPlanner.identifier(obligationId: itp, suffix: "d2"), obligationId: itp, cycle: cycle)
        let generic = DeliveredReminder(identifier: ReminderPlanner.identifier(obligationId: itp, suffix: "d1"), obligationId: itp, cycle: cycle,
                                        isProtected: true)
        await center.deliver(named)
        await center.deliver(generic)
        let reconciler = NotificationReconciler(client: center)

        await reconciler.apply([], badgeCount: 0, openCycles: [itp: cycle], prompt: .never)
        #expect(await center.deliveredReminders.count == 2, "Open: both stay")

        let outcome = await reconciler.apply([], badgeCount: 0, openCycles: [itp: cycle], locked: [itp], prompt: .never)
        #expect(await center.deliveredReminders == [generic], "Locked: only the one in generic words stays")
        #expect(outcome.clearedDelivered == 1)
        #expect(ReminderActions.isProtected(category: ReminderActions.protectedCategoryIdentifier))
        #expect(!ReminderActions.isProtected(category: ReminderActions.inAppCategoryIdentifier))
    }

    // MARK: Siri and Shortcuts while the app is locked

    @Test func aLockedAppListsNothingByNameInSiri() {
        let rent = snapshot("Chirie", kind: .payment, due: "2026-12-05", asset: (UUID(), "Apartament"))
        let open = ObligationEntity(rent, appLockEnabled: false)
        #expect(open.title == "Chirie")
        #expect(open.assetName == "Apartament")
        #expect(open.showsDay)

        let locked = ObligationEntity(rent, appLockEnabled: true)
        #expect(locked.title != "Chirie")
        #expect(locked.assetName == nil)
        #expect(!locked.showsDay, "Not even its day")
        #expect(locked.id == rent.id && locked.dueDay == rent.dueDay, "A saved shortcut still finds it")

        let protected = ObligationEntity(snapshot("ITP", kind: .legal, due: "2026-12-05", isSensitive: true), appLockEnabled: false)
        #expect(protected.title != "ITP")

        #expect(SearchPrivacy.outsideListsAnything(appLockEnabled: false))
        #expect(!SearchPrivacy.outsideListsAnything(appLockEnabled: true))
    }
}
