import Foundation

/// The app's badge while the app stays closed. A pass sets the badge to what needs doing now
/// (`AttentionModel`'s count: late past its grace, or due today), but the count moves as days
/// pass, and the app may not run on those days. So the badge travels with the reminders, which
/// iOS shows whether the app runs or not:
///
/// - every reminder carries the badge as it will be on the day it fires;
/// - on each of the next `horizonDays` days whose count differs from the day before, a reminder
///   that shows nothing (no title, no sound, not in Notification Center) sets the badge as that
///   day starts, in the room the reminders leave (`ReminderPlanner.defaultLimit`).
///
/// Each count is worked out as if nothing is done meanwhile; anything the person does saves, and
/// the pass that follows plans them all again. Beyond the horizon, or when the reminders fill
/// every place iOS keeps, the badge moves with the next reminder that fires, or when the app
/// next runs (the background refresh, when iOS allows it). Pure: no notification center and no
/// clock of its own.
public enum BadgePlanner {
    /// Identifier prefix of a reminder that only sets the badge: `obligation.badge.<yyyy-MM-dd>`,
    /// under the reminders' prefix, so the reconciler owns it like any other.
    public static let identifierPrefix = ReminderPlanner.identifierPrefix + "badge."
    /// How many days ahead the badge is planned on its own: a week, by which the app has
    /// usually run again.
    public static let horizonDays = 7

    /// The badge on `day`, by the app's one count (`AttentionModel.digest`'s `needsActionCount`).
    public static func count(_ obligations: [ObligationSnapshot], on day: CalendarDay, calendar: Calendar = .dosar) -> Int {
        AttentionModel.digest(obligations, now: day.startDate(in: calendar), calendar: calendar).needsActionCount
    }

    /// `reminders`, each with the badge of the day it fires, and the badge-only reminders for the
    /// next days whose count changes, as many as fit under `limit`.
    public static func plan(
        _ reminders: [PlannedReminder],
        obligations: [ObligationSnapshot],
        now: Date,
        calendar: Calendar = .dosar,
        limit: Int = ReminderPlanner.defaultLimit
    ) -> [PlannedReminder] {
        var counts: [CalendarDay: Int] = [:]
        func badge(on day: CalendarDay) -> Int {
            if let known = counts[day] { return known }
            let value = count(obligations, on: day, calendar: calendar)
            counts[day] = value
            return value
        }

        var planned = reminders.map { reminder in
            var reminder = reminder
            let value = badge(on: CalendarDay(reminder.fireDate, calendar: calendar))
            reminder.badge = value
            reminder.fingerprint += "|b\(value)"
            return reminder
        }

        let today = CalendarDay(now, calendar: calendar)
        var room = limit - planned.count
        var previous = badge(on: today)
        for offset in 1...horizonDays where room > 0 {
            let day = today.adding(days: offset, calendar: calendar)
            let value = badge(on: day)
            defer { previous = value }
            guard value != previous else { continue }
            planned.append(badgeOnly(value, on: day, calendar: calendar))
            room -= 1
        }
        return planned
    }

    /// The reminder that only sets the badge to `count` as `day` starts.
    static func badgeOnly(_ count: Int, on day: CalendarDay, calendar: Calendar) -> PlannedReminder {
        let fire = day.startDate(in: calendar)
        return PlannedReminder(
            identifier: identifierPrefix + day.isoString,
            obligationId: nil,
            cycle: nil,
            fireDate: fire,
            title: "",
            body: "",
            isTimeSensitive: false,
            fingerprint: [String(Int(fire.timeIntervalSince1970)), "badge", String(count)].joined(separator: "|"),
            deepLink: DeepLink.url(for: .upcoming),
            badge: count,
            showsAlert: false
        )
    }
}
