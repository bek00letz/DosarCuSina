import Foundation
import Testing
@testable import DosarCuSina

/// One month arithmetic: `CalendarDay.adding(months:dayOfMonth:calendar:)` and
/// `daysInMonth(calendar:)`, in the app's calendar. Repeating deadlines, reminder leads,
/// urgency's travel cut-off and the lengths capture reads off a page all move a day by
/// months there, so month ends, leap days and the day a series keeps come out the same
/// everywhere. The cases that pinned `CadenceCalculator`'s own month table (removed) are
/// kept here with the same days in and out.
@Suite("One month arithmetic")
struct MonthArithmeticTests {
    static let utc = Calendar.dosar(in: TimeZone(identifier: "UTC") ?? .gmt)

    /// Zones from the furthest ahead to the furthest behind: days alone don't depend on one.
    static let zones = ["UTC", "Europe/Bucharest", "Pacific/Kiritimati", "Pacific/Pago_Pago", "America/Sao_Paulo"]
        .compactMap(TimeZone.init(identifier:))
        .map { Calendar.dosar(in: $0) }

    // MARK: A month's length

    @Test(arguments: [2024, 2028, 2032, 2000, 2400])
    func februaryHas29DaysInALeapYear(year: Int) {
        #expect(CalendarDay(year: year, month: 2, day: 1).daysInMonth(calendar: Self.utc) == 29)
        #expect(CalendarDay(validYear: year, month: 2, day: 29) != nil)
        #expect(MonthDay(month: 2, day: 29).day(inYear: year, calendar: Self.utc) == CalendarDay(year: year, month: 2, day: 29))
    }

    @Test(arguments: [2025, 2026, 2027, 1900, 2100])
    func februaryHas28DaysInACommonYear(year: Int) {
        #expect(CalendarDay(year: year, month: 2, day: 1).daysInMonth(calendar: Self.utc) == 28)
        #expect(CalendarDay(validYear: year, month: 2, day: 29) == nil)
        #expect(MonthDay(month: 2, day: 29).day(inYear: year, calendar: Self.utc) == CalendarDay(year: year, month: 2, day: 28))
    }

    @Test func everyMonthHasItsLengthInEveryTimeZone() {
        let common = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let leap = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        for calendar in Self.zones {
            for month in 1...12 {
                #expect(CalendarDay(year: 2026, month: month, day: 15).daysInMonth(calendar: calendar) == common[month - 1])
                #expect(CalendarDay(year: 2028, month: month, day: 15).daysInMonth(calendar: calendar) == leap[month - 1])
                #expect(CalendarDay(validYear: 2026, month: month, day: common[month - 1]) != nil)
                #expect(CalendarDay(validYear: 2026, month: month, day: common[month - 1] + 1) == nil)
            }
        }
        #expect(CalendarDay(year: 2026, month: 3, day: 1).daysInMonth() == 31)
    }

    // MARK: Month ends

    @Test func aMonthLaterIsTheSameDayOrTheMonthsLastDay() {
        let utc = Self.utc
        #expect(CalendarDay("2026-01-31").adding(months: 1, calendar: utc) == CalendarDay("2026-02-28"))
        #expect(CalendarDay("2024-01-31").adding(months: 1, calendar: utc) == CalendarDay("2024-02-29"))
        #expect(CalendarDay("2026-03-31").adding(months: 1, calendar: utc) == CalendarDay("2026-04-30"))
        #expect(CalendarDay("2026-05-31").adding(months: 1, calendar: utc) == CalendarDay("2026-06-30"))
        #expect(CalendarDay("2026-08-31").adding(months: 1, calendar: utc) == CalendarDay("2026-09-30"))
        #expect(CalendarDay("2026-10-31").adding(months: 1, calendar: utc) == CalendarDay("2026-11-30"))
        #expect(CalendarDay("2026-12-31").adding(months: 2, calendar: utc) == CalendarDay("2027-02-28"))
        #expect(CalendarDay("2026-05-15").adding(months: 0, calendar: utc) == CalendarDay("2026-05-15"))
    }

    @Test func aMonthEarlierClampsTheSameWay() {
        #expect(CalendarDay("2026-03-31").adding(months: -1) == CalendarDay("2026-02-28"))
        #expect(CalendarDay("2024-03-31").adding(months: -1) == CalendarDay("2024-02-29"))
        #expect(CalendarDay("2026-01-31").adding(months: -2) == CalendarDay("2025-11-30"))
        #expect(CalendarDay("2027-08-31").adding(months: -6) == CalendarDay("2027-02-28"))
        #expect(CalendarDay("2028-08-31").adding(months: -6) == CalendarDay("2028-02-29"))
    }

    @Test func the29thOfFebruaryAYearLaterIsThe28thUnlessItIsALeapYear() {
        let leapDay = CalendarDay("2024-02-29")
        #expect(RecurrenceEngine.add(.years(1), to: leapDay, calendar: Self.utc) == CalendarDay("2025-02-28"))
        #expect(RecurrenceEngine.add(.years(2), to: leapDay, calendar: Self.utc) == CalendarDay("2026-02-28"))
        #expect(RecurrenceEngine.add(.years(3), to: leapDay, calendar: Self.utc) == CalendarDay("2027-02-28"))
        #expect(RecurrenceEngine.add(.years(4), to: leapDay, calendar: Self.utc) == CalendarDay("2028-02-29"))
        #expect(RecurrenceEngine.add(.years(8), to: leapDay, calendar: Self.utc) == CalendarDay("2032-02-29"))
        #expect(RecurrenceEngine.add(.years(76), to: leapDay, calendar: Self.utc) == CalendarDay("2100-02-28"))
        #expect(RecurrenceEngine.add(.years(1), to: CalendarDay("2025-02-28"), dayOfMonth: 29, calendar: Self.utc) == CalendarDay("2026-02-28"))
        #expect(RecurrenceEngine.add(.years(3), to: CalendarDay("2025-02-28"), dayOfMonth: 29, calendar: Self.utc) == CalendarDay("2028-02-29"))
    }

    @Test func daysWeeksMonthsAndYearsMoveADeadline() {
        let start = CalendarDay("2026-05-01")
        #expect(RecurrenceEngine.add(.days(30), to: start, calendar: Self.utc) == CalendarDay("2026-05-31"))
        #expect(RecurrenceEngine.add(.weeks(2), to: start, calendar: Self.utc) == CalendarDay("2026-05-15"))
        #expect(RecurrenceEngine.add(.months(3), to: start, calendar: Self.utc) == CalendarDay("2026-08-01"))
        #expect(RecurrenceEngine.add(.years(2), to: start, calendar: Self.utc) == CalendarDay("2028-05-01"))
        // No days or weeks leaves the day where it is.
        #expect(RecurrenceEngine.add(.days(0), to: start) == start)
        #expect(RecurrenceEngine.add(.weeks(0), to: start) == start)
    }

    // MARK: The day a series keeps

    @Test func aSeriesOnThe31stLandsOnEveryMonthsLastDay() {
        var due = CalendarDay("2026-01-31")
        var landed: [CalendarDay] = []
        for _ in 1...12 {
            due = RecurrenceEngine.add(.months(1), to: due, dayOfMonth: 31)
            landed.append(due)
        }
        let expected = ["2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31", "2026-06-30", "2026-07-31",
                        "2026-08-31", "2026-09-30", "2026-10-31", "2026-11-30", "2026-12-31", "2027-01-31"].map { CalendarDay($0) }
        #expect(landed == expected)
    }

    @Test func aSeriesOnThe30thComesBackAfterFebruary() {
        let february = RecurrenceEngine.add(.months(1), to: CalendarDay("2028-01-30"), dayOfMonth: 30)
        #expect(february == CalendarDay("2028-02-29"))
        #expect(RecurrenceEngine.add(.months(1), to: february, dayOfMonth: 30) == CalendarDay("2028-03-30"))
        // Without the series' day, the clamped day carries forward.
        #expect(RecurrenceEngine.add(.months(1), to: february) == CalendarDay("2028-03-29"))
        // No months to add moves the day within its own month.
        #expect(CalendarDay("2026-02-01").adding(months: 0, dayOfMonth: 31) == CalendarDay("2026-02-28"))
    }

    // MARK: One path

    /// A repeating deadline, a reminder lead counted back, urgency's travel cut-off and a
    /// length read off a page agree on every day, in every time zone.
    @Test func everySurfaceMovesADayByMonthsTheSameWay() {
        let starts = ["2026-01-31", "2024-01-31", "2024-02-29", "2026-03-31", "2026-08-31", "2026-12-31", "2026-05-15"].map { CalendarDay($0) }
        for calendar in Self.zones {
            for start in starts {
                for months in [1, 6, 12, 24] {
                    let expected = start.adding(months: months, calendar: calendar)
                    #expect(RecurrenceEngine.add(.months(months), to: start, calendar: calendar) == expected)
                    #expect(start.printed(addingMonths: months) == expected)
                    if months % 12 == 0 {
                        #expect(RecurrenceEngine.add(.years(months / 12), to: start, calendar: calendar) == expected)
                    }
                    let back = start.adding(months: -months, calendar: calendar)
                    #expect(ReminderLead(days: months * 30).day(before: start, calendar: calendar) == back)
                    #expect(start.printed(addingMonths: -months) == back)
                }
                let rule = UrgencyRule(graceDays: 0, firstLeadDays: 30, maxWindowDays: 30, travelMarginDays: 180)
                #expect(rule.travelCutoff(before: start, calendar: calendar) == start.adding(months: -6, calendar: calendar))
            }
        }
    }
}
