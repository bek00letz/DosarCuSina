import Foundation
import os

extension Calendar {
    /// The one calendar the app, its widgets and the share extension count days in, the way
    /// `Locale.dosarDefault` is the one locale they write in: Gregorian, in Romanian (weeks
    /// start on Monday), in the phone's time zone.
    ///
    /// Documents, deadlines, Romanian law and the archive's ISO days are all Gregorian, so a
    /// phone set to another calendar (Buddhist, Japanese, Hebrew, Islamic…) still counts
    /// 31 March as 31 March 2026. The time zone is read each time, as `Calendar.current`
    /// reads it, so a phone that moves to another time zone counts its days there.
    ///
    /// Every default calendar, every "today" and every day made from a moment goes through
    /// here; the architecture check (`app-calendar`) keeps `Calendar.current` out of app code.
    public static var dosar: Calendar {
        let zone = TimeZone.current
        return lastMade.withLock { state in
            if let kept = state, kept.timeZone == zone { return kept }
            let made = dosar(in: zone)
            state = made
            return made
        }
    }

    /// The app's calendar in a time zone of the caller's choosing: UTC for days alone
    /// (`CalendarDay.isoCalendar`), or the time zone a moment is written in.
    public static func dosar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .dosarDefault
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    /// The app's calendar for the time zone it was last asked in, made again when the phone's
    /// time zone changes.
    private static let lastMade = OSAllocatedUnfairLock<Calendar?>(initialState: nil)
}
