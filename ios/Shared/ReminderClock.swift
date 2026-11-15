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
}
