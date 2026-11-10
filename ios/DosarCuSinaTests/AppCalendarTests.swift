import Foundation
import Testing
@testable import DosarCuSina

/// One calendar counts the app's days, Gregorian whatever the phone is set to. A test
/// can't switch the process's own calendar, so each check sets what a phone in another
/// calendar would have counted beside what the app's defaults count: the defaults must
/// give the Gregorian answer, and the other calendar a different one, so the check
/// would catch a default that followed the phone.
@Suite("One app calendar")
struct AppCalendarTests {
    /// The phone's time zone, counted the way Romanian documents count.
    static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// What a phone set to another calendar would count in, in the same time zone.
    static func phone(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = .current
        return calendar
    }

    static func noon(_ iso: String) throws -> Date {
        let day = CalendarDay(iso)
        return try #require(gregorian.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)))
    }

    @Test func theAppCalendarIsGregorianInRomanianInThePhonesTimeZone() {
        let calendar = Calendar.dosar
        #expect(calendar.identifier == .gregorian)
        #expect(calendar.timeZone == TimeZone.current)
        #expect(calendar.locale?.identifier == Locale.dosarDefault.identifier)
        #expect(calendar.firstWeekday == 2)
        #expect(Calendar.dosar == calendar)
    }

    @Test func aSetTimeZoneKeepsTheSameCalendar() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let calendar = Calendar.dosar(in: tokyo)
        #expect(calendar.identifier == .gregorian)
        #expect(calendar.timeZone == tokyo)
        #expect(CalendarDay.isoCalendar.identifier == .gregorian)
        #expect(CalendarDay.isoCalendar.timeZone.secondsFromGMT() == 0)
    }

    @Test func aDayFromAMomentIsTheGregorianDay() throws {
        let moment = try Self.noon("2026-03-31")
        #expect(CalendarDay(moment) == CalendarDay("2026-03-31"))
        #expect(CalendarDay(moment, calendar: Self.phone(.buddhist)).year == 2569)
        #expect(CalendarDay(moment, calendar: Self.phone(.japanese)).year != 2026)
        #expect(CalendarDay(year: 2026, month: 3, day: 31).startDate() == Self.gregorian.startOfDay(for: moment))
        #expect(CalendarDay(year: 2026, month: 3, day: 31).noonDate() == moment)
    }

    @Test func monthsAndDaysAreCountedInGregorianMonths() {
        let endOfJanuary = CalendarDay("2026-01-31")
        #expect(endOfJanuary.adding(months: 1) == CalendarDay("2026-02-28"))
        #expect(CalendarDay("2028-01-31").adding(months: 1) == CalendarDay("2028-02-29"))
        #expect(CalendarDay("2026-03-31").adding(months: -1) == CalendarDay("2026-02-28"))
        #expect(endOfJanuary.adding(days: 29) == CalendarDay("2026-03-01"))
        #expect(endOfJanuary.days(to: CalendarDay("2026-03-31")) == 59)
        #expect(MonthDay(month: 2, day: 29).day(inYear: 2026) == CalendarDay("2026-02-28"))
        #expect(MonthDay(month: 2, day: 29).day(inYear: 2028) == CalendarDay("2028-02-29"))
        // A month in the Islamic calendar is 29 or 30 days, so it would land in March.
        #expect(endOfJanuary.adding(months: 1, calendar: Self.phone(.islamicUmmAlQura)) != CalendarDay("2026-02-28"))
    }

    @Test func aRepeatingDeadlineMovesByGregorianMonths() {
        let due = CalendarDay("2026-01-31")
        #expect(RecurrenceEngine.add(.months(1), to: due) == CalendarDay("2026-02-28"))
        #expect(RecurrenceEngine.add(.months(1), to: CalendarDay("2026-02-28"), dayOfMonth: 31) == CalendarDay("2026-03-31"))
        #expect(RecurrenceEngine.add(.years(1), to: CalendarDay("2028-02-29")) == CalendarDay("2029-02-28"))
        #expect(RecurrenceEngine.nextFixedDate(onOrAfter: CalendarDay("2026-04-01"), dates: [MonthDay(month: 3, day: 31)]) == CalendarDay("2027-03-31"))
        #expect(RecurrenceEngine.add(.months(1), to: due, calendar: Self.phone(.hebrew)) != CalendarDay("2026-02-28"))
    }

    @Test func remindersAndUrgencyCountGregorianMonths() throws {
        // Six calendar months before 31 August is the last day of February.
        let passport = CalendarDay("2027-08-31")
        #expect(ReminderLead(days: 180).day(before: passport) == CalendarDay("2027-02-28"))
        #expect(ReminderLead(days: 180).day(before: passport, calendar: Self.phone(.hebrew)) != CalendarDay("2027-02-28"))

        let rule = UrgencyRule(graceDays: 0, firstLeadDays: 30, maxWindowDays: 30, travelMarginDays: 180)
        #expect(rule.travelCutoff(before: passport) == CalendarDay("2027-02-28"))
        let monthAhead = UrgencyRule(graceDays: 0, firstLeadDays: 30, maxWindowDays: 30)
        #expect(monthAhead.windowDays(before: CalendarDay("2026-03-31")) == 31)
        #expect(monthAhead.urgency(of: CalendarDay("2026-03-31"), today: CalendarDay("2026-02-28")) == .soon)
        #expect(monthAhead.urgency(of: CalendarDay("2026-03-31"), today: CalendarDay("2026-02-27")) == .later)

        let fire = ReminderPlanner.fireDate(day: CalendarDay("2026-03-31"), minuteOfDay: 9 * 60)
        let expected = try #require(Self.gregorian.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 9)))
        #expect(fire == expected)
    }

    @Test func wordingAndDatesAreWrittenInGregorianNumbers() throws {
        let moment = try Self.noon("2026-03-31")
        #expect(DosarFormat.longDay(moment) == "31 martie 2026")
        // A day counted in another calendar is still written in Gregorian numbers.
        #expect(DosarFormat.longDay(moment, calendar: Self.phone(.buddhist)) == "31 martie 2026")
        #expect(DosarFormat.numericDay(moment, calendar: Self.phone(.japanese)) == "31.03.2026")

        let start = try Self.noon("2026-01-01")
        #expect(DurationWording.distance(days: 59, from: start) == DurationWording.distance(days: 59, from: start, calendar: Self.gregorian))
        #expect(DurationWording.distance(days: 59, from: start) == CalendarCount.months(2))

        let today = CalendarDay("2026-03-31")
        let line = DueWording.line(kind: .legal, due: CalendarDay("2027-03-31"), today: today)
        #expect(line == DueWording.line(kind: .legal, due: CalendarDay("2027-03-31"), today: today, calendar: Self.gregorian))
        #expect(line.hasSuffix("31 martie 2027"))
    }
}
