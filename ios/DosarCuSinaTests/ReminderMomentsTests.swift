import Foundation
import SwiftData
import Testing
import UIKit
@testable import DosarCuSina

/// When reminders come: one per moment however a deadline's reminders fall together, a time the
/// clocks skip in spring, and the phone's time zone or clock changing while the app runs.
@MainActor
@Suite("When reminders come")
struct ReminderMomentsTests {
    let calendar = Calendar.bucharest

    /// The clock on the wall at `moment` in Bucharest, as "hour:minute" ("4:0").
    private func clock(_ moment: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        return "\(parts.hour ?? -1):\(parts.minute ?? -1)"
    }

    // MARK: One reminder per moment

    @Test func aSnoozeThatEndsOnALeadDayRemindsOnce() {
        // Due 20 November, reminding a week, a day and on the day; on the 17th „Amână 3 zile”.
        let item = snapshot("RCA", kind: .insurance, due: "2026-11-20", offsets: [7, 1, 0], snoozedUntil: CalendarDay("2026-11-20"))
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-17"), calendar: calendar)
        let onTheDay = plan.filter { CalendarDay($0.fireDate, calendar: calendar) == CalendarDay("2026-11-20") }
        #expect(onTheDay.count == 1, "One reminder at 09:00 on the 20th, not the lead and the snooze both")
        #expect(onTheDay.first?.identifier.hasSuffix(".d0") == true, "The cycle's own lead is the one kept")
        #expect(Set(plan.map(\.fireDate)).count == plan.count)
    }

    @Test func aSnoozeThatEndsOnTheFollowUpDayRemindsOnce() {
        let item = snapshot("RCA", kind: .insurance, due: "2026-11-20", offsets: [7, 1, 0], snoozedUntil: CalendarDay("2026-11-21"))
        #expect(item.reminders.followUpAfterLapse)
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-17"), calendar: calendar)
        let dayAfter = plan.filter { CalendarDay($0.fireDate, calendar: calendar) == CalendarDay("2026-11-21") }
        #expect(dayAfter.map(\.identifier).count == 1)
        #expect(dayAfter.first?.identifier.hasSuffix(".\(ReminderPlanner.lapseSuffix)") == true)
    }

    @Test(arguments: 18...24)
    func noSnoozeEverPlansAMomentTwice(snoozedTo day: Int) {
        let item = snapshot("RCA", kind: .insurance, due: "2026-11-20", offsets: [7, 1, 0],
                            snoozedUntil: CalendarDay(year: 2026, month: 11, day: day))
        let plan = ReminderPlanner.plan([item], now: noon("2026-11-17"), calendar: calendar)
        #expect(!plan.isEmpty)
        #expect(Set(plan.map(\.fireDate)).count == plan.count, "Snoozed to \(day) November")
    }

    @Test func twoDeadlinesAtTheSameMinuteKeepTheirOwnReminders() {
        let rca = snapshot("RCA", kind: .insurance, due: "2026-11-20", offsets: [0])
        let itp = snapshot("ITP", kind: .legal, due: "2026-11-20", offsets: [0])
        let plan = ReminderPlanner.plan([rca, itp], now: noon("2026-11-17"), calendar: calendar)
        #expect(plan.filter { CalendarDay($0.fireDate, calendar: calendar) == CalendarDay("2026-11-20") }.count == 2,
                "One per moment is per deadline: each still has its own")
    }

    // MARK: A time the clocks skip

    @Test func aTimeSkippedInSpringIsTheFirstMinuteAfterTheGap() {
        // 28 March 2027 in Romania: 03:00 becomes 04:00.
        let day = CalendarDay("2027-03-28")
        let skipped = day.moment(atMinute: 3 * 60 + 30, in: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: skipped)
        #expect(parts.day == 28 && parts.hour == 4 && parts.minute == 0, "04:00, as iOS does, never 04:30")
        #expect(day.moment(atMinute: 3 * 60, in: calendar) == skipped)
        #expect(clock(day.moment(atMinute: 2 * 60 + 59, in: calendar)) == "2:59")
        #expect(clock(day.moment(atMinute: 9 * 60, in: calendar)) == "9:0")
        // When summer time ends, 03:30 comes twice: the first one.
        let autumn = CalendarDay("2027-10-31").moment(atMinute: 3 * 60 + 30, in: calendar)
        #expect(clock(autumn) == "3:30")
        #expect(calendar.timeZone.isDaylightSavingTime(for: autumn), "The first 03:30, still on summer time")
    }

    @Test func aTimeSkippedByHalfAnHourIsTheFirstMinuteAfterTheGapThatDay() throws {
        // 4 October 2026 on Lord Howe Island: 02:00 becomes 02:30, half an hour skipped.
        let lordHowe = Calendar.dosar(in: try #require(TimeZone(identifier: "Australia/Lord_Howe")))
        let day = CalendarDay("2026-10-04")
        for minute in [2 * 60, 2 * 60 + 15] {
            let skipped = day.moment(atMinute: minute, in: lordHowe)
            let parts = lordHowe.dateComponents([.day, .hour, .minute], from: skipped)
            #expect(parts.day == 4 && parts.hour == 2 && parts.minute == 30, "02:30 that day, never the next day")
        }
        let before = lordHowe.dateComponents([.day, .hour, .minute], from: day.moment(atMinute: 60 + 59, in: lordHowe))
        #expect(before.day == 4 && before.hour == 1 && before.minute == 59)
    }

    @Test func aReminderAtASkippedTimeIsPlannedForThatMinute() throws {
        var item = snapshot("Vaccin", kind: .health, due: "2027-03-28", offsets: [0])
        item.reminderMinuteOfDay = 3 * 60 + 30
        let plan = ReminderPlanner.plan([item], now: noon("2027-03-20"), calendar: calendar)
        let fire = try #require(plan.first?.fireDate)
        #expect(clock(fire) == "4:0")
    }

    @Test func thePageSaysWhenATimeIsSkipped() throws {
        let note = try #require(ReminderWording.springForward(3 * 60 + 30, now: noon("2026-11-17"), calendar: calendar))
        #expect(note == "Pe 28 martie, când se trece la ora de vară, îți amintesc la 04:00.")
        #expect(ReminderWording.springForward(9 * 60, now: noon("2026-11-17"), calendar: calendar) == nil)
        let skipped = try #require(ReminderClock.springForward(minuteOfDay: 3 * 60, after: noon("2026-11-17"), calendar: calendar))
        #expect(skipped.day == CalendarDay("2027-03-28") && skipped.remindsAt == 4 * 60)
        var tokyo = Calendar.bucharest
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        #expect(ReminderClock.springForward(minuteOfDay: 3 * 60 + 30, after: noon("2026-11-17"), calendar: tokyo) == nil,
                "A time zone that never moves its clocks says nothing")
    }

    // MARK: The phone's time changing

    @Test func theDayTheTimeZoneAndTheClockChangingEachRunAPass() {
        let names = SideEffectsCoordinator.timeChanges
        #expect(names.contains(.NSCalendarDayChanged))
        #expect(names.contains(.NSSystemTimeZoneDidChange))
        #expect(names.contains(UIApplication.significantTimeChangeNotification))
    }

    @Test func aPassPlansInTheTimeZoneThePhoneIsInThen() async throws {
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        try TemplateStore(context: context).installBuiltIns()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
        try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-20"), for: nil)

        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let center = FakeNotificationCenter(status: .authorized)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        var zone = TimeZone(identifier: "Europe/Bucharest") ?? .gmt
        let coordinator = SideEffectsCoordinator(
            container: container, notificationClient: center, widgetWriter: WidgetSnapshotWriter(directory: directory),
            preferences: AppPreferences(defaults: defaults),
            calendar: { .dosar(in: zone) },
            now: { noon("2026-11-02") }
        )
        await coordinator.reconcileNow()
        let before = await center.pendingReminders
        #expect(!before.isEmpty)

        zone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        await coordinator.reconcileNow()
        let after = await center.pendingReminders
        #expect(Set(after.keys) == Set(before.keys), "The same reminders")
        for (identifier, reminder) in after {
            #expect(reminder.fingerprint != before[identifier]?.fingerprint, "Planned again for 09:00 where the phone is now")
        }
    }
}
