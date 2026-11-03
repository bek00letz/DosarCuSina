import Foundation

/// A local notification the app wants pending.
public struct PlannedReminder: Hashable, Sendable, Identifiable {
    /// `obligation.<uuid>.d<days>` (`.t<days>` before a travel cut-off), `.catchup`, `.lapse` or `.snooze`, or
    /// `ReminderPlanner.continueIdentifier` for the "open the app" reminder.
    public var identifier: String
    /// The obligation it is about; nil only for the "open the app" reminder.
    public var obligationId: UUID?
    /// The due day of the cycle it is about. A button tapped on it acts only while
    /// the obligation is still on this cycle.
    public var cycle: CalendarDay?
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
/// Pure: no notification center, no database, no clock of its own, so every
/// rule is testable.
///
/// - Each lead of the profile reminds once, at the reminder time. A lead of whole
///   months is calendar months (`ReminderLead`): "6 luni" fires on the same day of the
///   month six months before, so its title reads "În 6 luni", like the lead itself.
/// - A document with a travel cut-off (a passport) counts its leads back from the cut-off
///   (`UrgencyRule.reminderAnchor`), and its reminders say how long it is still good for
///   travel. The follow-up after it lapses stays the day after it expires.
/// - A deadline that became known after its warnings had passed gets one
///   catch-up reminder at the next reminder time, so it is never silent.
/// - iOS keeps 64 pending notifications. When there are more, the plan keeps
///   every deadline's next reminder first, most consequential first, then the
///   rest by time, and gives its last place to a reminder to open the app,
///   just before the planned ones run out.
public enum ReminderPlanner {
    public static let identifierPrefix = "obligation."
    /// Identifier suffix of the one follow-up after the due date: `obligation.<uuid>.lapse`.
    public static let lapseSuffix = "lapse"
    /// Identifier suffix of the one reminder for warnings that passed before the deadline was known.
    public static let catchUpSuffix = "catchup"
    /// Prefix of a lead's suffix: `d` for days before the due day, `t` for days before a
    /// travel cut-off (never read back as a due day, so a button acts only on the cycle it carries).
    static func leadSuffix(_ days: Int, travel: Bool) -> String { "\(travel ? "t" : "d")\(days)" }
    /// The "open the app so reminders continue" reminder. It sits under the same
    /// prefix so the reconciler owns it like any other reminder.
    public static let continueIdentifier = "obligation.continue"
    /// iOS keeps at most 64 pending requests per app; leave room for the system.
    public static let defaultLimit = 60

    public static func plan(
        _ obligations: [ObligationSnapshot],
        now: Date,
        calendar: Calendar = .current,
        defaultMinuteOfDay: Int = AppPreferences.defaultReminderMinuteOfDay,
        limit: Int = ReminderPlanner.defaultLimit,
        locale: Locale = .dosarDefault
    ) -> [PlannedReminder] {
        var perObligation: [(weight: Int, reminders: [PlannedReminder])] = []
        for obligation in obligations where obligation.status == .active && !obligation.isExample {
            let reminders = candidates(for: obligation, now: now, calendar: calendar, defaultMinuteOfDay: defaultMinuteOfDay, locale: locale)
            guard !reminders.isEmpty else { continue }
            perObligation.append((obligation.reminders.consequence.weight, reminders.sorted(by: byTime)))
        }
        let all = perObligation.flatMap(\.reminders)
        guard all.count > limit else { return all.sorted(by: byTime) }

        // Too many for the system: every deadline's next reminder first, the most
        // consequential first, then everything else by time.
        let firsts = perObligation
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : byTime($0.reminders[0], $1.reminders[0]) }
            .map { $0.reminders[0] }
        let rest = perObligation.flatMap { $0.reminders.dropFirst() }.sorted(by: byTime)
        let ordered = firsts + rest
        let kept = Array(ordered.prefix(max(0, limit - 1)))
        let dropped = ordered.dropFirst(kept.count)

        var result = kept.sorted(by: byTime)
        if let runsOut = dropped.map(\.fireDate).min(),
           let reminder = continueReminder(before: runsOut, now: now, calendar: calendar, minuteOfDay: defaultMinuteOfDay) {
            result.append(reminder)
        }
        return result
    }

    /// Every reminder one obligation wants pending, in no particular order.
    static func candidates(
        for obligation: ObligationSnapshot,
        now: Date,
        calendar: Calendar,
        defaultMinuteOfDay: Int,
        locale: Locale
    ) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let minute = obligation.reminderMinuteOfDay ?? defaultMinuteOfDay
        let snoozedUntil = obligation.snoozedUntil.flatMap { $0 > now ? $0 : nil }
        let profile = obligation.reminders
        let cutoff = profile.urgencyRule.travelCutoff(before: obligation.dueDay, calendar: calendar)
        func make(_ day: CalendarDay, _ fire: Date, _ suffix: String) -> PlannedReminder {
            reminder(for: obligation, on: day, fireDate: fire, identifierSuffix: suffix, calendar: calendar, locale: locale)
        }

        for offset in profile.leadDays {
            let day = ReminderLead(days: offset).day(before: cutoff ?? obligation.dueDay, calendar: calendar)
            let fire = fireDate(day: day, minuteOfDay: minute, calendar: calendar)
            guard fire > now else { continue }
            if let snoozedUntil, fire < snoozedUntil { continue }
            result.append(make(day, fire, leadSuffix(offset, travel: cutoff != nil)))
        }

        if snoozedUntil == nil, let (day, fire) = catchUp(for: obligation, minuteOfDay: minute, calendar: calendar), fire > now {
            result.append(make(day, fire, catchUpSuffix))
        }

        // "Follow up after it lapses": one reminder the day after the due date,
        // then silence. Completing the obligation removes it from the plan.
        if profile.followUpAfterLapse {
            let day = obligation.dueDay.adding(days: 1, calendar: calendar)
            let fire = fireDate(day: day, minuteOfDay: minute, calendar: calendar)
            if fire > now, snoozedUntil.map({ fire >= $0 }) ?? true {
                result.append(make(day, fire, lapseSuffix))
            }
        }

        if let snoozedUntil {
            let day = CalendarDay(snoozedUntil, calendar: calendar)
            let fire = fireDate(day: day, minuteOfDay: minute, calendar: calendar)
            if fire > now {
                result.append(make(day, fire, "snooze"))
            }
        }
        return result
    }

    /// The one catch-up reminder for a deadline whose warnings (lead days before
    /// the day they count from) had all passed by the time it became known: the first
    /// reminder time after that, as long as it falls before that day, or on it when the
    /// profile doesn't remind on the day itself. Anchored to when the cycle
    /// became known, so it fires once and never repeats.
    static func catchUp(for obligation: ObligationSnapshot, minuteOfDay: Int, calendar: Calendar) -> (CalendarDay, Date)? {
        guard let knownSince = obligation.cycleKnownSince else { return nil }
        let warnings = obligation.reminders.leadDays.filter { $0 > 0 }
        guard !warnings.isEmpty else { return nil }
        let anchor = obligation.reminders.urgencyRule.reminderAnchor(for: obligation.dueDay, calendar: calendar)
        let warningFires = warnings.map {
            fireDate(day: ReminderLead(days: $0).day(before: anchor, calendar: calendar), minuteOfDay: minuteOfDay, calendar: calendar)
        }
        guard warningFires.allSatisfy({ $0 <= knownSince }) else { return nil }

        var day = CalendarDay(knownSince, calendar: calendar)
        var fire = fireDate(day: day, minuteOfDay: minuteOfDay, calendar: calendar)
        if fire <= knownSince {
            day = day.adding(days: 1, calendar: calendar)
            fire = fireDate(day: day, minuteOfDay: minuteOfDay, calendar: calendar)
        }
        let remindsOnTheDay = obligation.reminders.leadDays.contains(0)
        let beforeAnchor = day < anchor || (day == anchor && !remindsOnTheDay)
        // Past a travel cut-off the document still expires: one reminder before it does.
        let beforeExpiry = anchor < obligation.dueDay && day < obligation.dueDay
        guard beforeAnchor || beforeExpiry else { return nil }
        return (day, fire)
    }

    /// The "open the app" reminder: the reminder time the day before the planned
    /// reminders run out, or half an hour before when that day has already begun.
    static func continueReminder(before runsOut: Date, now: Date, calendar: Calendar, minuteOfDay: Int) -> PlannedReminder? {
        let dayBefore = CalendarDay(runsOut, calendar: calendar).adding(days: -1, calendar: calendar)
        let choices = [fireDate(day: dayBefore, minuteOfDay: minuteOfDay, calendar: calendar), runsOut.addingTimeInterval(-30 * 60)]
        guard let fire = choices.first(where: { $0 > now && $0 < runsOut }) else { return nil }
        let title = String(localized: "Deschide Dosar cu Șină o clipă", comment: "Reminder title when the phone can't hold every reminder: opening the app plans the next ones")
        let body = String(localized: "Ca să-ți amintim în continuare de termene, deschide aplicația.", comment: "Reminder body when the phone can't hold every reminder")
        return PlannedReminder(
            identifier: continueIdentifier,
            obligationId: nil,
            cycle: nil,
            fireDate: fire,
            title: title,
            body: body,
            isTimeSensitive: false,
            fingerprint: [String(Int(fire.timeIntervalSince1970)), title, body].joined(separator: "|"),
            deepLink: DeepLink.url(for: .upcoming)
        )
    }

    private static func byTime(_ a: PlannedReminder, _ b: PlannedReminder) -> Bool {
        a.fireDate != b.fireDate ? a.fireDate < b.fireDate : a.identifier < b.identifier
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

    /// The cycle a reminder delivered on `deliveredOn` was about, for reminders
    /// scheduled before they carried it: a lead-day reminder `d<n>` is about the
    /// day `n` days later, the follow-up about the day before. Nil when it can't
    /// be told (a snoozed reminder), so a button on it changes nothing.
    public static func cycle(fromIdentifier identifier: String, deliveredOn: CalendarDay, calendar: Calendar = .current) -> CalendarDay? {
        guard obligationId(fromIdentifier: identifier) != nil, let suffix = identifier.split(separator: ".").last else { return nil }
        if suffix == lapseSuffix { return deliveredOn.adding(days: -1, calendar: calendar) }
        guard suffix.hasPrefix("d"), let days = Int(suffix.dropFirst()) else { return nil }
        return deliveredOn.adding(days: days, calendar: calendar)
    }

    // MARK: Copy

    /// The reminder that fires on `day`. Before a travel cut-off (and on it) it says how
    /// long the document is still good for travel; otherwise how long until the due day.
    static func reminder(
        for obligation: ObligationSnapshot,
        on day: CalendarDay,
        fireDate: Date,
        identifierSuffix: String,
        calendar: Calendar,
        locale: Locale
    ) -> PlannedReminder {
        let daysBefore = day.days(to: obligation.dueDay, calendar: calendar)
        let rule = obligation.reminders.urgencyRule
        let cutoff = rule.travelCutoff(before: obligation.dueDay, calendar: calendar).flatMap { day <= $0 ? $0 : nil }
        let title: String
        let body: String
        if let cutoff {
            let daysToCutoff = day.days(to: cutoff, calendar: calendar)
            title = obligation.isSensitive
                ? genericTravelTitle(daysBefore: daysToCutoff, from: fireDate, calendar: calendar)
                : travelTitle(obligation.title, daysBefore: daysToCutoff, from: fireDate, calendar: calendar)
            let cutoffText = DosarFormat.dayMonth(cutoff, locale: locale)
            if obligation.isSensitive {
                body = String(localized: "Deschide Dosar cu Șină pentru detalii.", comment: "Reminder body for protected categories")
            } else if let assetName = obligation.assetName, !assetName.isEmpty {
                body = String(localized: "\(assetName) · bun de călătorit până pe \(cutoffText)", comment: "Reminder body: a document's name and the last day it is good for travel")
            } else {
                body = String(localized: "Bun de călătorit până pe \(cutoffText)", comment: "Reminder body: the last day a document is good for travel")
            }
        } else if obligation.isSensitive {
            title = genericTitle(daysBefore: daysBefore, from: fireDate, calendar: calendar)
            body = String(localized: "Deschide Dosar cu Șină pentru detalii.", comment: "Reminder body for protected categories")
        } else {
            let fireDay = CalendarDay(fireDate, calendar: calendar)
            if rule.urgency(of: obligation.dueDay, today: fireDay, calendar: calendar) == .withinGrace {
                // Still within the grace the person accepts, so the follow-up stays calm.
                title = String(localized: "Încă de făcut: \(obligation.title)", comment: "Follow-up reminder title the day after the due date, when some lateness is fine")
            } else {
                title = specificTitle(obligation.title, daysBefore: daysBefore, from: fireDate, calendar: calendar)
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
            String(Int(fireDate.timeIntervalSince1970)), obligation.dueDay.isoString, title, body, isTimeSensitive ? "ts" : "a",
        ].joined(separator: "|")
        return PlannedReminder(
            identifier: identifier(obligationId: obligation.id, suffix: identifierSuffix),
            obligationId: obligation.id,
            cycle: obligation.dueDay,
            fireDate: fireDate,
            title: title,
            body: body,
            isTimeSensitive: isTimeSensitive,
            fingerprint: fingerprint,
            deepLink: DeepLink.url(for: .obligation(obligation.id))
        )
    }

    /// Durations are worked out from the day the reminder fires, so "Într-o lună"
    /// is true when the person reads it, and say what every screen says that day.
    static func specificTitle(_ title: String, daysBefore: Int, from fireDate: Date, calendar: Calendar = .current) -> String {
        switch daysBefore {
        case ..<0: return String(localized: "Depășit: \(title)", comment: "Reminder title for an overdue obligation")
        case 0: return String(localized: "Azi: \(title)", comment: "Reminder title, due today")
        case 1: return String(localized: "Mâine: \(title)", comment: "Reminder title, due tomorrow")
        default:
            let phrase = DurationWording.distance(days: daysBefore, from: fireDate, calendar: calendar)
            return String(localized: "\(DurationWording.inside(phrase, startsSentence: true)): \(title)", comment: "Reminder title: due in a duration such as 'În 7 zile' or 'Într-o lună', then the obligation.")
        }
    }

    /// Before a travel cut-off: "Bun de călătorit încă 3 luni: Pașaport"; on it, "Azi e
    /// ultima zi bună de călătorit: Pașaport".
    static func travelTitle(_ title: String, daysBefore: Int, from fireDate: Date, calendar: Calendar = .current) -> String {
        switch daysBefore {
        case ...0: return String(localized: "Azi e ultima zi bună de călătorit: \(title)", comment: "Reminder title on the last day a document is good for travel (a passport, six months before it expires)")
        case 1: return String(localized: "Mâine e ultima zi bună de călătorit: \(title)", comment: "Reminder title the day before a document stops being good for travel")
        default:
            let phrase = DurationWording.distance(days: daysBefore, from: fireDate, calendar: calendar)
            return String(localized: "Bun de călătorit încă \(phrase): \(title)", comment: "Reminder title: a document is good for travel for a duration such as '3 luni' or 'o lună', then the deadline.")
        }
    }

    /// The same for a protected category, naming nothing: "Un act e bun de călătorit încă 3 luni".
    static func genericTravelTitle(daysBefore: Int, from fireDate: Date, calendar: Calendar = .current) -> String {
        switch daysBefore {
        case ...0: return String(localized: "Azi e ultima zi în care un act e bun de călătorit", comment: "Generic reminder title on the last day a document is good for travel")
        case 1: return String(localized: "Mâine e ultima zi în care un act e bun de călătorit", comment: "Generic reminder title the day before a document stops being good for travel")
        default:
            let phrase = DurationWording.distance(days: daysBefore, from: fireDate, calendar: calendar)
            return String(localized: "Un act e bun de călătorit încă \(phrase)", comment: "Generic reminder title: a document is good for travel for a duration such as '3 luni'.")
        }
    }

    static func genericTitle(daysBefore: Int, from fireDate: Date, calendar: Calendar = .current) -> String {
        switch daysBefore {
        case ..<0: return String(localized: "Ai o scadență depășită", comment: "Generic reminder title")
        case 0: return String(localized: "Ai o scadență azi", comment: "Generic reminder title")
        case 1: return String(localized: "Ai o scadență mâine", comment: "Generic reminder title")
        default:
            let phrase = DurationWording.distance(days: daysBefore, from: fireDate, calendar: calendar)
            return String(localized: "Ai o scadență \(DurationWording.inside(phrase))", comment: "Generic reminder title: due in a duration such as 'în 7 zile' or 'într-o lună'.")
        }
    }
}
