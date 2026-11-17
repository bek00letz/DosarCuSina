import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A locked section behaves the same on every surface: one answer for whether it is locked, even
/// before its category's record arrives; every route and sheet that shows or writes into a
/// section opens behind it; and closing one of its deadlines asks for Face ID from every way in,
/// while „Amână” never does. Every value is a placeholder.
@MainActor
@Suite("Locked sections, everywhere")
struct LockedSectionsEverywhereTests {
    let calendar = Calendar.bucharest

    /// Counts the Face ID prompts a request asked for, and answers them as told.
    @MainActor final class Prompts {
        var answer: UnlockResult
        var count = 0
        init(_ answer: UnlockResult) { self.answer = answer }
        var confirm: IntentEngine.ClosingConfirmation {
            { [self] _ in
                count += 1
                return answer
            }
        }
    }

    private struct Household {
        let container: ModelContainer
        let car: Asset
        let itp: Obligation
        let coordinator: SideEffectsCoordinator
        let failures: OutsideActionFailures
        let folder: URL
    }

    /// A car whose ITP is due 5 December, its category locked on this device or not.
    private func household(locked: Bool, now: Date) async throws -> Household {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context, calendar: calendar, now: { now }).create(name: "VW Golf 2018", template: template, values: FieldValues())
        let itp = try ObligationActions(context: context, calendar: calendar, now: { now })
            .create(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-12-05"), for: car)
        if locked { try template.setLock(true) }
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        let coordinator = SideEffectsCoordinator(
            container: container,
            notificationClient: FakeNotificationCenter(status: .authorized),
            widgetWriter: WidgetSnapshotWriter(directory: folder),
            preferences: AppPreferences(defaults: defaults),
            calendar: { calendar },
            now: { now }
        )
        return Household(container: container, car: car, itp: itp, coordinator: coordinator,
                         failures: OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)"), folder: folder)
    }

    /// Sends one request through the real entry point of `surface`, answering Face ID with `prompts`.
    @discardableResult
    private func send(_ request: OutsideRequest, to home: Household, prompts: Prompts, navigator: AppNavigator = AppNavigator(isAppLocked: { false }),
                      now: Date) async -> IntentEngine.Outcome? {
        switch request.surface {
        case .notification:
            let responder = NotificationResponder(containerProvider: { home.container }, navigator: navigator,
                                                  sideEffects: { _ in home.coordinator }, failures: home.failures, confirmClosing: prompts.confirm)
            let action = request.action == .complete ? ReminderActions.complete : ReminderActions.snooze
            await responder.handle(action: action, payload: ReminderPayload(obligationId: request.obligationId, cycle: request.cycle), calendar: calendar)
            return nil
        case .widget:
            let queue = WidgetCompletionQueue(fileURL: home.folder.appending(path: WidgetCompletionQueue.fileName))
            queue.enqueue(WidgetCompletion(obligationId: request.obligationId, dueDay: request.cycle?.isoString ?? "", requestedAt: now))
            IntentEngine.applyQueuedWidgetCompletions(queue: queue, in: home.container.mainContext, failures: home.failures, calendar: calendar, now: { now })
            #expect(queue.pending().isEmpty, "A tap the app handled leaves the queue")
            return nil
        case .shortcut:
            return try? await IntentEngine.perform(request, container: home.container, sideEffects: { _ in home.coordinator },
                                                   failures: home.failures, confirmClosing: prompts.confirm, calendar: calendar, now: { now })
        }
    }

    // MARK: One answer for a section's lock

    @Test func aSectionWhoseCategoryHasntArrivedStaysLocked() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let section = try AssetActions(context: context, calendar: calendar).create(name: "Caiet", template: template, values: FieldValues())
        try ObligationActions(context: context, calendar: calendar).create(title: "Termen", kind: .routine, dueDay: CalendarDay("2026-12-05"), for: section)
        #expect(!section.isSensitive(template: template), "A car is open by default")

        // Its category of one's own is still on its way from another device.
        section.templateKey = "custom.0b6c6f43-0000-4000-8000-0000000000aa"
        #expect(section.isSensitive(template: nil), "No record yet: locked until it arrives")
        #expect(section.isSensitive(among: try TemplateStore(context: context).templatesByKey()))
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(.cancel), appLockEnabled: { false }, observesAppLifecycle: false)
        #expect(vault.isLocked(section, template: nil))
        let snapshot = try #require(try ObligationSnapshot.fetchAll(in: context, calendar: calendar).first)
        #expect(snapshot.isSensitive, "Reminders, widgets and Siri give it the generic words")
        #expect(try SpotlightCatalog.entries(obligations: [snapshot], in: context).isEmpty, "Nothing of it in the iPhone's search")

        // This device's own choice for the key still counts, and a built-in follows the catalog.
        try SectionLocks.of(container).set(false, for: section.templateKey)
        #expect(!section.isSensitive(template: nil))
        #expect(!CategoryTemplate.isSensitive(key: BuiltInTemplates.Key.vehicle, template: nil, in: nil))
        #expect(CategoryTemplate.isSensitive(key: BuiltInTemplates.Key.documents, template: nil, in: nil))
        #expect(CategoryTemplate.isSensitive(key: "custom.unknown", template: nil, in: nil))
    }

    // MARK: Routes and sheets

    @Test func everyRouteAndSheetIntoASectionOpensBehindItsLock() {
        let id = UUID()
        // The link „dosarcusina://visit/<id>” opens the visit's sheet over its section, both behind its lock.
        let visit = ShellRouting.plan(for: .addVisit(id))
        #expect(visit.sheet?.lock == .section(id))
        #expect(visit.locks == [.section(id), .section(id)])
        #expect(ShellRouting.plan(for: .asset(id)).locks == [.section(id)])

        #expect(ShellSheet.addVisit(id).lock == .section(id))
        #expect(ShellSheet.addSection(AddSectionRequest(parentID: id, templateKey: nil)).lock == .section(id))
        #expect(ShellSheet.addPersonalDocument(holderID: id).lock == .section(id))
        #expect(ShellSheet.addSection(.topLevel).lock == .open, "A new top-level section reveals nothing")
        #expect(ShellSheet.addPersonalDocument(holderID: nil).lock == .open)
        #expect(ShellSheet.settings(nil).lock == .open)

        // A record's screen draws the lock itself; nothing that names one of a section's records is open.
        let records: [AppRoute] = [.obligation(id), .historyEntry(id), .document(id), .provider(id), .category("vehicle"),
                                   .readiness(.sale(assetID: id)), .readiness(.trip(holderID: nil))]
        for route in records { #expect(route.lock == .drawnByItsScreen, "\(route)") }
        let open: [AppRoute] = [.home, .upcoming, .search, .intake, .agenda, .settings(nil)]
        for route in open { #expect(route.lock == .open, "\(route)") }
    }

    // MARK: Closing asks for Face ID, snoozing doesn't

    @Test func theRuleClosesWithFaceIDAndSnoozesFreely() {
        #expect(DeadlineChange.close.asksFaceID(inLockedCategory: true))
        #expect(!DeadlineChange.close.asksFaceID(inLockedCategory: false))
        #expect(!DeadlineChange.snooze.asksFaceID(inLockedCategory: true))
        #expect(OutsideAction.complete.change == .close)
        #expect(OutsideAction.snooze(days: 3).change == .snooze)
        #expect(OutsideSurface.notification.canAskFaceID && OutsideSurface.shortcut.canAskFaceID)
        #expect(!OutsideSurface.widget.canAskFaceID, "A widget runs in the background")

        // A reminder of a locked category opens the app for „Am rezolvat”; „Amână” stays on the Lock Screen.
        #expect(ReminderActions.completeOptions(isProtected: true).contains(.foreground))
        #expect(ReminderActions.completeOptions(isProtected: true).contains(.authenticationRequired))
        #expect(!ReminderActions.completeOptions(isProtected: false).contains(.foreground))
        #expect(ReminderActions.snoozeOptions(isProtected: true).isEmpty)
        #expect(ReminderActions.snoozeOptions(isProtected: false).isEmpty)
        #expect(ReminderActions.category(isProtected: true) != ReminderActions.category(isProtected: false))
    }

    @Test func aRemindersButtonKnowsItsCategorysLock() {
        let locked = snapshot("ITP", kind: .legal, due: "2026-12-05", isSensitive: true)
        let open = snapshot("ITP", kind: .legal, due: "2026-12-05")
        let lockedReminder = ReminderPlanner.reminder(for: locked, on: CalendarDay("2026-12-04"), fireDate: noon("2026-12-04"),
                                                     identifierSuffix: "d1", calendar: calendar, locale: .dosarDefault)
        let openReminder = ReminderPlanner.reminder(for: open, on: CalendarDay("2026-12-04"), fireDate: noon("2026-12-04"),
                                                   identifierSuffix: "d1", calendar: calendar, locale: .dosarDefault)
        #expect(lockedReminder.isProtected)
        #expect(!openReminder.isProtected)
        #expect(lockedReminder.fingerprint != openReminder.fingerprint, "Locking a category plans its reminders again")
    }

    @Test(arguments: OutsideSurface.allCases)
    func closingALockedDeadlineAsksFaceIDFirst(surface: OutsideSurface) async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: true, now: now)
        let request = OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-12-05"), action: .complete, surface: surface)

        // Face ID not given (or, on a widget, not possible): nothing closes.
        let refused = Prompts(.cancelled)
        let navigator = AppNavigator(isAppLocked: { false })
        let outcome = await send(request, to: home, prompts: refused, navigator: navigator, now: now)
        #expect(home.itp.status == .active)
        #expect(home.itp.dueDay == CalendarDay("2026-12-05"))
        #expect(refused.count == (surface.canAskFaceID ? 1 : 0))
        switch surface {
        case .notification:
            #expect(home.failures.all().map(\.obligationId) == [home.itp.id], "It waits in Urmează")
            #expect(navigator.pendingRoute == .obligation(home.itp.id), "Its page opens, to finish there")
        case .widget:
            #expect(home.failures.all().map(\.obligationId) == [home.itp.id], "It waits in Urmează")
        case .shortcut:
            #expect(outcome == .leftForTheApp)
            #expect(home.failures.all().isEmpty, "Siri says it at once")
        }

        // Confirmed: it closes, where the surface can ask.
        guard surface.canAskFaceID else { return }
        let given = Prompts(.success)
        await send(request, to: home, prompts: given, now: now)
        #expect(given.count == 1)
        #expect(home.itp.status != .active || home.itp.dueDay != CalendarDay("2026-12-05"), "Closed after Face ID")
    }

    @Test(arguments: OutsideSurface.allCases)
    func anOpenCategorysDeadlineClosesWithoutAsking(surface: OutsideSurface) async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: false, now: now)
        let prompts = Prompts(.cancelled)
        await send(OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-12-05"), action: .complete, surface: surface),
                   to: home, prompts: prompts, now: now)
        #expect(prompts.count == 0)
        #expect(home.itp.status != .active || home.itp.dueDay != CalendarDay("2026-12-05"))
        #expect(home.failures.all().isEmpty)
    }

    @Test func snoozingALockedDeadlineFromTheLockScreenAsksNothing() async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: true, now: now)
        let prompts = Prompts(.cancelled)
        let request = OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-12-05"), action: .snooze(days: 3), surface: .notification)
        #expect(try !IntentEngine.asksFaceID(request, in: home.container.mainContext))
        await send(request, to: home, prompts: prompts, now: now)
        #expect(prompts.count == 0)
        #expect(home.itp.snoozedUntil != nil)
        #expect(home.failures.all().isEmpty)
    }

    @Test func aStaleTapOnALockedDeadlineAsksNothing() async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: true, now: now)
        let prompts = Prompts(.success)
        let stale = OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-11-05"), action: .complete, surface: .notification)
        #expect(try !IntentEngine.asksFaceID(stale, in: home.container.mainContext))
        await send(stale, to: home, prompts: prompts, now: now)
        #expect(prompts.count == 0)
        #expect(home.itp.dueDay == CalendarDay("2026-12-05"))
    }

    @Test func theWidgetOffersGataOnlyWhereClosingAsksNothing() {
        let id = UUID()
        func item(_ isSensitive: Bool) -> WidgetFeed.Item {
            WidgetFeed.Item(obligationId: id, assetId: nil, title: "ITP", assetName: "VW Golf 2018", symbol: "car", tint: "gray", dueDate: CalendarDay("2026-12-05"),
                            kind: "legal", isSensitive: isSensitive, deepLink: DeepLink.url(for: .obligation(id)), urgency: nil)
        }
        for isSensitive in [true, false] {
            let feed = WidgetFeed(generatedAt: noon("2026-12-03"), needsActionCount: 0, items: [item(isSensitive)])
            let row = WidgetContent.rows(feed: feed, completed: [], now: noon("2026-12-03"), calendar: calendar, protectedTitle: "Scadență protejată", limit: 3).first
            #expect(row?.canComplete == !isSensitive)
        }
    }
}
