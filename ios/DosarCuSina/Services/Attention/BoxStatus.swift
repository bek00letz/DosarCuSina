import Foundation

/// The one line under a box on the Dosar grid: "Totul e în regulă", or the
/// single most pressing obligation in that box with how far it is.
public struct BoxStatus: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case allGood
        case pending(AttentionEntry)
    }

    public var state: State

    /// The obligation shown, if any.
    public var entry: AttentionEntry? {
        if case .pending(let entry) = state { return entry }
        return nil
    }

    /// Whether the line should look like a problem (overdue past grace, or due today).
    public var isAlarming: Bool { entry?.urgency.isAlarming ?? false }

    /// The status of a box from the obligations it holds, ranked exactly as the
    /// Urmează tab ranks them. Only what is inside its attention window counts;
    /// anything further out is "all good" for now.
    public static func make(_ obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .current) -> BoxStatus {
        let digest = AttentionModel.digest(obligations, now: now, calendar: calendar, limits: .init(maxNow: 1, soonWindowDays: 0))
        if let top = digest.now.first { return BoxStatus(state: .pending(top)) }
        return BoxStatus(state: .allGood)
    }

    /// The box of one asset: its own obligations and those of the assets filed under it.
    public static func make(forAsset id: UUID, descendants: Set<UUID> = [], in obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .current) -> BoxStatus {
        let ids = descendants.union([id])
        return make(obligations.filter { $0.assetId.map(ids.contains) ?? false }, now: now, calendar: calendar)
    }

    /// The line to show. In a section behind a lock the obligation's title is
    /// replaced, so the line never reveals what is inside.
    public func line(isSensitive: Bool) -> String {
        guard let entry else { return String(localized: "Totul e în regulă", comment: "Box status when nothing needs attention") }
        let title = isSensitive ? String(localized: "O scadență", comment: "Box status title in a locked section") : entry.obligation.title
        let days = abs(entry.daysRemaining)
        switch entry.urgency {
        case .overdue:
            return String(localized: "\(title) · depășit de \(DurationWording.phrase(days: days))", comment: "Box status: overdue by N days")
        case .withinGrace:
            return String(localized: "\(title) · întârziat \(DurationWording.phrase(days: days))", comment: "Box status: late, but within accepted grace")
        case .today:
            return String(localized: "\(title) · azi", comment: "Box status: due today")
        case .soon, .upcoming, .later:
            if entry.daysRemaining == 1 { return String(localized: "\(title) · mâine", comment: "Box status: due tomorrow") }
            return String(localized: "\(title) · în \(DurationWording.phrase(days: days))", comment: "Box status: due in N days")
        }
    }
}

/// "1 zi", "5 zile", "20 de zile". The forms live in the String Catalog as
/// plural variations (Romanian one / few / other), like every other count in
/// the app, so there is one way to write plurals.
public enum DayCount {
    public static func phrase(_ count: Int) -> String {
        let n = abs(count)
        return String(localized: "\(n) zile", comment: "A number of days, with Romanian plural forms: 1 zi, 2 zile, 20 de zile.")
    }
}

/// "1 an", "3 ani", "20 de ani"; "1 lună", "5 luni"; "1 săptămână", "3 săptămâni".
public enum CalendarCount {
    public static func years(_ count: Int) -> String {
        String(localized: "\(abs(count)) ani", comment: "A number of years, with Romanian plural forms.")
    }

    public static func months(_ count: Int) -> String {
        String(localized: "\(abs(count)) luni", comment: "A number of months, with Romanian plural forms.")
    }

    public static func weeks(_ count: Int) -> String {
        String(localized: "\(abs(count)) săptămâni", comment: "A number of weeks, with Romanian plural forms.")
    }
}

/// How far away something is, in the unit a person feels: "87 de zile" hides
/// that it's under three months away. Steps up as the distance grows:
/// - under 3 weeks: days ("5 zile", "18 zile"), where every day counts;
/// - under a month: weeks ("3 săptămâni");
/// - under a year: months and weeks ("2 luni și 3 săptămâni");
/// - from a year: years and months ("1 an și 4 luni"), years only from 3 years ("8 ani").
/// Leftovers are always dropped, never rounded up, so it never shows more time
/// than there is. Calendar-accurate from `today`; the sign of `days` is ignored.
public enum DurationWording {
    public static func phrase(days: Int, from today: Date = Date(), calendar: Calendar = .current) -> String {
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
            : String(localized: "\(CalendarCount.months(months)) și \(CalendarCount.weeks(weeks))", comment: "A duration in months and weeks, e.g. '2 luni și 3 săptămâni'.")
    }

    /// "1 an și 4 luni", "3 ani", "5 luni". Months stop mattering from 3 years.
    public static func yearsAndMonths(years: Int, months: Int) -> String {
        if years == 0 { return CalendarCount.months(months) }
        if months == 0 || years >= 3 { return CalendarCount.years(years) }
        return String(localized: "\(CalendarCount.years(years)) și \(CalendarCount.months(months))", comment: "A duration or an age in years and months, e.g. '1 an și 4 luni'.")
    }
}
