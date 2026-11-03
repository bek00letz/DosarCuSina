import Foundation

/// A local notification the app wants pending.
public struct PlannedReminder: Hashable, Sendable, Identifiable {
    /// `obligation.<uuid>.d<days>` or `obligation.<uuid>.snooze`.
    public var identifier: String
    public var obligationId: UUID
    public var fireDate: Date
    public var title: String
    public var body: String
    /// May break through Focus (the last reminders for consequential kinds).
    public var isTimeSensitive: Bool
    /// Changes whenever anything the person would see changes, so the
    /// reconciler can tell a pending request is stale.
    public var fingerprint: String
    /// Where tapping the notification goes.
    public var deepLink: URL

    public var id: String { identifier }
}

/// Works out every reminder that should be pending, from obligation snapshots.
/// Pure: no notification center, no database, so every rule is testable.
public enum ReminderPlanner {
    public static let identifierPrefix = "obligation."
    /// Identifier suffix of the one follow-up after the due date: `obligation.<uuid>.lapse`.
    public static let lapseSuffix = "lapse"
    /// iOS keeps at most 64 pending requests per app; leave room for the system.
    public static let defaultLimit = 60

    public static func plan(
        _ obligations: [ObligationSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current,
        defaultMinuteOfDay: Int = AppPreferences.defaultReminderMinuteOfDay,
        limit: Int = ReminderPlanner.defaultLimit,
        locale: Locale = .dosarDefault
    ) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for obligation in obligations where obligation.status == .active && !obligation.isExample {
            let minute = obligation.reminderMinuteOfDay ?? defaultMinuteOfDay
            let snoozedUntil = obligation.snoozedUntil.flatMap { $0 > now ? $0 : nil }

            let profile = obligation.reminders
            for offset in profile.leadDays {
                let day = obligation.dueDay.adding(days: -offset, calendar: calendar)
                let fire = fireDate(day: day, minuteOfDay: minute, calendar: calendar)
                guard fire > now else { continue }
                if let snoozedUntil, fire < snoozedUntil { continue }
                result.append(reminder(for: obligation, daysBefore: offset, fireDate: fire, identifierSuffix: "d\(offset)", calendar: calendar, locale: locale))
            }

            // "Follow up after it lapses": one reminder the day after the due date,
            // then silence. Completing the obligation removes it from the plan.
            if profile.followUpAfterLapse {
                let lapseFire = fireDate(day: obligation.dueDay.adding(days: 1, calendar: calendar), minuteOfDay: minute, calendar: calendar)
                if lapseFire > now, snoozedUntil.map({ lapseFire >= $0 }) ?? true {
                    result.append(reminder(for: obligation, daysBefore: -1, fireDate: lapseFire, identifierSuffix: lapseSuffix, calendar: calendar, locale: locale))
                }
            }

            if let snoozedUntil {
                let day = CalendarDay(snoozedUntil, calendar: calendar)
                let fire = fireDate(day: day, minuteOfDay: minute, calendar: calendar)
                if fire > now {
                    let daysBefore = day.days(to: obligation.dueDay, calendar: calendar)
                    result.append(reminder(for: obligation, daysBefore: daysBefore, fireDate: fire, identifierSuffix: "snooze", calendar: calendar, locale: locale))
                }
            }
        }
        result.sort { $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.identifier < $1.identifier }
        return Array(result.prefix(limit))
    }

    /// The moment `minuteOfDay` minutes after midnight on `day`, in local time.
    /// Uses calendar components, so daylight-saving changes keep the wall-clock time.
    public static func fireDate(day: CalendarDay, minuteOfDay: Int, calendar: Calendar = .current) -> Date {
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = minuteOfDay / 60
        parts.minute = minuteOfDay % 60
        return calendar.date(from: parts) ?? day.startDate(in: calendar)
    }

    public static func identifier(obligationId: UUID, suffix: String) -> String {
        "\(identifierPrefix)\(obligationId.uuidString.lowercased()).\(suffix)"
    }

    /// The obligation a reminder identifier belongs to.
    public static func obligationId(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let rest = identifier.dropFirst(identifierPrefix.count)
        return rest.split(separator: ".").first.flatMap { UUID(uuidString: String($0)) }
    }

    // MARK: Copy

    static func reminder(
        for obligation: ObligationSnapshot,
        daysBefore: Int,
        fireDate: Date,
        identifierSuffix: String,
        calendar: Calendar,
        locale: Locale
    ) -> PlannedReminder {
        let title: String
        let body: String
        if obligation.isSensitive {
            title = genericTitle(daysBefore: daysBefore)
            body = String(localized: "Deschide Dosar cu Șină pentru detalii.", comment: "Reminder body for protected categories")
        } else {
            if daysBefore < 0, obligation.reminders.graceDays > 0 {
                // Still within the grace the person accepts, so the follow-up stays calm.
                title = String(localized: "Încă de făcut: \(obligation.title)", comment: "Follow-up reminder title the day after the due date, when some lateness is fine")
            } else {
                title = specificTitle(obligation.title, daysBefore: daysBefore)
            }
            let dueText = DosarFormat.dayMonth(obligation.dueDay, locale: locale)
            if let assetName = obligation.assetName, !assetName.isEmpty {
                body = String(localized: "\(assetName) · scadent pe \(dueText)", comment: "Reminder body: asset name and due date")
            } else {
                body = String(localized: "Scadent pe \(dueText)", comment: "Reminder body: due date")
            }
        }
        let isTimeSensitive = daysBefore <= 1 && obligation.reminders.consequence.allowsTimeSensitiveReminders
        let fingerprint = [
            String(Int(fireDate.timeIntervalSince1970)), title, body, isTimeSensitive ? "ts" : "a",
        ].joined(separator: "|")
        return PlannedReminder(
            identifier: identifier(obligationId: obligation.id, suffix: identifierSuffix),
            obligationId: obligation.id,
            fireDate: fireDate,
            title: title,
            body: body,
            isTimeSensitive: isTimeSensitive,
            fingerprint: fingerprint,
            deepLink: DeepLink.url(for: .obligation(obligation.id))
        )
    }

    static func specificTitle(_ title: String, daysBefore: Int) -> String {
        switch daysBefore {
        case ..<0: return String(localized: "Depășit: \(title)", comment: "Reminder title for an overdue obligation")
        case 0: return String(localized: "Azi: \(title)", comment: "Reminder title, due today")
        case 1: return String(localized: "Mâine: \(title)", comment: "Reminder title, due tomorrow")
        default: return String(localized: "În \(DurationWording.phrase(days: daysBefore)): \(title)", comment: "Reminder title: due in a duration such as '7 zile' or '9 luni', then the obligation.")
        }
    }

    static func genericTitle(daysBefore: Int) -> String {
        switch daysBefore {
        case ..<0: return String(localized: "Ai o scadență depășită", comment: "Generic reminder title")
        case 0: return String(localized: "Ai o scadență azi", comment: "Generic reminder title")
        case 1: return String(localized: "Ai o scadență mâine", comment: "Generic reminder title")
        default: return String(localized: "Ai o scadență în \(DurationWording.phrase(days: daysBefore))", comment: "Generic reminder title: due in a duration such as '7 zile' or '2 luni'.")
        }
    }
}
