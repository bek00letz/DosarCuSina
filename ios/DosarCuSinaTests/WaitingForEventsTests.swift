import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Screens wait for what they are waiting for, never for a guessed pause: the next sheet for
/// the last one's dismissal, Settings for its list, the permission for the person's answer.
@Suite("Waiting for the event")
struct WaitingForEventsTests {

    // MARK: The next sheet

    @Test("With nothing on screen a sheet opens at once, and nil closes")
    func opensAtOnce() {
        var sheets = ShellSheetQueue()
        sheets.present(.settings(nil))
        #expect(sheets.shown == .settings(nil))
        #expect(sheets.isBusy)
        sheets.present(nil)
        #expect(sheets.shown == nil)
        #expect(!sheets.isBusy)
    }

    @Test("Over a sheet on screen, the next one waits for its dismissal to complete")
    func waitsForTheDismissal() {
        let id = UUID()
        var sheets = ShellSheetQueue()
        sheets.present(.settings(nil))
        sheets.didAppear()
        sheets.present(.addVisit(id))
        #expect(sheets.shown == nil, "The one on screen closes first")
        #expect(sheets.waiting == .addVisit(id))
        #expect(sheets.isBusy, "Nothing else pops up while it closes")
        sheets.didDismiss()
        #expect(sheets.shown == .addVisit(id))
        #expect(sheets.waiting == nil)
        #expect(!sheets.isOnScreen)
    }

    @Test("While one closes, the newest asked for wins, and nil forgets it")
    func newestWins() {
        let first = UUID(), second = UUID()
        var sheets = ShellSheetQueue()
        sheets.present(.settings(nil))
        sheets.didAppear()
        sheets.present(nil)
        sheets.present(.addVisit(first))
        sheets.present(.addVisit(second))
        sheets.didDismiss()
        #expect(sheets.shown == .addVisit(second))

        sheets.didAppear()
        sheets.present(.settings(.backup))
        sheets.present(nil)
        sheets.didDismiss()
        #expect(sheets.shown == nil)
        #expect(!sheets.isBusy)
    }

    @Test("The same sheet asked for again stays open; one that never came on screen is replaced at once")
    func sameSheetAndNeverShown() {
        var sheets = ShellSheetQueue()
        sheets.present(.settings(.backup))
        sheets.didAppear()
        sheets.present(.settings(.backup))
        #expect(sheets.shown == .settings(.backup))
        #expect(sheets.waiting == nil)

        // Asked for and replaced before it was drawn: there is no dismissal to wait for.
        var quick = ShellSheetQueue()
        quick.present(.settings(nil))
        quick.present(.addSection(.topLevel))
        #expect(quick.shown == .addSection(.topLevel))
    }

    @Test("A sheet closed by a swipe leaves nothing waiting")
    func swipedAway() {
        var sheets = ShellSheetQueue()
        sheets.present(.settings(nil))
        sheets.didAppear()
        sheets.present(nil)
        sheets.didDismiss()
        #expect(sheets.shown == nil)
        #expect(!sheets.isBusy)
    }

    @MainActor
    @Test("A route with a sheet over another sheet opens it once the first has closed")
    func routerWaitsForTheDismissal() {
        let id = UUID()
        let router = ShellRouter()
        router.open(.settings(.notifications))
        router.sheetDidAppear()
        router.open(.addVisit(id))
        #expect(router.sheet == nil)
        #expect(router.hasSheet)
        #expect(router.tab == .dosar && router.dosarPath.count == 1, "The path moves at once; only the sheet waits")
        router.sheetDidDismiss()
        #expect(router.sheet == .addVisit(id))

        router.sheetDidAppear()
        router.sheet = nil
        router.sheetDidDismiss()
        #expect(!router.hasSheet)
    }

    // MARK: Settings at a section

    @Test("Settings keeps the linked section at the top once the list has rows, until the person scrolls")
    func settingsLanding() {
        var landing = SettingsLanding(.backup)
        #expect(landing.section(whenLaidOut: 0) == nil, "No rows yet: nothing to scroll to")
        #expect(landing.section(whenLaidOut: 640) == .backup)
        #expect(landing.section(whenLaidOut: 1800) == .backup, "Rows that change height keep it in place")
        landing.personScrolled()
        #expect(landing.section(whenLaidOut: 2000) == nil)
        #expect(SettingsLanding(nil).section(whenLaidOut: 640) == nil)
    }

    // MARK: The permission

    @MainActor
    @Test("Asking returns with the person's answer, once, and only when something reminds")
    func askingReturnsWithTheAnswer() async throws {
        for grants in [true, false] {
            let container = try makeInMemoryContainer()
            let context = container.mainContext
            try TemplateStore(context: context).installBuiltIns()
            let center = FakeNotificationCenter(status: .notDetermined, grants: grants)
            let coordinator = try Self.coordinator(container, center: center)

            #expect(await coordinator.askForPermission() == .notDetermined, "Nothing reminds: nothing to ask")
            #expect(await center.promptCount == 0)

            try ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
                .create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-30"), for: nil)
            let answer = await coordinator.askForPermission()
            #expect(answer == (grants ? .authorized : .denied))
            #expect(coordinator.reminderAuthorization == answer, "Settings shows it as soon as it returns")
            #expect(await center.promptCount == 1)

            let permission = ReminderPermission(client: center, becomesActive: Notification.Name("tests.\(UUID().uuidString)"))
            await permission.refresh()
            #expect(permission.status == answer)
            #expect(await coordinator.askForPermission() == answer)
            #expect(await center.promptCount == 1, "Asked once")
        }
    }

    @MainActor
    @Test("The permission is read again when the app becomes active")
    func readsAgainWhenActive() async {
        let center = FakeNotificationCenter(status: .notDetermined, grants: false)
        let becameActive = Notification.Name("tests.\(UUID().uuidString)")
        let permission = ReminderPermission(client: center, becomesActive: becameActive)
        await permission.refresh()
        #expect(permission.status == .notDetermined)

        // The person answers the system's question (or changes it in the phone's Settings).
        _ = await center.requestAuthorization()
        NotificationCenter.default.post(name: becameActive, object: nil)
        for _ in 0..<1_000 where permission.status != .denied { await Task.yield() }
        #expect(permission.status == .denied)
    }

    @MainActor
    private static func coordinator(_ container: ModelContainer, center: FakeNotificationCenter) throws -> SideEffectsCoordinator {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        return SideEffectsCoordinator(
            container: container,
            notificationClient: center,
            widgetWriter: WidgetSnapshotWriter(directory: directory),
            preferences: AppPreferences(defaults: defaults),
            calendar: .bucharest,
            now: { noon("2026-11-02") }
        )
    }
}
