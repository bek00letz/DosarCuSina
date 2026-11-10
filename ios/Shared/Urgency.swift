import Foundation

// The one urgency rule. The app and the widget both compile this file, so Urmează,
// a section's page, the binder's boxes, the badge, the widget and Siri all say the
// same thing about the same deadline. Screens take the result and only draw it.

/// How close a due day is, in the steps every surface shows.
public enum AttentionUrgency: String, Sendable, Comparable, CaseIterable {
    /// Past due and past its grace period: show it as a problem.
    case overdue
    case today
    /// Past due but within the grace the person can live with (a cat vaccine a
    /// couple of days late). Shown calmly, not as an alarm.
    case withinGrace
    /// Its first reminder has gone out (at most its consequence's window ahead):
    /// it needs the person now. Listed under "Acum".
    case soon
    /// Within the next month, but nothing has reminded yet. Listed under "Curând".
    case upcoming
    case later

    private var order: Int {
        switch self {
        case .overdue: return 0
        case .today: return 1
        case .withinGrace: return 2
        case .soon: return 3
        case .upcoming: return 4
        case .later: return 5
        }
    }

    /// Counted on the app's badge: late past grace, or due today.
    public var isAlarming: Bool { self == .overdue || self == .today }

    /// Needs the person now: listed under "Acum", shown on its box, drawn in a warning tone.
    public var needsAttentionNow: Bool { self <= .soon }

    /// The tone every surface draws it in.
    public var tone: UrgencyTone {
        switch self {
        case .overdue: return .overdue
        case .today, .withinGrace, .soon: return .soon
        case .upcoming, .later: return .calm
        }
    }

    public static func < (lhs: AttentionUrgency, rhs: AttentionUrgency) -> Bool { lhs.order < rhs.order }
}

/// The tone an urgency is drawn in. Decided here; the design system and the widget
/// only pick their colours and symbols for it.
public enum UrgencyTone: String, Sendable {
    /// Late past its grace: red, with an exclamation mark.
    case overdue
    /// Needs the person now (due today, late within grace, or reminded): amber, with a clock.
    case soon
    /// Nothing to do yet.
    case calm
}

/// How far ahead a reminder goes, as the person reads it. A lead of a whole number
/// of months (30 days each, a year being 365) is that many calendar months, so
/// "Cu 6 luni înainte" fires on the same day of the month six months before, and
/// the reminder that day reads "În 6 luni", never rounded up. Any other lead is days.
public enum ReminderLead: Hashable, Sendable {
    case days(Int)
    case months(Int)

    public init(days: Int) {
        let n = abs(days)
        if n >= 365, n % 365 == 0 {
            self = .months(n / 365 * 12)
        } else if n >= 30, n % 30 == 0 {
            self = .months(n / 30)
        } else {
            self = .days(n)
        }
    }

    /// The day this lead before `due` falls on.
    public func day(before due: CalendarDay, calendar: Calendar = .dosar) -> CalendarDay {
        switch self {
        case .days(let n): return due.adding(days: -n, calendar: calendar)
        case .months(let n): return due.adding(months: -n, calendar: calendar)
        }
    }

    /// "7 zile", "o lună", "6 luni", "un an", "un an și 6 luni".
    public var wording: String {
        switch self {
        case .days(let n): return DayCount.phrase(n)
        case .months(let n): return DurationWording.yearsAndMonths(years: n / 12, months: n % 12)
        }
    }
}

/// The one rule for how urgent a deadline is, from its reminder profile:
/// - late within its grace days is calm ("withinGrace"), later than that is overdue;
/// - it needs the person from the day its first reminder goes out, but never
///   earlier than its consequence's window (an ID card that reminds three months
///   ahead joins "Acum" only in its last month);
/// - a document that stops being good for travel before it expires (a passport, six
///   months before) has a travel cut-off: its reminders count back from the cut-off,
///   and from the cut-off on it needs the person, whatever its consequence's window;
/// - otherwise it is upcoming within a month (of its cut-off, when it has one), later after that.
///
/// The widget gets it in the snapshot, so it counts down the same way at every midnight.
public struct UrgencyRule: Hashable, Sendable, Codable {
    /// Days after the due day that are still fine.
    public var graceDays: Int
    /// The earliest reminder, in days before the day reminders count from (the travel
    /// cut-off when there is one, else the due day); 0 when it reminds only on that day.
    public var firstLeadDays: Int
    /// The furthest ahead its consequence lets it ask for attention, in days (30 is a month).
    public var maxWindowDays: Int
    /// How long before the due day the document stops being good for travel, in days
    /// (whole months as calendar months, like a lead: 180 is six months); 0 when it is
    /// good for travel until it expires. Declared by the document type (`DocumentType.travelMarginDays`).
    public var travelMarginDays: Int

    /// What "Curând" covers: the next month.
    public static let upcomingWindowDays = 30

    /// A date nothing reminds about: urgent only on the day and once it has passed.
    public static let noReminders = UrgencyRule(graceDays: 0, firstLeadDays: 0, maxWindowDays: 0)

    public init(graceDays: Int, firstLeadDays: Int, maxWindowDays: Int, travelMarginDays: Int = 0) {
        self.graceDays = max(0, graceDays)
        self.firstLeadDays = max(0, firstLeadDays)
        self.maxWindowDays = max(0, maxWindowDays)
        self.travelMarginDays = max(0, travelMarginDays)
    }

    /// The last day a document with a travel margin is good for travel ("Bun de călătorit
    /// până pe …"): the margin before its due day, the last valid day. Nil when it is good
    /// for travel until it expires.
    public func travelCutoff(before due: CalendarDay, calendar: Calendar = .dosar) -> CalendarDay? {
        guard travelMarginDays > 0 else { return nil }
        return ReminderLead(days: travelMarginDays).day(before: due, calendar: calendar)
    }

    /// The day its reminders count back from: the travel cut-off, else the due day.
    public func reminderAnchor(for due: CalendarDay, calendar: Calendar = .dosar) -> CalendarDay {
        travelCutoff(before: due, calendar: calendar) ?? due
    }

    /// The first day it needs the person: the later of its first reminder (at least the
    /// day before) and its consequence's window, and never later than its travel cut-off.
    /// A rule with no window and no cut-off starts on the due day.
    public func attentionStart(before due: CalendarDay, calendar: Calendar = .dosar) -> CalendarDay {
        let cutoff = travelCutoff(before: due, calendar: calendar)
        guard maxWindowDays > 0 else { return cutoff ?? due }
        let reminded = ReminderLead(days: max(firstLeadDays, 1)).day(before: reminderAnchor(for: due, calendar: calendar), calendar: calendar)
        let window = ReminderLead(days: maxWindowDays).day(before: due, calendar: calendar)
        let capped = max(reminded, window)
        return cutoff.map { min(capped, $0) } ?? capped
    }

    /// How many days ahead of `due` it needs the person.
    public func windowDays(before due: CalendarDay, calendar: Calendar = .dosar) -> Int {
        attentionStart(before: due, calendar: calendar).days(to: due, calendar: calendar)
    }

    public func urgency(of due: CalendarDay, today: CalendarDay, calendar: Calendar = .dosar) -> AttentionUrgency {
        let days = today.days(to: due, calendar: calendar)
        if days < 0 { return -days <= graceDays ? .withinGrace : .overdue }
        if days == 0 { return .today }
        if today >= attentionStart(before: due, calendar: calendar) { return .soon }
        if today.days(to: reminderAnchor(for: due, calendar: calendar), calendar: calendar) <= Self.upcomingWindowDays { return .upcoming }
        return .later
    }

    private enum CodingKeys: String, CodingKey { case graceDays, firstLeadDays, maxWindowDays, travelMarginDays }

    /// A snapshot written before the travel margin existed reads as having none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            graceDays: try c.decode(Int.self, forKey: .graceDays),
            firstLeadDays: try c.decode(Int.self, forKey: .firstLeadDays),
            maxWindowDays: try c.decode(Int.self, forKey: .maxWindowDays),
            travelMarginDays: try c.decodeIfPresent(Int.self, forKey: .travelMarginDays) ?? 0
        )
    }
}
