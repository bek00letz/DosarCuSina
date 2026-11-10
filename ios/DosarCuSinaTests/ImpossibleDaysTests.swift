import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A day kept as written that the calendar doesn't have ("2026-02-30", from an older backup)
/// is never rolled over into the next month: it shows with its own numbers, counts and reminds
/// as its month's last day, and the repair list offers that day, asking first. Every value is a
/// placeholder.
@MainActor
@Suite("Days the calendar doesn't have")
struct ImpossibleDaysTests {
    @Test("Which days the calendar has", arguments: [
        ("2026-02-28", true), ("2024-02-29", true), ("2026-02-29", false), ("2026-02-30", false),
        ("2026-04-31", false), ("2026-12-31", true), ("2026-01-31", true),
    ])
    func whichDaysAreOnTheCalendar(iso: String, exists: Bool) {
        #expect(CalendarDay(iso).isOnCalendar == exists, "\(iso)")
    }

    @Test("A missing day becomes its month's last, never the next month's", arguments: [
        ("2026-02-30", "2026-02-28"), ("2024-02-30", "2024-02-29"), ("2026-02-29", "2026-02-28"),
        ("2026-04-31", "2026-04-30"), ("2026-03-15", "2026-03-15"),
    ])
    func aMissingDayIsItsMonthsLast(iso: String, expected: String) {
        let day = CalendarDay(iso)
        #expect(day.onCalendar == CalendarDay(expected))
        for calendar in [Calendar.bucharest, Calendar.dosar(in: .gmt), Calendar.dosar(in: TimeZone(identifier: "Pacific/Kiritimati") ?? .gmt)] {
            #expect(CalendarDay(day.startDate(in: calendar), calendar: calendar) == CalendarDay(expected), "\(iso) in \(calendar.timeZone.identifier)")
            #expect(CalendarDay(day.noonDate(in: calendar), calendar: calendar) == CalendarDay(expected))
        }
        let fire = ReminderPlanner.fireDate(day: day, minuteOfDay: 9 * 60, calendar: .bucharest)
        #expect(CalendarDay(fire, calendar: .bucharest) == CalendarDay(expected), "A reminder falls on the month's last day")
        #expect(Calendar.bucharest.component(.hour, from: fire) == 9)
    }

    @Test("Counting from a missing day counts from its month's last")
    func countingFromAMissingDay() {
        let day = CalendarDay("2026-02-30")
        #expect(CalendarDay("2026-02-01").days(to: day, calendar: .bucharest) == 27)
        #expect(day.adding(days: 1, calendar: .bucharest) == CalendarDay("2026-03-01"))
        #expect(day.adding(months: 1, calendar: .bucharest) == CalendarDay("2026-03-30"), "Months keep the day as written")
        #expect(day.daysInMonth(calendar: .bucharest) == 28)
    }

    @Test("A missing day is written with its own numbers")
    func aMissingDayIsWrittenAsItIs() {
        let day = CalendarDay("2026-02-30")
        #expect(DosarFormat.longDay(day) == "30 februarie 2026")
        #expect(DosarFormat.dayMonth(day) == "30 februarie")
        #expect(DosarFormat.day(day).hasPrefix("30 "))
        #expect(DosarFormat.monthYear(day) == "februarie 2026")
        #expect(!DosarFormat.longDay(day).contains("martie"), "Never shown as 2 March")
        #expect(DosarFormat.longDay(CalendarDay("2026-02-28")) == "28 februarie 2026", "A real day is written as before")
        #expect(DosarFormat.longDay(CalendarDay("2026-03-02")) == "2 martie 2026")
    }

    @Test("The repair list offers the month's last day for a missing day", arguments: [
        ("2026-02-30", DayYearsStep.Verdict.missing(lastOfMonth: CalendarDay("2026-02-28"))),
        ("2024-02-30", .missing(lastOfMonth: CalendarDay("2024-02-29"))),
        ("2026-06-31", .missing(lastOfMonth: CalendarDay("2026-06-30"))),
        ("2026-02-28", .possible),
        ("2568-02-30", .unknown),
    ])
    func verdict(iso: String, expected: DayYearsStep.Verdict) {
        #expect(DayYearsStep.verdict(CalendarDay(iso), thisYear: 2026) == expected, "\(iso)")
    }

    @Test("A missing day is listed in plain words, asking first, and fixed once")
    func aMissingDayIsOfferedAsTheMonthsLast() throws {
        let context = try makeContext()
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        let itp = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-02-30"))
        context.insert(itp)
        itp.asset = car
        try UnitOfWork.save(context)
        #expect(itp.dueDay == CalendarDay("2026-02-30"), "Kept as written")

        let list = DataRepairs(context: context, calendar: .bucharest,
                               ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "missing-days-\(UUID().uuidString)")!))
        let found = try list.detect().filter { $0.step == .dayYears }
        try #require(found.count == 1)
        #expect(found[0].isFixable)
        #expect(found[0].message.contains("30 februarie 2026"))
        #expect(found[0].message.contains("28 februarie 2026"))
        #expect(!found[0].message.contains("martie"))
        #expect(itp.dueDay == CalendarDay("2026-02-30"), "Nothing changes before the owner says so")

        try list.apply(found)
        #expect(itp.dueDay == CalendarDay("2026-02-28"))
        #expect(try list.detect().filter { $0.step == .dayYears }.isEmpty, "Found nothing once applied")
    }
}
