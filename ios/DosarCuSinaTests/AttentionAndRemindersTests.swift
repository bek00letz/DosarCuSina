import Foundation
import Testing
@testable import DosarCuSina

@Suite("Attention model")
struct AttentionModelTests {
    let calendar = Calendar.bucharest
    let today = noon("2026-11-02")

    @Test func legalDeadlinesOutrankOverdueChores() {
        let digest = AttentionModel.digest([
            snapshot("Udat", kind: .routine, due: "2026-10-28"),
            snapshot("ITP", kind: .legal, due: "2026-11-12"),
            snapshot("Impozit", kind: .tax, due: "2026-10-31"),
        ], now: today, calendar: calendar)
        #expect(digest.now.map(\.obligation.title) == ["Impozit", "ITP", "Udat"])
        #expect(digest.now.first?.urgency == .overdue)
        #expect(digest.needsActionCount == 2)
    }

    @Test func farAwayItemsAreSummarizedNotListed() {
        let digest = AttentionModel.digest([
            snapshot("RCA", kind: .insurance, due: "2026-11-25", asset: (UUID(), "VW Golf"), cost: Money(1_200)),
            snapshot("PAD", kind: .insurance, due: "2027-03-01", cost: Money(130)),
            snapshot("Pașaport", kind: .renewal, due: "2028-01-01", cost: Money(Decimal(string: "60")!, currency: "EUR")),
        ], now: today, calendar: calendar)
        #expect(digest.now.isEmpty)
        #expect(digest.soon.map(\.assetName) == ["VW Golf"])
        #expect(digest.later.count == 2)
        #expect(digest.later.nextDay == CalendarDay("2027-03-01"))
        #expect(digest.later.estimatedCost.amounts.count == 2, "Costs stay per currency")
    }

    @Test func snoozedPausedAndFinishedItemsAreHidden() {
        let digest = AttentionModel.digest([
            snapshot("Amânat", due: "2026-11-02", snoozedUntil: noon("2026-11-05")),
            snapshot("Pauză", due: "2026-11-02", status: .paused),
            snapshot("Gata", due: "2026-11-02", status: .done),
            snapshot("Arhivă", due: "2026-11-02", status: .archived),
        ], now: today, calendar: calendar)
        #expect(digest.now.isEmpty)
        #expect(digest.hiddenCount == 2)
        #expect(digest.isAllClear)
    }

    @Test("Hundreds of obligations still leave a short list on top")
    func staysBoundedAtScale() {
        var items: [ObligationSnapshot] = []
        let kinds = ObligationKind.allCases
        for index in 0..<600 {
            let asset = (UUID(), "Activ \(index % 40)")
            let offset = (index * 7) % 400 - 30
            let due = CalendarDay("2026-11-02").adding(days: offset, calendar: calendar).isoString
            items.append(snapshot("Obligație \(index)", kind: kinds[index % kinds.count], due: due, asset: asset))
        }
        let digest = AttentionModel.digest(items, now: today, calendar: calendar)
        #expect(digest.now.count == 5)
        #expect(digest.overflowCount > 0)
        let shown = digest.now.count + digest.soon.reduce(0) { $0 + $1.entries.count } + digest.later.count
        #expect(shown == 600, "Nothing is lost, it is only folded away")
        let scores = digest.now.map(\.score)
        #expect(scores == scores.sorted(by: >))
        #expect(digest.now.allSatisfy { $0.obligation.kind.consequenceWeight >= ObligationKind.health.consequenceWeight })
    }
}

@Suite("Reminder planner")
struct ReminderPlannerTests {
    let calendar = Calendar.bucharest

    @Test func schedulesOnlyFutureOffsetsAtTheChosenTime() {
        let item = snapshot("ITP", kind: .legal, due: "2026-11-10", asset: (UUID(), "VW Golf"), offsets: [30, 7, 1, 0])
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-02"), calendar: calendar, defaultMinuteOfDay: 9 * 60)
        #expect(plan.count == 3)
        #expect(plan.map { CalendarDay($0.fireDate, calendar: calendar) } == [CalendarDay("2026-11-03"), CalendarDay("2026-11-09"), CalendarDay("2026-11-10")])
        #expect(plan.allSatisfy { calendar.component(.hour, from: $0.fireDate) == 9 })
        #expect(plan.last?.title == "Azi: ITP")
        #expect(plan.last?.isTimeSensitive == true)
        #expect(plan.first?.isTimeSensitive == false)
        #expect(plan.first?.body.hasPrefix("VW Golf") == true)
    }

    @Test func wallClockTimeSurvivesDaylightSaving() {
        // Romania moves clocks forward on 29 March 2026.
        let item = snapshot("Plată", kind: .payment, due: "2026-03-30", offsets: [2, 0])
        let plan = ReminderPlanner.plan([item], now: noon("2026-03-01"), calendar: calendar, defaultMinuteOfDay: 8 * 60 + 30)
        #expect(plan.count == 2)
        for reminder in plan {
            let parts = calendar.dateComponents([.hour, .minute], from: reminder.fireDate)
            #expect(parts.hour == 8 && parts.minute == 30)
        }
    }

    @Test func protectedCategoriesGetGenericText() {
        let item = snapshot("Colonoscopie", kind: .health, due: "2026-11-03", asset: (UUID(), "Profil medical"), offsets: [1], isSensitive: true)
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-01"), calendar: calendar)
        #expect(plan.count == 1)
        #expect(!plan[0].title.contains("Colonoscopie"))
        #expect(!plan[0].body.contains("Profil medical"))
    }

    @Test func examplesAndInactiveItemsNeverRemind() {
        let plan = ReminderPlanner.plan([
            snapshot("Exemplu", due: "2026-11-20", isExample: true),
            snapshot("Pauză", due: "2026-11-20", status: .paused),
            snapshot("Gata", due: "2026-11-20", status: .done),
        ], now: noon("2026-11-02"), calendar: calendar)
        #expect(plan.isEmpty)
    }

    @Test func snoozeReplacesEarlierRemindersWithOne() {
        let item = snapshot("RCA", kind: .insurance, due: "2026-11-10", offsets: [7, 1, 0], snoozedUntil: CalendarDay("2026-11-08").startDate(in: calendar))
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-03"), calendar: calendar)
        #expect(plan.map(\.identifier).contains { $0.hasSuffix(".snooze") })
        #expect(plan.allSatisfy { $0.fireDate >= CalendarDay("2026-11-08").startDate(in: calendar) })
        #expect(!plan.contains { $0.identifier.hasSuffix(".d7") })
    }

    @Test func respectsTheSystemLimitByKeepingTheSoonest() {
        let items = (0..<40).map { snapshot("O\($0)", due: CalendarDay("2026-11-10").adding(days: $0, calendar: calendar).isoString, offsets: [7, 1, 0]) }
        let plan = ReminderPlanner.plan(items, now: noon("2026-11-02"), calendar: calendar)
        #expect(plan.count == ReminderPlanner.defaultLimit)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
    }

    @Test func identifiersRoundTrip() {
        let id = UUID()
        let identifier = ReminderPlanner.identifier(obligationId: id, suffix: "d7")
        #expect(ReminderPlanner.obligationId(fromIdentifier: identifier) == id)
        #expect(ReminderPlanner.obligationId(fromIdentifier: "other.\(id)") == nil)
    }
}

/// Records what the reconciler asks of the notification center.
actor FakeNotificationCenter: NotificationCenterClient {
    var status: ReminderAuthorization
    var grants: Bool
    private(set) var pendingReminders: [String: PendingReminder] = [:]
    private(set) var promptCount = 0
    private(set) var badge: Int?

    init(status: ReminderAuthorization, grants: Bool = true, pending: [PendingReminder] = []) {
        self.status = status
        self.grants = grants
        for item in pending { pendingReminders[item.identifier] = item }
    }

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async -> Bool {
        promptCount += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func pending() async -> [PendingReminder] { Array(pendingReminders.values) }

    func add(_ reminder: PlannedReminder) async throws {
        pendingReminders[reminder.identifier] = PendingReminder(identifier: reminder.identifier, fingerprint: reminder.fingerprint)
    }

    func remove(identifiers: [String]) async {
        for identifier in identifiers { pendingReminders.removeValue(forKey: identifier) }
    }

    func setBadgeCount(_ count: Int) async { badge = count }
    func registerCategories() async {}
}

@Suite("Notification reconciler")
struct NotificationReconcilerTests {
    let calendar = Calendar.bucharest

    private func plan(_ titles: [String]) -> [PlannedReminder] {
        ReminderPlanner.plan(titles.map { snapshot($0, due: "2026-11-20", offsets: [1]) }, now: noon("2026-11-02"), calendar: calendar)
    }

    @Test func asksForPermissionOnlyInContext() async {
        let center = FakeNotificationCenter(status: .notDetermined)
        let reconciler = NotificationReconciler(client: center)

        await reconciler.apply(plan(["A"]), badgeCount: 0, allowPermissionPrompt: false)
        #expect(await center.promptCount == 0)

        await reconciler.apply([], badgeCount: 0, allowPermissionPrompt: true)
        #expect(await center.promptCount == 0, "Nothing to remind about, nothing to ask")

        let outcome = await reconciler.apply(plan(["A"]), badgeCount: 2, allowPermissionPrompt: true)
        #expect(await center.promptCount == 1)
        #expect(outcome.authorization == .authorized)
        #expect(await center.pendingReminders.count == 1)
        #expect(await center.badge == 2)
    }

    @Test func diffsAgainstWhatIsPending() async {
        let first = plan(["A", "B"])
        let center = FakeNotificationCenter(status: .authorized)
        let reconciler = NotificationReconciler(client: center)
        await reconciler.apply(first, badgeCount: 0, allowPermissionPrompt: false)

        let unchanged = await reconciler.apply(first, badgeCount: 0, allowPermissionPrompt: false)
        #expect(unchanged.added == 0 && unchanged.removed == 0)

        let renamed = await reconciler.apply([first[0]], badgeCount: 0, allowPermissionPrompt: false)
        #expect(renamed.removed == 1)
        #expect(await center.pendingReminders.count == 1)
    }

    @Test func leavesOtherAppsRequestsAlone() async {
        let center = FakeNotificationCenter(status: .authorized, pending: [PendingReminder(identifier: "someone-else", fingerprint: nil)])
        await NotificationReconciler(client: center).apply([], badgeCount: 0, allowPermissionPrompt: false)
        #expect(await center.pendingReminders["someone-else"] != nil)
    }

    @Test func deniedPermissionClearsOurRequests() async {
        let stale = PendingReminder(identifier: "obligation.\(UUID().uuidString.lowercased()).d1", fingerprint: "x")
        let center = FakeNotificationCenter(status: .denied, pending: [stale])
        await NotificationReconciler(client: center).apply(plan(["A"]), badgeCount: 0, allowPermissionPrompt: true)
        #expect(await center.pendingReminders.isEmpty)
        #expect(await center.promptCount == 0)
    }
}

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    @Test func protectedItemsAreRedactedAndOrderFollowsAttention() throws {
        let digest = AttentionModel.digest([
            snapshot("Analize", kind: .health, due: "2026-11-03", asset: (UUID(), "Profil medical"), isSensitive: true),
            snapshot("ITP", kind: .legal, due: "2026-11-05", asset: (UUID(), "VW Golf")),
        ], now: noon("2026-11-02"), calendar: .bucharest)
        let widget = WidgetSnapshot.make(from: digest, generatedAt: noon("2026-11-02"))
        #expect(widget.items.first?.title == "ITP")
        let hidden = try #require(widget.items.last)
        #expect(hidden.isSensitive)
        #expect(hidden.title != "Analize")
        #expect(hidden.assetName == nil)

        let data = try WidgetSnapshot.encoder().encode(widget)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"dueDate\":\"2026-11-05\""))
        #expect(try WidgetSnapshot.decoder().decode(WidgetSnapshot.self, from: data) == widget)
    }

    @Test func writerSkipsUnchangedContent() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = WidgetSnapshotWriter(directory: directory)
        let snapshot = WidgetSnapshot.make(from: AttentionModel.digest([snapshot("ITP", kind: .legal, due: "2026-11-05")], now: noon("2026-11-02"), calendar: .bucharest))
        #expect(writer.write(snapshot))
        var later = snapshot
        later.generatedAt = later.generatedAt.addingTimeInterval(60)
        #expect(!writer.write(later))
    }
}

@Suite("Deep links")
struct DeepLinkTests {
    @Test func everyRouteRoundTrips() {
        let routes: [AppRoute] = [.home, .radar, .intake, .asset(UUID()), .obligation(UUID()), .category("custom.abc"), .settings(nil), .settings(.backup)]
        for route in routes {
            #expect(DeepLink.route(from: DeepLink.url(for: route)) == route)
        }
    }

    @Test func rejectsOtherSchemesAndMalformedIds() {
        #expect(DeepLink.route(from: URL(string: "https://example.com/asset/1")!) == nil)
        #expect(DeepLink.route(from: URL(string: "dosarcusina://asset/not-a-uuid")!) == nil)
    }

    @MainActor
    @Test func archivesOpenTheBackupScreen() {
        let navigator = AppNavigator()
        #expect(navigator.open(URL(filePath: "/tmp/Backup.dosar")))
        #expect(navigator.pendingRoute == .settings(.backup))
        #expect(navigator.consumeArchiveURL()?.lastPathComponent == "Backup.dosar")
        #expect(navigator.consumeArchiveURL() == nil)
    }
}
