import Foundation
import Testing
@testable import DosarCuSina

/// Dates read the same day in every time zone: a due day is written as the day it
/// is, and a moment as the day it falls on where the days are counted. The zones
/// cover UTC (where CI runs), west of it, and both ends of the clock, so a
/// day turned into midnight somewhere and written in another zone fails here on
/// any machine.
@Suite("Writing dates in any time zone")
struct DosarFormatTests {
    static let zones = ["UTC", "America/New_York", "Europe/Bucharest", "Pacific/Kiritimati", "Pacific/Pago_Pago"]
    let ro = Locale(identifier: "ro_RO")

    @Test("A due day is written as the day it is", arguments: zones)
    func aDueDayIsTheDayItIs(zone: String) throws {
        let calendar = try Self.calendar(zone)
        let today = CalendarDay("2026-11-02")
        let due = CalendarDay("2026-11-07")

        #expect(DosarFormat.day(due, locale: ro) == "7 nov. 2026")
        #expect(DosarFormat.longDay(due, locale: ro) == "7 noiembrie 2026")
        #expect(DosarFormat.dayMonth(due, locale: ro) == "7 noiembrie")
        #expect(DosarFormat.monthYear(due, locale: ro) == "noiembrie 2026")
        #expect(DueWording.line(kind: .legal, due: due, today: today, calendar: calendar) == "Expiră în 5 zile · 7 noiembrie")
        #expect(DueWording.line(kind: .payment, due: today, today: today, calendar: calendar) == "De plătit azi · 2 noiembrie")
        #expect(DueWording.date(CalendarDay("2031-08-12"), today: today) == "12 august 2031")
        #expect(ReminderWording.expiryLine(CalendarDay("2031-08-12"), profile: ReminderProfile(leadDays: [90, 30], consequence: .legal), today: today).hasPrefix("Expiră pe 12 august 2031."))
    }

    @Test("A day counted in a zone and written there is the same day", arguments: zones)
    func aDayRoundTripsThroughItsZone(zone: String) throws {
        let calendar = try Self.calendar(zone)
        for iso in ["2026-01-01", "2026-03-29", "2026-08-12", "2026-10-25", "2026-12-31"] {
            let day = CalendarDay(iso)
            #expect(CalendarDay(day.startDate(in: calendar), calendar: calendar) == day)
            #expect(DosarFormat.longDay(day.startDate(in: calendar), locale: ro, calendar: calendar) == DosarFormat.longDay(day, locale: ro))
            #expect(DosarFormat.longDay(day.noonDate(in: calendar), locale: ro, calendar: calendar) == DosarFormat.longDay(day, locale: ro))
        }
    }

    @Test func aMomentIsWrittenAsTheDayItFallsOnWhereDaysAreCounted() throws {
        // 23:30 UTC on 11 August: still the 11th in New York, already the 12th in Bucharest.
        let moment = try #require(ISO8601DateFormatter().date(from: "2026-08-11T23:30:00Z"))
        let utc = try Self.calendar("UTC")
        let newYork = try Self.calendar("America/New_York")
        #expect(DosarFormat.day(moment, locale: ro, calendar: utc) == "11 aug. 2026")
        #expect(DosarFormat.day(moment, locale: ro, calendar: newYork) == "11 aug. 2026")
        #expect(DosarFormat.day(moment, locale: ro, calendar: .bucharest) == "12 aug. 2026")
        #expect(DosarFormat.dayMonth(moment, locale: ro, calendar: .bucharest) == "12 august")
        #expect(DosarFormat.monthYear(moment, locale: ro, calendar: utc) == "august 2026")
        #expect(DosarFormat.time(moment, locale: ro, calendar: utc) == "23:30")
        #expect(DosarFormat.time(moment, locale: ro, calendar: .bucharest) == "02:30")
        #expect(DosarFormat.numericDay(moment, locale: ro, calendar: .bucharest).hasSuffix(".08.2026"))
    }

    @Test func machineDaysArePaddedAndNeverLocalized() {
        #expect(CalendarDay(year: 2026, month: 3, day: 7).isoString == "2026-03-07")
        #expect(CalendarDay(year: 987, month: 12, day: 31).isoString == "0987-12-31")
        #expect(MonthDay(month: 3, day: 1).isoString == "03-01")
    }

    private static func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }
}
