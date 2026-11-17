import Foundation

/// A time of day kept as minutes after midnight (the general reminder time in Settings, a
/// deadline's own „Ora amintirii”), and the moment a time picker shows for it. The one
/// conversion both ways, so a time picked is the time kept.
enum ReminderClock {
    /// 0:00 to 23:59.
    static func clamped(_ minuteOfDay: Int) -> Int { min(max(minuteOfDay, 0), 24 * 60 - 1) }

    /// A moment at `minuteOfDay` on a mid-January day, when no time zone moves its clocks, so
    /// every minute of the day exists (a picker never shows 3:30 as 4:30).
    static func moment(minuteOfDay: Int, calendar: Calendar = .dosar) -> Date {
        CalendarDay(year: 2001, month: 1, day: 15).moment(atMinute: clamped(minuteOfDay), in: calendar)
    }

    /// The minutes after midnight a picked moment shows, in the app's calendar.
    static func minuteOfDay(of moment: Date, calendar: Calendar = .dosar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        return clamped((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// The next day within a year when the clocks skip `minuteOfDay` (the morning summer time
    /// starts: 03:30 doesn't exist in Romania when 03:00 becomes 04:00), with the time a reminder
    /// set for it comes at that day: the first minute after the gap, by the one rule
    /// (`CalendarDay.moment(atMinute:in:)`). Nil when the time exists every day of the next year
    /// in the calendar's time zone.
    static func springForward(minuteOfDay: Int, after now: Date, calendar: Calendar = .dosar) -> (day: CalendarDay, remindsAt: Int)? {
        let minute = clamped(minuteOfDay)
        guard let yearOn = calendar.date(byAdding: .year, value: 1, to: now) else { return nil }
        var after = now
        // A time zone moves its clocks at most a few times a year.
        for _ in 0..<4 {
            guard let change = calendar.timeZone.nextDaylightSavingTimeTransition(after: after), change <= yearOn else { return nil }
            let day = CalendarDay(change, calendar: calendar)
            let moment = day.moment(atMinute: minute, in: calendar)
            let shown = minuteOfDay(of: moment, calendar: calendar)
            if shown != minute, CalendarDay(moment, calendar: calendar) == day {
                return (day, shown)
            }
            after = change
        }
        return nil
    }
}
