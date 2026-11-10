import Foundation

/// How the database keeps a day (a due day, a document's date, the end of a snooze): as the
/// ISO text of the day, `2026-11-15`, written by `MachineText` like the archive's days.
///
/// A day kept as a moment (noon in the phone's time zone, as version 8 did) reads as another
/// day on a phone ten or more hours away; the text is the same day everywhere, and it sorts
/// as the days do, so a fetch can sort by it. Only the models read and write it, through
/// their `CalendarDay` properties (`Obligation.dueDay`, `HistoryEntry.cycleDueDay`,
/// `Attachment.documentDay`, …); nothing else turns a stored day into a moment or back.
public enum StoredDay {
    /// The stored text of `day`.
    public static func text(_ day: CalendarDay) -> String {
        day.isoString
    }

    /// The day `text` holds; nil when there is none or it isn't a day.
    public static func day(_ text: String?) -> CalendarDay? {
        guard let text, text.count == 10 else { return nil }
        return CalendarDay(isoString: text)
    }

    /// How version 8 kept a day as a moment.
    public enum Moment: Sendable {
        /// Noon of the day in the phone's time zone: due days and a document's dates.
        case noon
        /// The start of the day in the phone's time zone: the end of a snooze.
        case startOfDay
    }

    /// The day a moment version 8 stored meant, counted in `calendar`. The time zone it was
    /// written in wasn't kept, so the caller's is taken (the phone's when the database is
    /// upgraded): noon keeps the day for any time zone up to eleven hours away, and the start of
    /// a day is read as the noon after it, so it keeps it the same way.
    public static func day(of moment: Date, storedAs kind: Moment, calendar: Calendar = .dosar) -> CalendarDay {
        switch kind {
        case .noon: CalendarDay(moment, calendar: calendar)
        case .startOfDay: CalendarDay(moment.addingTimeInterval(12 * 3600), calendar: calendar)
        }
    }
}
