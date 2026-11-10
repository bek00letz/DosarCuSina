import Foundation
import SwiftData
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
            snapshot("RCA", kind: .insurance, due: "2026-11-25", asset: (UUID(), "VW Golf"), offsets: [7, 0], cost: Money(1_200)),
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
            snapshot("Amânat", due: "2026-11-02", snoozedUntil: CalendarDay("2026-11-05")),
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
        #expect(digest.now.allSatisfy { $0.obligation.reminders.consequence.weight >= Consequence.health.weight })
    }
}

@Suite("Reminder profiles")
struct ReminderProfileTests {
    let calendar = Calendar.bucharest
    let today = noon("2026-11-02")

    @Test func aCatVaccineALittleLateIsCalmButAnExpiredRCAIsNot() {
        let vaccine = snapshot("Vaccin pisică", kind: .health, due: "2026-10-31", offsets: [1], consequence: .health, grace: 7)
        let rca = snapshot("RCA", kind: .insurance, due: "2026-11-01", offsets: [30, 7, 0], consequence: .legal, grace: 0)
        let digest = AttentionModel.digest([vaccine, rca], now: today, calendar: calendar)
        let byTitle = Dictionary(uniqueKeysWithValues: digest.now.map { ($0.obligation.title, $0) })
        #expect(byTitle["Vaccin pisică"]?.urgency == .withinGrace)
        #expect(byTitle["RCA"]?.urgency == .overdue)
        #expect(digest.now.first?.obligation.title == "RCA")
        #expect(digest.needsActionCount == 1, "Only the RCA counts on the badge")
    }

    @Test func graceRunsOutIntoOverdue() {
        let vaccine = snapshot("Vaccin", kind: .health, due: "2026-10-20", offsets: [1], consequence: .health, grace: 7)
        let digest = AttentionModel.digest([vaccine], now: today, calendar: calendar)
        #expect(digest.now.first?.urgency == .overdue)
    }

    @Test func leadDaysDecideWhenThingsReachTheRadar() {
        let vignette = snapshot("Rovinietă", kind: .legal, due: "2026-11-12", offsets: [7, 0], consequence: .legal)
        let licence = snapshot("Permis", kind: .renewal, due: "2026-11-25", offsets: [60, 30], consequence: .legal)
        let passport = snapshot("Pașaport", kind: .renewal, due: "2027-03-20", offsets: [180, 60], consequence: .legal)
        let digest = AttentionModel.digest([vignette, licence, passport], now: today, calendar: calendar)
        #expect(digest.now.map(\.obligation.title) == ["Permis"], "The vignette is 10 days out but only needs a week")
        // A month ahead of 1 December is 1 November: 30 days.
        let due = CalendarDay("2026-12-01")
        #expect(ReminderProfile(leadDays: [180, 60], consequence: .legal).urgencyRule.windowDays(before: due, calendar: calendar) == 30)
        #expect(ReminderProfile(leadDays: [7, 0], consequence: .legal).urgencyRule.windowDays(before: due, calendar: calendar) == 7)
        #expect(ReminderProfile(leadDays: [1], consequence: .health).urgencyRule.windowDays(before: due, calendar: calendar) == 1)
    }

    @Test func followUpComesTheDayAfterLapsingAndOnlyWhenAskedFor() {
        let itp = snapshot("ITP", kind: .legal, due: "2026-11-10", offsets: [30, 7], consequence: .legal)
        let itpPlan = ReminderPlanner.plan([itp], now: today, calendar: calendar)
        let lapse = itpPlan.first { $0.identifier.hasSuffix(".\(ReminderPlanner.lapseSuffix)") }
        #expect(lapse.map { CalendarDay($0.fireDate, calendar: calendar) } == CalendarDay("2026-11-11"))
        #expect(lapse?.title == "Depășit: ITP")
        #expect(itpPlan.filter { $0.fireDate > noon("2026-11-11") }.isEmpty, "Then silence")

        let vaccine = snapshot("Vaccin", kind: .health, due: "2026-11-10", offsets: [1], consequence: .health, grace: 7)
        #expect(ReminderPlanner.plan([vaccine], now: today, calendar: calendar).map { CalendarDay($0.fireDate, calendar: calendar) } == [CalendarDay("2026-11-09")],
                "Health and comfort don't follow up by default")

        var turnedOff = itp
        turnedOff.reminders.followUpAfterLapse = false
        #expect(!ReminderPlanner.plan([turnedOff], now: today, calendar: calendar).contains { $0.identifier.hasSuffix(".lapse") })

        var calm = snapshot("Chirie", kind: .payment, due: "2026-11-10", offsets: [0], consequence: .financial, grace: 3)
        calm.reminders.followUpAfterLapse = true
        #expect(ReminderPlanner.plan([calm], now: today, calendar: calendar).last?.title == "Încă de făcut: Chirie")

        let chore = snapshot("Udat", kind: .routine, due: "2026-11-03", offsets: [0], consequence: .comfort, grace: 2)
        #expect(ReminderPlanner.plan([chore], now: today, calendar: calendar).allSatisfy { !$0.isTimeSensitive }, "Comfort never breaks through Focus")
    }

    @Test func completingRemovesThePendingFollowUp() async {
        let id = UUID()
        let open = ObligationSnapshot(id: id, title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-10"),
                                      reminders: ReminderProfile(leadDays: [7], consequence: .legal))
        let center = FakeNotificationCenter(status: .authorized)
        let reconciler = NotificationReconciler(client: center)
        await reconciler.apply(ReminderPlanner.plan([open], now: today, calendar: calendar), badgeCount: 0, allowPermissionPrompt: false)
        let lapseId = ReminderPlanner.identifier(obligationId: id, suffix: ReminderPlanner.lapseSuffix)
        #expect(await center.pendingReminders[lapseId] != nil)

        var done = open
        done.status = .done
        await reconciler.apply(ReminderPlanner.plan([done], now: today, calendar: calendar), badgeCount: 0, allowPermissionPrompt: false)
        #expect(await center.pendingReminders[lapseId] == nil)
    }

    @Test func profilesDefaultTheFollowUpByConsequence() throws {
        #expect(ReminderProfile(leadDays: [7], consequence: .legal).followUpAfterLapse)
        #expect(ReminderProfile(leadDays: [7], consequence: .financial).followUpAfterLapse)
        #expect(!ReminderProfile(leadDays: [7], consequence: .health).followUpAfterLapse)
        #expect(!ReminderProfile(leadDays: [7], consequence: .comfort).followUpAfterLapse)
        let old = #"{"leadDays": [7], "consequence": "legal", "graceDays": 0}"#
        #expect(try JSONDecoder().decode(ReminderProfile.self, from: Data(old.utf8)).followUpAfterLapse)
    }

    @Test func rabiesRemindersFollowTheSpecies() throws {
        let rabies = try #require(BuiltInTemplates.pet.blueprints.first { $0.key == "pet.rabies" })
        var values = FieldValues()
        values["pet.species"] = .text(PetSpecies.dog)
        let dog = rabies.reminders(for: values)
        #expect(dog == ReminderProfile(leadDays: [10, 4], consequence: .legal, graceDays: 0))
        #expect(dog.followUpAfterLapse)
        values["pet.species"] = .text(PetSpecies.cat)
        let cat = rabies.reminders(for: values)
        #expect(cat.leadDays == [1] && cat.graceDays > 0 && !cat.followUpAfterLapse)
    }

    @Test func documentRemindersFollowTheDocumentType() throws {
        let blueprint = try #require(BuiltInTemplates.documents.blueprints.first)
        var values = FieldValues()
        values["document.type"] = .text(DocumentType.passport)
        #expect(blueprint.reminders(for: values).leadDays == [90, 0], "Counted from the day it stops being good for travel")
        #expect(blueprint.reminders(for: values).travelMarginDays == 180)
        values["document.type"] = .text(DocumentType.drivingLicence)
        #expect(blueprint.reminders(for: values).leadDays == [60, 30])
        values["document.type"] = .text(DocumentType.idCard)
        #expect(blueprint.reminders(for: values).leadDays == [90, 30])
        #expect(blueprint.reminders(for: FieldValues()).leadDays == [90, 30])
    }

    @Test func builtInDefaultsMatchHowHardEachRenewalIs() throws {
        func profile(_ template: TemplateDefinition, _ key: String) throws -> ReminderProfile {
            try #require(template.blueprints.first { $0.key == key }).reminders
        }
        #expect(try profile(BuiltInTemplates.vehicle, "vehicle.vignette") == ReminderProfile(leadDays: [7, 0], consequence: .legal))
        #expect(try profile(BuiltInTemplates.vehicle, "vehicle.rca") == ReminderProfile(leadDays: [30, 7, 0], consequence: .legal))
        #expect(try profile(BuiltInTemplates.vehicle, "vehicle.itp") == ReminderProfile(leadDays: [30, 7], consequence: .legal))
        #expect(try profile(BuiltInTemplates.home, "home.buildingTax") == ReminderProfile(leadDays: [14, 1], consequence: .financial))
        #expect(try profile(BuiltInTemplates.subscription, "subscription.contractEnd") == ReminderProfile(leadDays: [30], consequence: .financial, followUpAfterLapse: false))
        #expect(try profile(BuiltInTemplates.subscription, "subscription.renewal").leadDays == [14])
        let catVaccine = try profile(BuiltInTemplates.pet, "pet.vaccine")
        #expect(catVaccine.leadDays == [1] && catVaccine.graceDays > 0)
    }

    @Test func obligationsTakeTheirBlueprintProfileAndCanOverrideIt() throws {
        let profile = ReminderProfile(leadDays: [14], consequence: .financial, graceDays: 2)
        let decoded = try JSONDecoder().decode(ReminderProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }
}

@Suite("Reminder planner")
struct ReminderPlannerTests {
    let calendar = Calendar.bucharest

    @Test func schedulesOnlyFutureOffsetsAtTheChosenTime() {
        let item = snapshot("ITP", kind: .legal, due: "2026-11-10", asset: (UUID(), "VW Golf"), offsets: [30, 7, 1, 0])
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-02"), calendar: calendar, defaultMinuteOfDay: 9 * 60)
        #expect(plan.count == 4)
        #expect(plan.map { CalendarDay($0.fireDate, calendar: calendar) } == [CalendarDay("2026-11-03"), CalendarDay("2026-11-09"), CalendarDay("2026-11-10"), CalendarDay("2026-11-11")])
        #expect(plan.allSatisfy { calendar.component(.hour, from: $0.fireDate) == 9 })
        #expect(plan[2].title == "Azi: ITP")
        #expect(plan[2].isTimeSensitive == true)
        #expect(plan[3].title == "Depășit: ITP", "A legal deadline follows up the next day")
        #expect(plan.first?.isTimeSensitive == false)
        #expect(plan.first?.body.hasPrefix("VW Golf") == true)
    }

    @Test func wallClockTimeSurvivesDaylightSaving() {
        // Romania moves clocks forward on 29 March 2026.
        let item = snapshot("Plată", kind: .payment, due: "2026-03-30", offsets: [2, 0])
        let plan = ReminderPlanner.plan([item], now: noon("2026-03-01"), calendar: calendar, defaultMinuteOfDay: 8 * 60 + 30)
        #expect(plan.count == 3)
        for reminder in plan {
            let parts = calendar.dateComponents([.hour, .minute], from: reminder.fireDate)
            #expect(parts.hour == 8 && parts.minute == 30)
        }
    }

    @Test func protectedCategoriesGetGenericText() {
        let item = snapshot("Colonoscopie", kind: .health, due: "2026-11-03", asset: (UUID(), "Profil medical"), offsets: [1], isSensitive: true)
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-01"), calendar: calendar)
        #expect(!plan.isEmpty)
        for reminder in plan {
            #expect(!reminder.title.contains("Colonoscopie"))
            #expect(!reminder.body.contains("Profil medical"))
        }
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
        let item = snapshot("RCA", kind: .insurance, due: "2026-11-10", offsets: [7, 1, 0], snoozedUntil: CalendarDay("2026-11-08"))
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-03"), calendar: calendar)
        #expect(plan.map(\.identifier).contains { $0.hasSuffix(".snooze") })
        #expect(plan.allSatisfy { $0.fireDate >= CalendarDay("2026-11-08").startDate(in: calendar) })
        #expect(!plan.contains { $0.identifier.hasSuffix(".d7") })
    }

    /// Changed on purpose: the limit used to keep the soonest reminders by time alone,
    /// so a busy household lost a passport's warning months ahead without a sign.
    /// Now every deadline's next reminder comes first, the legal ones before the
    /// rest, and the last place tells the person to open the app.
    @Test func respectsTheSystemLimitByConsequenceThenTime() {
        let now = noon("2026-11-02")
        let legal = (0..<20).map { i in
            snapshot("Legal \(i)", kind: .insurance, due: CalendarDay("2026-12-01").adding(days: i * 15, calendar: calendar).isoString)
        }
        let bills = (0..<30).map { i in
            snapshot("Factură \(i)", kind: .payment, due: CalendarDay("2026-11-04").adding(days: i % 25, calendar: calendar).isoString)
        }
        let chores = (0..<150).map { i in
            snapshot("Udat \(i)", kind: .routine, due: CalendarDay("2026-11-03").adding(days: i % 10, calendar: calendar).isoString)
        }
        let all = legal + bills + chores
        let plan = ReminderPlanner.plan(all, now: now, calendar: calendar)

        #expect(plan.count == ReminderPlanner.defaultLimit)
        for item in legal {
            let next = ReminderPlanner.candidates(for: item, now: now, calendar: calendar, defaultMinuteOfDay: AppPreferences.defaultReminderMinuteOfDay, locale: .dosarDefault)
                .min { $0.fireDate < $1.fireDate }
            #expect(next.map { first in plan.contains { $0.identifier == first.identifier } } == true, "\(item.title) keeps its next reminder")
        }
        let last = plan.last
        #expect(last?.identifier == ReminderPlanner.continueIdentifier, "The list ends with the reminder to open the app")
        #expect(last?.title == "Deschide Dosar cu Șină o clipă")
        let kept = plan.dropLast()
        #expect(kept.map(\.fireDate) == kept.map(\.fireDate).sorted())
        let dropped = all.flatMap {
            ReminderPlanner.candidates(for: $0, now: now, calendar: calendar, defaultMinuteOfDay: AppPreferences.defaultReminderMinuteOfDay, locale: .dosarDefault)
        }.filter { candidate in !plan.contains { $0.identifier == candidate.identifier } }
        let runsOut = dropped.map(\.fireDate).min()
        #expect(runsOut.map { (last?.fireDate ?? .distantFuture) < $0 } == true, "It fires before the first reminder that didn't fit")
    }

    @Test func noOpenTheAppReminderWhenEverythingFits() {
        let items = (0..<5).map { snapshot("O\($0)", due: CalendarDay("2026-11-10").adding(days: $0, calendar: calendar).isoString, offsets: [7, 1, 0]) }
        let plan = ReminderPlanner.plan(items, now: noon("2026-11-02"), calendar: calendar)
        #expect(plan.count == 15)
        #expect(!plan.contains { $0.identifier == ReminderPlanner.continueIdentifier })
        #expect(plan.allSatisfy { $0.cycle != nil && $0.obligationId != nil }, "Every reminder about a deadline carries its cycle")
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

    private(set) var deliveredReminders: [DeliveredReminder] = []

    func deliver(_ reminder: DeliveredReminder) { deliveredReminders.append(reminder) }

    func delivered() async -> [DeliveredReminder] { deliveredReminders }

    func removeDelivered(identifiers: [String]) async {
        deliveredReminders.removeAll { identifiers.contains($0.identifier) }
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
        #expect(await center.pendingReminders.count == plan(["A"]).count)
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
        #expect(renamed.removed == first.count - 1)
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
        let widget = WidgetFeed.make(from: [
            snapshot("Analize", kind: .health, due: "2026-11-03", asset: (UUID(), "Profil medical"), isSensitive: true),
            snapshot("ITP", kind: .legal, due: "2026-11-05", asset: (UUID(), "VW Golf")),
        ], now: noon("2026-11-02"), calendar: .bucharest)
        #expect(widget.items.first?.title == "ITP")
        let hidden = try #require(widget.items.last)
        #expect(hidden.isSensitive)
        #expect(hidden.title != "Analize")
        #expect(hidden.assetName == nil)

        let data = try WidgetFeed.encode(widget)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"dueDate\":\"2026-11-05\""))
        #expect(WidgetFeed.decode(data) == widget)
    }

    @Test func examplesNeverReachWidgetsEvenWhenTheyAreAllThereIs() {
        let onlyExamples = WidgetFeed.make(from: [
            snapshot("RCA exemplu", kind: .insurance, due: "2026-11-01", isExample: true),
            snapshot("ITP exemplu", kind: .legal, due: "2026-11-03", isExample: true),
        ], now: noon("2026-11-02"), calendar: .bucharest)
        #expect(onlyExamples.items.isEmpty)
        #expect(onlyExamples.needsActionCount == 0)

        let mixed = WidgetFeed.make(from: [
            snapshot("RCA exemplu", kind: .insurance, due: "2026-11-01", isExample: true),
            snapshot("ITP", kind: .legal, due: "2026-11-05"),
        ], now: noon("2026-11-02"), calendar: .bucharest)
        #expect(mixed.items.map(\.title) == ["ITP"])
    }

    @Test func writerSkipsUnchangedContent() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = WidgetSnapshotWriter(directory: directory)
        let snapshot = WidgetFeed.make(from: [snapshot("ITP", kind: .legal, due: "2026-11-05")], now: noon("2026-11-02"), calendar: .bucharest)
        #expect(writer.write(snapshot))
        var later = snapshot
        later.generatedAt = later.generatedAt.addingTimeInterval(60)
        #expect(!writer.write(later))
    }
}

@MainActor
@Suite("Side effects with example data")
struct SideEffectsExampleTests {
    @Test func examplesNeverNotifyBadgeOrReachWidgets() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        try ExampleDataService(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).loadExamples()

        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let center = FakeNotificationCenter(status: .authorized)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        let coordinator = SideEffectsCoordinator(
            container: container,
            notificationClient: center,
            widgetWriter: WidgetSnapshotWriter(directory: directory),
            preferences: AppPreferences(defaults: defaults),
            calendar: .bucharest,
            now: { noon("2026-11-02") }
        )
        await coordinator.reconcileNow(allowPermissionPrompt: true)

        #expect(await center.pendingReminders.isEmpty)
        #expect(await center.badge == 0)
        #expect(await center.promptCount == 0)
        let data = try Data(contentsOf: directory.appending(path: WidgetFeed.fileName))
        let widget = try #require(WidgetFeed.decode(data))
        #expect(widget.items.isEmpty)

        // A real obligation next to the examples does reach both.
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-10"), for: nil)
        await coordinator.reconcileNow()
        #expect(await !center.pendingReminders.isEmpty)
        #expect(await center.pendingReminders.keys.allSatisfy { !$0.isEmpty })
        let updated = try #require(WidgetFeed.decode(Data(contentsOf: directory.appending(path: WidgetFeed.fileName))))
        #expect(updated.items.map(\.title) == ["RCA"])
    }
}

@Suite("Deep links")
struct DeepLinkTests {
    @Test func everyRouteRoundTrips() {
        let routes: [AppRoute] = [
            .home, .upcoming, .search, .agenda, .intake, .asset(UUID()), .addVisit(UUID()), .obligation(UUID()), .historyEntry(UUID()), .provider(UUID()), .document(UUID()),
            .category("custom.abc"), .settings(nil), .settings(.backup),
        ]
        for route in routes {
            #expect(DeepLink.route(from: DeepLink.url(for: route)) == route)
        }
    }

    @Test func linksFromEarlierBuildsStillOpen() {
        #expect(DeepLink.route(from: URL(string: "dosarcusina://radar")!) == .upcoming)
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
