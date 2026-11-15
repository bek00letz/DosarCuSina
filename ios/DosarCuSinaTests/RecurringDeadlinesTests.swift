import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A repeating deadline end to end, for every unit and both ways of counting: what "Gata"
/// moves it to (in the app and from outside it), what a snooze and a late or early completion
/// do, the reminders of the next cycle (at its own time, with leads no longer than the repeat),
/// and what Urmează and the widget show.
@MainActor
@Suite("Recurring deadlines, end to end")
struct RecurringDeadlinesTests {
    let calendar = Calendar.bucharest

    /// Due 10 November 2026, done a day early, on the day or five days late.
    @Test(arguments: [
        // every, unit, done, from its due day, from when it was done
        (3, RecurrenceInterval.Unit.day, "2026-11-09", "2026-11-13", "2026-11-12"),
        (3, .day, "2026-11-10", "2026-11-13", "2026-11-13"),
        (3, .day, "2026-11-15", "2026-11-13", "2026-11-18"),
        (2, .week, "2026-11-09", "2026-11-24", "2026-11-23"),
        (2, .week, "2026-11-15", "2026-11-24", "2026-11-29"),
        (1, .month, "2026-11-09", "2026-12-10", "2026-12-09"),
        (1, .month, "2026-11-15", "2026-12-10", "2026-12-15"),
        (1, .year, "2026-11-09", "2027-11-10", "2027-11-09"),
        (1, .year, "2026-11-15", "2027-11-10", "2027-11-15"),
    ])
    func gataMovesTheNextDueDayByHowItCounts(every: Int, unit: RecurrenceInterval.Unit, done: String, fromDue: String, fromDone: String) throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon(done) })
        let interval = RecurrenceInterval(every: every, unit: unit)
        let series = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-11-10"), for: nil,
                                        recurrence: .interval(interval, anchor: .dueDate))
        let chore = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-10"), for: nil,
                                       recurrence: .interval(interval, anchor: .completion))
        try actions.complete(series)
        try actions.complete(chore)
        #expect(series.dueDay == CalendarDay(fromDue), "From its due day: the series stays, whenever it was done")
        #expect(chore.dueDay == CalendarDay(fromDone), "From the day it was done")
        #expect(series.status == .active && chore.status == .active)
    }

    @Test func everyFewMonthsKeepsTheMonthsLastDay() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-12-01") })
        let tax = try actions.create(title: "Rata", kind: .payment, dueDay: CalendarDay("2026-12-31"), for: nil,
                                     recurrence: .interval(.months(2), anchor: .dueDate))
        for expected in ["2027-02-28", "2027-04-30", "2027-06-30", "2027-08-31", "2027-10-31", "2027-12-31"] {
            try actions.complete(tax)
            #expect(tax.dueDay == CalendarDay(expected))
        }
    }

    @Test func countedFromWhenItWasDoneAMonthKeepsNoSeriesDay() throws {
        var day = "2027-01-31"
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon(day) })
        let filter = try actions.create(title: "Filtrul", kind: .maintenance, dueDay: CalendarDay("2027-01-31"), for: nil,
                                        recurrence: .interval(.months(1), anchor: .completion))
        try actions.complete(filter)
        #expect(filter.dueDay == CalendarDay("2027-02-28"))
        day = "2027-02-28"
        try actions.complete(filter)
        #expect(filter.dueDay == CalendarDay("2027-03-28"), "It counts from the 28th, the day it was done")
    }

    @Test func aNewRuleStartsANewSeries() throws {
        var day = "2027-01-05"
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon(day) })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2027-01-05"), for: nil,
                                      recurrence: .interval(.days(10), anchor: .dueDate))
        try actions.complete(rent)
        day = "2027-01-15"
        try actions.complete(rent)
        #expect(rent.dueDay == CalendarDay("2027-01-25"))
        try actions.setRecurrence(rent, .interval(.months(1), anchor: .dueDate))
        day = "2027-01-25"
        try actions.complete(rent)
        #expect(rent.dueDay == CalendarDay("2027-02-25"), "Monthly from the 25th, not from the 5th the 10-day steps began on")
    }

    @Test func aSnoozeDoesntMoveTheSeries() throws {
        var now = noon("2026-12-03")
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { now })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-12-05"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate))
        let plants = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-12-05"), for: nil,
                                        recurrence: .interval(.weeks(1), anchor: .completion))
        try actions.snooze(rent, days: 7)
        try actions.snooze(plants, days: 7)
        now = noon("2026-12-09")
        try actions.complete(rent)
        try actions.complete(plants)
        #expect(rent.dueDay == CalendarDay("2027-01-05"))
        #expect(plants.dueDay == CalendarDay("2026-12-16"), "From the day it was done, not from when the snooze ended")
        #expect(rent.snoozedUntil == nil && plants.snoozedUntil == nil)
    }

    /// From its due day every cycle is its own (a month's rent is still owed after the one
    /// before was paid late): one "Gata" closes one cycle. From the day it was done it is
    /// never late again after "Gata".
    @Test func anOverdueDeadlineClosesOneCycleAtATime() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-20") })
        let bins = try actions.create(title: "Gunoiul", kind: .routine, dueDay: CalendarDay("2026-11-02"), for: nil,
                                      recurrence: .interval(.weeks(1), anchor: .dueDate))
        let plants = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-02"), for: nil,
                                        recurrence: .interval(.weeks(1), anchor: .completion))
        try actions.complete(bins)
        try actions.complete(plants)
        #expect(bins.dueDay == CalendarDay("2026-11-09"), "The next cycle, still late")
        #expect(plants.dueDay == CalendarDay("2026-11-27"))
    }

    // MARK: From outside the app

    @Test(arguments: OutsideSurface.allCases)
    func gataFromOutsideCountsFromTheDayItWasDone(surface: OutsideSurface) async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let created = noon("2026-11-08")
        let plants = try ObligationActions(context: context, calendar: calendar, now: { created })
            .create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-10"), for: nil,
                    recurrence: .interval(.days(3), anchor: .completion))
        let tapped = noon("2026-11-10")
        let applied = noon("2026-11-12")
        let request = OutsideRequest(obligationId: plants.id, cycle: CalendarDay("2026-11-10"), action: .complete, surface: surface,
                                     actedAt: surface == .widget ? tapped : nil)
        switch surface {
        case .widget:
            // Left for the app on 10 November, applied when the app opens two days later.
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let queue = WidgetCompletionQueue(fileURL: folder.appending(path: WidgetCompletionQueue.fileName))
            queue.enqueue(WidgetCompletion(obligationId: plants.id, dueDay: "2026-11-10", requestedAt: tapped))
            IntentEngine.applyQueuedWidgetCompletions(queue: queue, in: context, failures: OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)"),
                                                      calendar: calendar, now: { applied })
        case .notification, .shortcut:
            try IntentEngine.apply(request, in: context, calendar: calendar, now: { tapped })
        }
        #expect(plants.dueDay == CalendarDay("2026-11-13"), "Three days after it was done, not after the app opened")
        #expect(plants.history.first.map { CalendarDay($0.occurredAt, calendar: calendar) } == CalendarDay("2026-11-10"))
    }

    // MARK: Reminders of the next cycle

    @Test func theNextCycleRemindsAtItsOwnTime() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-10"), for: nil,
                                        recurrence: .interval(.days(3), anchor: .completion),
                                        reminders: ReminderProfile(leadDays: [1, 0], consequence: .comfort), reminderMinuteOfDay: 19 * 60 + 30)
        try actions.complete(plants)
        let plan = ReminderPlanner.plan(try ObligationSnapshot.fetchAll(in: context, calendar: calendar), now: noon("2026-11-10"), calendar: calendar)
            .filter { $0.obligationId == plants.id }
        #expect(plan.map(\.fireDate) == [CalendarDay("2026-11-12").moment(atMinute: 19 * 60 + 30, in: calendar),
                                         CalendarDay("2026-11-13").moment(atMinute: 19 * 60 + 30, in: calendar)])
        #expect(plan.allSatisfy { $0.cycle == CalendarDay("2026-11-13") })
    }

    /// A week's warning on something done every 3 days would fall before the cycle began: it is
    /// left out of the cycle, so it never fires in the past, never brings a catch-up and never
    /// keeps the deadline urgent. The leads stay stored for a longer repeat.
    @Test func leadsLongerThanTheRepeatAreLeftOut() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try actions.create(title: "Udat plantele", kind: .maintenance, dueDay: CalendarDay("2026-11-10"), for: nil,
                                        recurrence: .interval(.days(3), anchor: .completion),
                                        reminders: ReminderProfile(leadDays: [14, 7, 1, 0], consequence: .comfort))
        try actions.complete(plants)
        #expect(plants.dueDay == CalendarDay("2026-11-13"))
        #expect(plants.reminders.leadDays == [14, 7, 1, 0], "Stored as the person chose them")
        #expect(plants.cycleReminders.leadDays == [1, 0])

        let snapshots = try ObligationSnapshot.fetchAll(in: context, calendar: calendar)
        let plan = ReminderPlanner.plan(snapshots, now: noon("2026-11-10"), calendar: calendar).filter { $0.obligationId == plants.id }
        #expect(plan.map(\.identifier).map { $0.split(separator: ".").last.map(String.init) } == ["d1", "d0"], "No week's warning, no catch-up")

        let soon = try #require(snapshots.first { $0.id == plants.id })
        #expect(AttentionModel.entry(for: soon, today: CalendarDay("2026-11-11"), calendar: calendar).urgency == .upcoming,
                "Not urgent the day after it was done")
        #expect(AttentionModel.entry(for: soon, today: CalendarDay("2026-11-12"), calendar: calendar).urgency == .soon)

        try actions.setRecurrence(plants, .interval(.months(1), anchor: .completion))
        #expect(plants.cycleReminders.leadDays == [14, 7, 1, 0], "A longer repeat uses them all again")
    }

    @Test func aCycleNoLeadFitsRemindsOnTheDay() {
        let profile = ReminderProfile(leadDays: [7, 2], consequence: .comfort)
        let daily = profile.forCycle(due: CalendarDay("2026-11-11"), rule: .interval(.days(1), anchor: .completion), calendar: calendar)
        #expect(daily.leadDays == [0], "Never silent")
        let monthly = ReminderProfile(leadDays: [30, 14, 0], consequence: .financial)
            .forCycle(due: CalendarDay("2026-03-31"), rule: .interval(.months(1), anchor: .dueDate), calendar: calendar)
        #expect(monthly.leadDays == [14, 0], "A month before a monthly deadline is the one before's due day")
        let yearly = ReminderProfile(leadDays: [60, 30, 7], consequence: .legal)
        #expect(yearly.forCycle(due: CalendarDay("2027-05-20"), rule: .interval(.years(1), anchor: .completion), calendar: calendar) == yearly)
        #expect(yearly.forCycle(due: CalendarDay("2027-05-20"), rule: .none, calendar: calendar) == yearly, "A one-off keeps every lead")
        let taxes = ReminderProfile(leadDays: [200, 30], consequence: .financial)
            .forCycle(due: CalendarDay("2027-03-31"), rule: .fixedDates([MonthDay(month: 3, day: 31), MonthDay(month: 9, day: 30)]), calendar: calendar)
        #expect(taxes.leadDays == [30], "Not before the installment before")
    }

    // MARK: What Urmează and the widget show

    @Test func urmeazaAndTheWidgetShowTheNextDay() throws {
        let context = try makeContext()
        let now = noon("2026-11-10")
        let actions = ObligationActions(context: context, calendar: calendar, now: { now })
        let plants = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-10"), for: nil,
                                        recurrence: .interval(.days(3), anchor: .completion))
        try actions.complete(plants)
        let snapshots = try ObligationSnapshot.fetchForOutside(in: context, calendar: calendar)
        let digest = AttentionModel.digest(snapshots, now: noon("2026-11-12"), calendar: calendar)
        let shown = (digest.now + digest.soon.flatMap(\.entries)).map(\.obligation)
        #expect(shown.first { $0.id == plants.id }?.dueDay == CalendarDay("2026-11-13"))
        let feed = WidgetFeed.make(from: snapshots, now: noon("2026-11-12"), calendar: calendar)
        #expect(feed.items.first { $0.obligationId == plants.id }?.dueDate == CalendarDay("2026-11-13"))
    }
}
