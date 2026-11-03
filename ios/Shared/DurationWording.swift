import Foundation

// How long and how far, in words. The app and the widget both compile this file,
// and its counts live in one String Catalog, Shared.xcstrings, as plural variations
// (Romanian one / few / other), so a duration reads the same on every surface.

/// "o zi", "5 zile", "20 de zile": a count of one is a word, two and up are digits.
public enum DayCount {
    public static func phrase(_ count: Int) -> String {
        let n = abs(count)
        return String(localized: "\(n) zile", table: "Shared", comment: "A number of days, with Romanian plural forms: o zi, 2 zile, 20 de zile.")
    }
}

/// "un an", "3 ani", "20 de ani"; "o lună", "5 luni"; "o săptămână", "3 săptămâni".
public enum CalendarCount {
    public static func years(_ count: Int) -> String {
        let n = abs(count)
        return String(localized: "\(n) ani", table: "Shared", comment: "A number of years, with Romanian plural forms.")
    }

    public static func months(_ count: Int) -> String {
        let n = abs(count)
        return String(localized: "\(n) luni", table: "Shared", comment: "A number of months, with Romanian plural forms.")
    }

    public static func weeks(_ count: Int) -> String {
        let n = abs(count)
        return String(localized: "\(n) săptămâni", table: "Shared", comment: "A number of weeks, with Romanian plural forms.")
    }
}

/// How long something is, in the unit a person feels. Two styles, one set of words:
/// - `distance`: how far a day is from today, calendar-accurate and never rounded up
///   ("87 de zile" hides that it's under three months away):
///   under 3 weeks in days, then weeks, then months and weeks, then years and months
///   (years only from 3 years);
/// - `lead`: a reminder's lead as the person chose it ("Cu 6 luni înainte"). Leads of
///   whole months are calendar months (`ReminderLead`), so on the day such a reminder
///   fires, its distance reads exactly the same.
public enum DurationWording {
    /// How far `days` from `today` is: "5 zile", "3 săptămâni", "2 luni și 3 săptămâni",
    /// "un an și 4 luni", "8 ani". The sign of `days` is ignored.
    public static func distance(days: Int, from today: Date = Date(), calendar: Calendar = .current) -> String {
        let n = abs(days)
        guard n >= 21 else { return DayCount.phrase(n) }
        let start = calendar.startOfDay(for: today)
        guard let end = calendar.date(byAdding: .day, value: n, to: start) else { return DayCount.phrase(n) }
        let parts = calendar.dateComponents([.year, .month, .day], from: start, to: end)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        let weeks = (parts.day ?? 0) / 7
        if years > 0 { return yearsAndMonths(years: years, months: months) }
        if months == 0 { return CalendarCount.weeks(max(weeks, 1)) }
        return weeks == 0
            ? CalendarCount.months(months)
            : String(localized: "\(CalendarCount.months(months)) și \(CalendarCount.weeks(weeks))", table: "Shared", comment: "A duration in months and weeks, e.g. '2 luni și 3 săptămâni'.")
    }

    /// A reminder's lead: "7 zile", "o lună", "6 luni", "un an".
    public static func lead(days: Int) -> String {
        ReminderLead(days: days).wording
    }

    /// A duration after „în”: "în 5 zile", "într-o lună", "într-un an și 4 luni". Romanian
    /// joins „în” to „o” and „un”, so every "in this long" is written here, never as
    /// "în \(phrase)" of its own. `startsSentence` capitalises it: "Într-o lună".
    public static func inside(_ phrase: String, startsSentence: Bool = false) -> String {
        let text = String(localized: "în \(phrase)", table: "Shared", comment: "In a duration such as '5 zile' or '2 luni și 3 săptămâni'. A duration of one ('o lună', 'un an') is joined: 'într-o lună'.")
        let joined: String
        if let rest = text.dropPrefix("în o ") {
            joined = "într-o " + rest
        } else if let rest = text.dropPrefix("în un ") {
            joined = "într-un " + rest
        } else {
            joined = text
        }
        guard startsSentence, let first = joined.first else { return joined }
        return String(first).uppercased(with: .dosarDefault) + joined.dropFirst()
    }

    /// "un an și 4 luni", "3 ani", "5 luni". Months stop mattering from 3 years.
    public static func yearsAndMonths(years: Int, months: Int) -> String {
        if years == 0 { return CalendarCount.months(months) }
        if months == 0 || years >= 3 { return CalendarCount.years(years) }
        return String(localized: "\(CalendarCount.years(years)) și \(CalendarCount.months(months))", table: "Shared", comment: "A duration or an age in years and months, e.g. 'un an și 4 luni'.")
    }
}

/// When a deadline is, in a few words, from its urgency: "azi", "mâine", "în 5 zile",
/// "întârziat cu o zi" (late within grace), "depășit de 3 zile" (late past grace).
/// The binder's boxes, the badges, the widget and Siri all say it this way.
public enum WhenWording {
    public static func phrase(_ urgency: AttentionUrgency, daysRemaining days: Int, from today: Date = Date(), calendar: Calendar = .current) -> String {
        let distance = DurationWording.distance(days: days, from: today, calendar: calendar)
        switch urgency {
        case .overdue:
            return String(localized: "depășit de \(distance)", table: "Shared", comment: "When: late past its grace, by a duration such as '3 zile'.")
        case .withinGrace:
            return String(localized: "întârziat cu \(distance)", table: "Shared", comment: "When: late, but within the accepted grace, by a duration such as '2 zile'.")
        case .today:
            return String(localized: "azi", table: "Shared", comment: "When: due today.")
        case .soon, .upcoming, .later:
            if days == 1 { return String(localized: "mâine", table: "Shared", comment: "When: due tomorrow.") }
            return DurationWording.inside(distance)
        }
    }

    /// The same words starting a line on their own: "Azi", "În 5 zile", "Depășit de 3 zile".
    public static func standalone(_ urgency: AttentionUrgency, daysRemaining days: Int, from today: Date = Date(), calendar: Calendar = .current) -> String {
        let text = phrase(urgency, daysRemaining: days, from: today, calendar: calendar)
        return String(text.prefix(1)).uppercased(with: .dosarDefault) + String(text.dropFirst())
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }
}
