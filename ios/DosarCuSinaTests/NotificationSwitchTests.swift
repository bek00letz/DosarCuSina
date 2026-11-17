import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Settings' „Notificări”: this device's one switch for the app's reminders, its badge and the
/// share's notice, kept once (`NotificationSwitch`, through `AppPreferences.notificationsOn`) and
/// acted on only by `SideEffectsCoordinator`. iOS's own permission is left as it is.
@MainActor
@Suite("Notificări, this device's switch")
struct NotificationSwitchTests {
    @Test func offStopsEveryReminderAndTheBadgeAndOnBringsThemBack() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-20"), for: nil)
        try actions.create(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-10-25"), for: nil)

        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let center = FakeNotificationCenter(status: .authorized)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.notificationsOn, "On until the person turns it off")
        let coordinator = SideEffectsCoordinator(
            container: container,
            notificationClient: center,
            widgetWriter: WidgetSnapshotWriter(directory: directory),
            inboxNotices: FakeInboxNoticeCenter(allowed: true),
            waitingInboxItems: { [] },
            preferences: preferences,
            calendar: { .bucharest },
            now: { noon("2026-11-02") }
        )

        await coordinator.reconcileNow()
        let planned = await center.pendingReminders.count
        #expect(planned > 0)
        #expect((await center.badge ?? 0) > 0, "The overdue ITP shows on the badge")

        preferences.notificationsOn = false
        await coordinator.reconcileNow()
        #expect(await center.pendingReminders.isEmpty, "Off: every pending reminder goes, and none is planned")
        #expect(await center.badge == 0, "Off: the badge clears")
        #expect(await center.promptCount == 0, "iOS's own permission is left as it is")
        #expect(coordinator.reminderAuthorization == .authorized)
        let widget = try #require(WidgetFeed.decode(Data(contentsOf: directory.appending(path: WidgetFeed.fileName))))
        #expect(!widget.items.isEmpty, "The widget follows the binder either way")

        // Kept once, where the share extension reads it, and remembered.
        #expect(!NotificationSwitch.isOn(in: defaults))
        #expect(!AppPreferences(defaults: defaults).notificationsOn)

        preferences.notificationsOn = true
        await coordinator.reconcileNow()
        #expect(await center.pendingReminders.count == planned, "On: they all come back")
        #expect((await center.badge ?? 0) > 0)
    }

    @Test func theSwitchIsOnUntilChosenAndKeptWhereTheExtensionReadsIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        #expect(NotificationSwitch.isOn(in: defaults))
        NotificationSwitch.set(false, in: defaults)
        #expect(!NotificationSwitch.isOn(in: defaults))
        #expect(!AppPreferences(defaults: .standard, groupDefaults: defaults).notificationsOn, "The app reads the one the extension reads")
    }
}
