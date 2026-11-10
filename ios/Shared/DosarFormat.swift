import Foundation

/// Dates the way the app writes them, in Romanian whatever the phone's language.
/// Every screen, widget, notification and search entry writes dates here.
///
/// Two kinds of date come in, and each is written as what it is:
/// - A `CalendarDay` (a due day, an expiry) has no time and no time zone. It is
///   written as the day it is, whatever time zone the phone is in.
/// - A `Date` (when a visit happened, when a backup was made) is a moment. It is
///   written as the day it falls on in `calendar`'s time zone: the phone's
///   (`Calendar.dosar`), unless the caller counts days in another one. The
///   numbers are always Gregorian, whatever calendar the phone is set to.
///
/// A due day is never turned into a `Date` to be written: midnight in one time
/// zone is the evening before in another.
enum DosarFormat {
    /// "14 mar. 2025"
    static func day(_ day: CalendarDay, locale: Locale = .dosarDefault) -> String {
        write(day, .day, locale: locale)
    }

    /// "14 mar. 2025"
    static func day(_ date: Date, locale: Locale = .dosarDefault, calendar: Calendar = .dosar) -> String {
        write(date, .day, locale: locale, timeZone: calendar.timeZone)
    }

    /// "14 martie 2025"
    static func longDay(_ day: CalendarDay, locale: Locale = .dosarDefault) -> String {
        write(day, .longDay, locale: locale)
    }

    /// "14 martie 2025"
    static func longDay(_ date: Date, locale: Locale = .dosarDefault, calendar: Calendar = .dosar) -> String {
        write(date, .longDay, locale: locale, timeZone: calendar.timeZone)
    }

    /// "14 martie"
    static func dayMonth(_ day: CalendarDay, locale: Locale = .dosarDefault) -> String {
        write(day, .dayMonth, locale: locale)
    }

    /// "14 martie"
    static func dayMonth(_ date: Date, locale: Locale = .dosarDefault, calendar: Calendar = .dosar) -> String {
        write(date, .dayMonth, locale: locale, timeZone: calendar.timeZone)
    }

    /// "martie 2025"
    static func monthYear(_ day: CalendarDay, locale: Locale = .dosarDefault) -> String {
        write(day, .monthYear, locale: locale)
    }

    /// "martie 2025"
    static func monthYear(_ date: Date, locale: Locale = .dosarDefault, calendar: Calendar = .dosar) -> String {
        write(date, .monthYear, locale: locale, timeZone: calendar.timeZone)
    }

    /// "14.03.2025", as printed on Romanian documents.
    static func numericDay(_ date: Date, locale: Locale = .dosarDefault, calendar: Calendar = .dosar) -> String {
        write(date, .numericDay, locale: locale, timeZone: calendar.timeZone)
    }

    /// "08/28": the month a bank card is valid through, as cards print it.
    static func cardExpiry(_ day: CalendarDay) -> String {
        let calendar = Calendar.dosar(in: .gmt)
        let style = Date.VerbatimFormatStyle(format: "\(month: .twoDigits)/\(year: .twoDigits)", timeZone: .gmt, calendar: calendar)
        return day.startDate(in: calendar).formatted(style)
    }

    /// "14:05"
    static func time(_ date: Date, locale: Locale = .dosarDefault, calendar: Calendar = .dosar) -> String {
        write(date, .time, locale: locale, timeZone: calendar.timeZone)
    }

    // MARK: - One writer

    private enum Shape {
        case day, longDay, dayMonth, monthYear, numericDay, time
    }

    /// A calendar day is written in a calendar with no offset, so nothing can move it. A day the
    /// calendar doesn't have ("2026-02-30", kept as an older build or a backup wrote it) is
    /// written with its own numbers, "30 februarie 2026", never as another day: the month's last
    /// day stands in for it only where a moment is needed (`CalendarDay.onCalendar`).
    private static func write(_ day: CalendarDay, _ shape: Shape, locale: Locale) -> String {
        let date = day.startDate(in: Calendar.dosar(in: .gmt))
        guard !day.isOnCalendar, (1...12).contains(day.month) else { return write(date, shape, locale: locale, timeZone: .gmt) }
        var text = marked(date, shape, locale: locale, timeZone: .gmt)
        if let range = text.runs[\.dateField].first(where: { $0.0 == .day })?.1 {
            text.replaceSubrange(range, with: AttributedString(String(day.day)))
        }
        return String(text.characters)
    }

    /// Always the app's calendar (`Calendar.dosar`), Gregorian like Romanian documents and
    /// `CalendarDay`, whatever calendar the caller counted in: only its time zone is taken.
    private static func write(_ date: Date, _ shape: Shape, locale: Locale, timeZone: TimeZone) -> String {
        String(marked(date, shape, locale: locale, timeZone: timeZone).characters)
    }

    /// The same, with each part marked by the date field it writes.
    private static func marked(_ date: Date, _ shape: Shape, locale: Locale, timeZone: TimeZone) -> AttributedString {
        let base = Date.FormatStyle(locale: locale, calendar: Calendar.dosar(in: timeZone), timeZone: timeZone)
        let style: Date.FormatStyle = switch shape {
        case .day: base.day().month(.abbreviated).year()
        case .longDay: base.day().month(.wide).year()
        case .dayMonth: base.day().month(.wide)
        case .monthYear: base.month(.wide).year()
        case .numericDay: base.day().month(.twoDigits).year()
        case .time: base.hour().minute()
        }
        return date.formatted(style.attributedStyle)
    }
}
