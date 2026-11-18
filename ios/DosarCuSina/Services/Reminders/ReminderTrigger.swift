import Foundation
@preconcurrency import UserNotifications

/// The one place a reminder's moment is handed to the system. Its date parts always carry the
/// app's calendar (`Calendar.dosar`, Gregorian), so the system reads "9:00 on 15 November 2026"
/// as that, whatever calendar the phone is set to: without it, the parts are read in the phone's
/// own calendar, where year 2026 is long past (Buddhist) or far ahead (Japanese, Hebrew).
///
/// The parts name a wall-clock time and no time zone, so a reminder fires at its hour wherever
/// the phone is; a move to another time zone plans every reminder again anyway
/// (`SideEffectsCoordinator.timeChanges`).
enum ReminderTrigger {
    /// The date parts of `moment` in `calendar`, with the calendar they were read in.
    static func components(firingAt moment: Date, calendar: Calendar = .dosar) -> DateComponents {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        parts.calendar = calendar
        return parts
    }

    /// The trigger for a reminder that fires once at `moment`.
    static func make(firingAt moment: Date, calendar: Calendar = .dosar) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: components(firingAt: moment, calendar: calendar), repeats: false)
    }
}
