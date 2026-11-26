import Foundation

/// When something is due, in plain words: "Expiră în 5 zile · 7 noiembrie". The words are built
/// from data said first (which verb, how far, whether the year shows, a passport's two dates), so
/// the Android app's `DueLine` and `TravelLines` are pinned against the same choices
/// (`AttentionVectorsTests`).
enum DueWording {
    /// The verb a due line starts with, by what kind of duty it is.
    enum Verb: String, Hashable, Sendable {
        /// "Expiră", past "A expirat".
        case expires
        /// "De plătit", past "Trebuia plătit".
        case pay
        /// "De făcut", past "Trebuia făcut".
        case doIt = "do"
    }

    /// How far a due day is, as the line says it.
    enum When: String, Hashable, Sendable {
        case yesterday, ago, today, tomorrow, inside
    }

    /// A passport's lines, as data: expired, or its expiry and its last day good for travel.
    enum Travel: Hashable, Sendable {
        case expired(on: CalendarDay)
        case valid(expiry: CalendarDay, travelUntil: CalendarDay, stillGood: Bool)
    }

    static func when(daysRemaining days: Int) -> When {
        switch days {
        case -1: .yesterday
        case ..<0: .ago
        case 0: .today
        case 1: .tomorrow
        default: .inside
        }
    }

    /// "în 5 zile", "într-o lună", "azi", "mâine", "acum 3 zile", in the same durations as every
    /// other surface (`DurationWording.distance`).
    static func relative(daysRemaining days: Int, from today: Date = Date(), calendar: Calendar = .dosar) -> String {
        switch when(daysRemaining: days) {
        case .yesterday: return String(localized: "ieri", comment: "Due: yesterday")
        case .ago: return String(localized: "acum \(DurationWording.distance(days: days, from: today, calendar: calendar))", comment: "Due: this long ago")
        case .today: return String(localized: "azi", comment: "Due: today")
        case .tomorrow: return String(localized: "mâine", comment: "Due: tomorrow")
        case .inside: return DurationWording.inside(DurationWording.distance(days: days, from: today, calendar: calendar))
        }
    }

    /// Whether a day is written with its year: when it isn't this year.
    static func showsYear(_ day: CalendarDay, today: CalendarDay) -> Bool {
        day.year != today.year
    }

    /// "7 noiembrie", with the year when it isn't this year. Written as the day
    /// it is, whatever the phone's time zone.
    static func date(_ day: CalendarDay, today: CalendarDay) -> String {
        showsYear(day, today: today) ? DosarFormat.longDay(day) : DosarFormat.dayMonth(day)
    }

    /// Which verb a deadline of this kind takes.
    static func verbKind(for kind: ObligationKind) -> Verb {
        switch kind {
        case .legal, .insurance, .renewal: .expires
        case .tax, .payment: .pay
        case .health, .maintenance, .routine: .doIt
        }
    }

    /// The verb for the deadline, by what kind of duty it is.
    static func verb(for kind: ObligationKind, daysRemaining days: Int) -> String {
        let late = days < 0
        switch verbKind(for: kind) {
        case .expires:
            return late ? String(localized: "A expirat", comment: "Due line verb, past") : String(localized: "Expiră", comment: "Due line verb")
        case .pay:
            return late ? String(localized: "Trebuia plătit", comment: "Due line verb, past") : String(localized: "De plătit", comment: "Due line verb")
        case .doIt:
            return late ? String(localized: "Trebuia făcut", comment: "Due line verb, past") : String(localized: "De făcut", comment: "Due line verb")
        }
    }

    /// "Expiră în 5 zile · 7 noiembrie", "De plătit azi · 2 noiembrie", "A expirat acum 3 zile · 30 octombrie".
    static func line(kind: ObligationKind, due: CalendarDay, today: CalendarDay, calendar: Calendar = .dosar) -> String {
        let days = today.days(to: due, calendar: calendar)
        let when = relative(daysRemaining: days, from: today.startDate(in: calendar), calendar: calendar)
        return "\(verb(for: kind, daysRemaining: days)) \(when) · \(date(due, today: today))"
    }

    /// A document with a travel cut-off (a passport): expired once its day has passed, else its
    /// expiry and its last day good for travel, still ahead or passed. Nil without a cut-off.
    static func travel(due: CalendarDay, rule: UrgencyRule, today: CalendarDay, calendar: Calendar = .dosar) -> Travel? {
        guard let cutoff = rule.travelCutoff(before: due, calendar: calendar) else { return nil }
        guard today <= due else { return .expired(on: due) }
        return .valid(expiry: due, travelUntil: cutoff, stillGood: today <= cutoff)
    }

    /// A document with a travel cut-off (a passport) shows both its dates instead of one due
    /// line: "Expiră pe 12 august 2027" and "Bun de călătorit până pe 12 februarie 2027". Once
    /// the cut-off has passed: "A fost bun de călătorit până pe …"; once it has expired, only
    /// "A expirat pe …". Nil for everything without a cut-off, which keeps `line`.
    static func travelLines(due: CalendarDay, rule: UrgencyRule, today: CalendarDay, calendar: Calendar = .dosar) -> [String]? {
        switch travel(due: due, rule: rule, today: today, calendar: calendar) {
        case nil:
            return nil
        case .expired(let day):
            let expiry = date(day, today: today)
            return [String(localized: "A expirat pe \(expiry)", comment: "A passport's line once it has expired")]
        case .valid(let day, let cutoff, let stillGood):
            let expiry = date(day, today: today)
            let travel = date(cutoff, today: today)
            return [
                String(localized: "Expiră pe \(expiry)", comment: "A passport's expiry, on its page"),
                stillGood
                    ? String(localized: "Bun de călătorit până pe \(travel)", comment: "A passport's last day good for travel, six months before it expires")
                    : String(localized: "A fost bun de călătorit până pe \(travel)", comment: "A passport past its last day good for travel, before it expires"),
            ]
        }
    }

    /// Why it matters, in one plain sentence, from the consequence.
    static func consequence(_ consequence: Consequence) -> String {
        switch consequence {
        case .legal: return String(localized: "Dacă trece termenul, riști amendă sau probleme la control.", comment: "Why a legal deadline matters")
        case .financial: return String(localized: "Dacă întârzii, pot veni penalități sau bani pierduți.", comment: "Why a financial deadline matters")
        case .health: return String(localized: "Ține de sănătate: e mai bine făcut la timp.", comment: "Why a health deadline matters")
        case .comfort: return String(localized: "Nu e grav dacă întârzie puțin.", comment: "Why a comfort deadline matters")
        }
    }
}
