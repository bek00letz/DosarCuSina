import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// "Se repetă" (every so many days, weeks, months or years, from the due day or from when it
/// was done) and "Ora amintirii" (the general time, or one of the deadline's own): the control's
/// rules, its words, and the one action behind each.
@MainActor
@Suite("How a deadline repeats, and its reminder time")
struct RepeatAndReminderTimeTests {
    let calendar = Calendar.bucharest

    // MARK: The control's rules

    @Test(arguments: [
        RecurrenceRule.none,
        .interval(.days(3), anchor: .completion),
        .interval(.weeks(2), anchor: .dueDate),
        .interval(.months(1), anchor: .dueDate),
        .interval(.years(2), anchor: .completion),
    ])
    func everyRuleOfItsShapeReadsBackAsItself(rule: RecurrenceRule) throws {
        let choice = try #require(RepeatChoice(rule: rule))
        #expect(choice.rule == rule)
    }

    @Test(arguments: [
        RecurrenceRule.fixedDates([MonthDay(month: 3, day: 31), MonthDay(month: 9, day: 30)]),
        .metric(every: 10_000, unit: .kilometres, fallback: .years(1)),
        .legal(.vehicleITP),
        .unreadable(.object(["type": .string("lunar")])),
    ])
    func rulesOnFixedDatesCountersOrLawAreNotOffered(rule: RecurrenceRule) {
        #expect(RepeatChoice(rule: rule) == nil, "Shown in words only")
        #expect(!RepeatWording.sentence(rule).isEmpty)
    }

    @Test func aNewRepeatStartsAtOneCountedTheWayItsUnitUsuallyIs() {
        let never = RepeatChoice.never
        #expect(never.choosing(.day) == RepeatChoice(frequency: .day, every: 1, anchor: .completion), "Watering: from the day it was done")
        #expect(never.choosing(.week).anchor == .completion)
        #expect(never.choosing(.month) == RepeatChoice(frequency: .month, every: 1, anchor: .dueDate), "A payment: from its due day")
        #expect(never.choosing(.year).anchor == .dueDate)
        #expect(never.rule == .none)
    }

    @Test func changingTheUnitKeepsTheNumberAndWhatItCountsFrom() {
        let everyFortyDays = RepeatChoice(frequency: .day, every: 40, anchor: .dueDate)
        #expect(everyFortyDays.choosing(.week) == RepeatChoice(frequency: .week, every: 40, anchor: .dueDate))
        #expect(everyFortyDays.choosing(.year) == RepeatChoice(frequency: .year, every: RepeatChoice.upperBound(for: .year), anchor: .dueDate),
                "Within the new unit's range")
        #expect(everyFortyDays.choosing(.never).rule == .none)
        #expect(RepeatChoice(frequency: .day, every: 0).every == 1, "Never less than one")
        #expect(RepeatChoice(frequency: .day, every: 500).everyRange.upperBound == 500, "A larger number a rule has stays offered")
    }

    @Test("„+” and „−” step in the unit's own steps: whole weeks in days, then months; inside the range")
    func stepsFollowTheUnit() {
        func up(_ value: Int, _ unit: RecurrenceInterval.Unit = .day, in range: ClosedRange<Int>? = nil) -> Int {
            RepeatChoice.stepped(value, up: true, unit: unit, in: range ?? RepeatChoice(frequency: .init(unit), every: 1).everyRange)
        }
        func down(_ value: Int, _ unit: RecurrenceInterval.Unit = .day) -> Int {
            RepeatChoice.stepped(value, up: false, unit: unit, in: RepeatChoice(frequency: .init(unit), every: 1).everyRange)
        }
        #expect([1, 6, 7, 13, 14, 21, 49, 56, 60, 330, 360].map { up($0) } == [2, 7, 8, 14, 21, 28, 56, 60, 90, 360, 365])
        #expect([2, 8, 14, 21, 28, 56, 60, 90, 365].map { down($0) } == [1, 7, 13, 14, 21, 49, 56, 60, 360])
        #expect(up(40) == 42 && down(40) == 35, "A rule's number between two stops goes to the nearest each way")
        #expect(up(365) == 365 && down(1) == 1, "Never past the range")
        #expect(up(365, in: 1...500) == 500, "A larger number a rule has is a stop too")

        // Every stop of a unit is reached from the one before and goes back to it.
        for unit in [RecurrenceInterval.Unit.day, .week, .month, .year] {
            let range = RepeatChoice(frequency: .init(unit), every: 1).everyRange
            var value = range.lowerBound
            var reached = [value]
            while value < range.upperBound { value = up(value, unit); reached.append(value) }
            #expect(reached.count < 40, "\(unit): a few dozen steps from one to the most, \(reached.count)")
            var back = value
            var returned = [back]
            while back > range.lowerBound { back = down(back, unit); returned.append(back) }
            #expect(returned == reached.reversed(), "\(unit): „−” goes back through the same stops")
        }
        #expect([7, 14, 21, 28].allSatisfy { RepeatChoice.ladder(for: .day).contains($0) }, "Whole weeks in days")
        #expect(RepeatChoice.ladder(for: .week).contains(52) && RepeatChoice.ladder(for: .month).contains(18))
    }

    // MARK: Words

    @Test(arguments: [
        (1, RecurrenceInterval.Unit.day, "În fiecare zi"), (3, .day, "La fiecare 3 zile"), (20, .day, "La fiecare 20 de zile"),
        (1, .week, "În fiecare săptămână"), (2, .week, "La fiecare 2 săptămâni"), (21, .week, "La fiecare 21 de săptămâni"),
        (1, .month, "În fiecare lună"), (6, .month, "La fiecare 6 luni"), (24, .month, "La fiecare 24 de luni"),
        (1, .year, "În fiecare an"), (2, .year, "La fiecare 2 ani"), (20, .year, "La fiecare 20 de ani"),
    ])
    func howOftenTakesRomanianPlurals(count: Int, unit: RecurrenceInterval.Unit, expected: String) {
        #expect(RepeatWording.every(count, unit) == expected)
    }

    @Test func theRuleReadsAsOneSentence() {
        #expect(RepeatWording.sentence(.interval(.days(3), anchor: .completion)) == "La fiecare 3 zile, de la data la care l-ai făcut.")
        #expect(RepeatWording.sentence(.interval(.months(1), anchor: .dueDate)) == "În fiecare lună, de la data termenului.")
        #expect(RepeatWording.sentence(.none) == "Nu se repetă.")
        #expect(RepeatWording.sentence(.fixedDates([MonthDay(month: 9, day: 30), MonthDay(month: 3, day: 31)]))
                == "În fiecare an, pe 31 martie și pe 30 septembrie.")
        #expect(RepeatWording.detail(of: .completion, every: 3, .day) == "Următorul e la 3 zile după ce îl bifezi.")
        #expect(RepeatWording.detail(of: .dueDate, every: 1, .month) == "Următorul e la o lună după termen, oricând îl bifezi.")
    }

    @Test func theReminderTimeSaysWhichOneItIs() {
        #expect(ReminderWording.time(nil, usual: 9 * 60, calendar: calendar) == "Ora obișnuită (09:00)")
        #expect(ReminderWording.time(7 * 60 + 30, usual: 9 * 60, calendar: calendar) == "07:30")
        #expect(ReminderWording.atTime(nil, usual: 9 * 60, calendar: calendar) == "Îți amintesc la ora obișnuită, 09:00.")
        #expect(ReminderWording.atTime(20 * 60, usual: 9 * 60, calendar: calendar) == "Îți amintesc la 20:00.")
    }

    @Test(arguments: [0, 1, 9 * 60, 13 * 60 + 45, 24 * 60 - 1])
    func aPickedTimeIsTheTimeKept(minute: Int) {
        // Including 3:00–4:00, which a spring-forward night doesn't have.
        #expect(ReminderClock.minuteOfDay(of: ReminderClock.moment(minuteOfDay: minute, calendar: calendar), calendar: calendar) == minute)
        #expect(ReminderClock.minuteOfDay(of: ReminderClock.moment(minuteOfDay: 3 * 60 + 30, calendar: calendar), calendar: calendar) == 3 * 60 + 30)
        #expect(ReminderClock.clamped(-5) == 0)
        #expect(ReminderClock.clamped(2_000) == 24 * 60 - 1)
    }

    // MARK: Changing how it repeats

    @Test func changingTheRepeatIsOneUndoableStepAndTheDueDayStays() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-12"), for: nil,
                                        recurrence: .interval(.weeks(1), anchor: .completion))
        let receipt = try actions.setRecurrence(plants, .interval(.days(3), anchor: .completion), startedFrom: plants.recurrence)
        #expect(plants.recurrence == .interval(.days(3), anchor: .completion))
        #expect(plants.dueDay == CalendarDay("2026-11-12"))
        try receipt.undo()
        #expect(plants.recurrence == .interval(.weeks(1), anchor: .completion))
    }

    @Test func aRepeatEditKeepsWhatAnotherDeviceChangedMeanwhile() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let opened = RecurrenceRule.interval(.months(1), anchor: .dueDate)
        let filter = try actions.create(title: "Filtrul de apă", kind: .maintenance, dueDay: CalendarDay("2026-12-01"), for: nil, recurrence: opened)
        // Meanwhile another device counts it from when it was done.
        try actions.setRecurrence(filter, .interval(.months(1), anchor: .completion))
        // This edit, opened before that, made it every two months and left the anchor as read.
        try actions.setRecurrence(filter, .interval(.months(2), anchor: .dueDate), startedFrom: opened)
        #expect(filter.recurrence == .interval(.months(2), anchor: .completion))
    }

    // MARK: Its own reminder time

    @Test func aDeadlineCanHaveItsOwnTimeAndGoBackToTheUsualOne() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let pills = try actions.create(title: "Pastila", kind: .health, dueDay: CalendarDay("2026-11-20"), for: nil,
                                       recurrence: .interval(.days(1), anchor: .completion), reminderMinuteOfDay: 20 * 60)
        #expect(pills.reminderMinuteOfDay == 20 * 60)
        let knownSince = pills.cycleKnownSince

        let receipt = try actions.setReminderTime(pills, minuteOfDay: 7 * 60 + 30, startedFrom: 20 * 60)
        #expect(pills.reminderMinuteOfDay == 7 * 60 + 30)
        #expect(pills.cycleKnownSince == knownSince, "The time doesn't make the cycle new: no catch-up for it")
        try receipt.undo()
        #expect(pills.reminderMinuteOfDay == 20 * 60)

        try actions.setReminderTime(pills, minuteOfDay: nil, startedFrom: 20 * 60)
        #expect(pills.reminderMinuteOfDay == nil, "Back to the general time")
        try actions.setReminderTime(pills, minuteOfDay: 5_000, startedFrom: nil)
        #expect(pills.reminderMinuteOfDay == 24 * 60 - 1)
    }

    @Test func aTimeEditKeepsATimeChangedMeanwhileWhenItLeftItAsRead() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-12-05"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate), reminderMinuteOfDay: 10 * 60)
        try actions.setReminderTime(rent, minuteOfDay: 11 * 60, startedFrom: 10 * 60) // another device
        try actions.setReminderTime(rent, minuteOfDay: 10 * 60, startedFrom: 10 * 60) // an editor that changed nothing
        #expect(rent.reminderMinuteOfDay == 11 * 60)
        try actions.setReminderTime(rent, minuteOfDay: 8 * 60, startedFrom: 10 * 60)
        #expect(rent.reminderMinuteOfDay == 8 * 60, "What the person changed is theirs")
    }

    @Test func aUsualDeadlineTakesItsOwnTimeToo() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf 2018", template: template, values: FieldValues())
        let blueprint = try #require(template.blueprints.first { $0.key == "vehicle.itp" })
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let deadline = try actions.create(from: blueprint, for: car, firstDue: CalendarDay("2027-03-01"), reminderMinuteOfDay: 18 * 60)
        #expect(deadline.reminderMinuteOfDay == 18 * 60)
    }

    @Test func remindersComeAtItsOwnTimeAndTheGeneralTimeReachesTheRest() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let pills = try actions.create(title: "Pastila", kind: .routine, dueDay: CalendarDay("2026-11-12"), for: nil,
                                       recurrence: .interval(.days(1), anchor: .completion), reminders: ReminderProfile(leadDays: [0], consequence: .comfort),
                                       reminderMinuteOfDay: 21 * 60)
        let plants = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-12"), for: nil,
                                        recurrence: .interval(.days(3), anchor: .completion), reminders: ReminderProfile(leadDays: [0], consequence: .comfort))
        let snapshots = try ObligationSnapshot.fetchAll(in: context, calendar: calendar)

        for usual in [9 * 60, 7 * 60] {
            let plan = ReminderPlanner.plan(snapshots, now: noon("2026-11-10"), calendar: calendar, defaultMinuteOfDay: usual)
            let pillsFire = try #require(plan.first { $0.obligationId == pills.id }).fireDate
            let plantsFire = try #require(plan.first { $0.obligationId == plants.id }).fireDate
            #expect(pillsFire == CalendarDay("2026-11-12").moment(atMinute: 21 * 60, in: calendar), "Its own time, whatever the general one")
            #expect(plantsFire == CalendarDay("2026-11-12").moment(atMinute: usual, in: calendar), "The general time, as it is now")
        }
    }

    // MARK: The reminder settings

    @Test func leadsLongerThanTheRepeatAreNotOfferedAndOneKeptSaysWhy() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try actions.create(title: "Udat plantele", kind: .routine, dueDay: CalendarDay("2026-11-13"), for: nil,
                                        recurrence: .interval(.days(3), anchor: .completion),
                                        reminders: ReminderProfile(leadDays: [7, 1, 0], consequence: .comfort))
        let settings = ReminderSettings(obligation: plants, in: context)
        #expect(settings.leadRows == [7, 1, 0], "A week only because it is kept; two weeks and the months aren't offered")
        #expect(!settings.fits(7))
        #expect(settings.fits(1) && settings.fits(0))
        #expect(settings.cycleProfile.leadDays == [1, 0], "The sentence says what reminds")
    }
}
