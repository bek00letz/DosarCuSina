import Foundation

/// When something is due, in plain words: "Expiră în 5 zile · 7 noiembrie".
enum DueWording {
    /// "în 5 zile", "azi", "mâine", "acum 3 zile".
    static func relative(daysRemaining days: Int) -> String {
        switch days {
        case -1: return String(localized: "ieri", comment: "Due: yesterday")
        case ..<0: return String(localized: "acum \(DurationWording.phrase(days: days))", comment: "Due: this long ago")
        case 0: return String(localized: "azi", comment: "Due: today")
        case 1: return String(localized: "mâine", comment: "Due: tomorrow")
        default: return String(localized: "în \(DurationWording.phrase(days: days))", comment: "Due: in this long")
        }
    }

    /// "7 noiembrie", with the year when it isn't this year. Written as the day
    /// it is, whatever the phone's time zone.
    static func date(_ day: CalendarDay, today: CalendarDay) -> String {
        day.year == today.year ? DosarFormat.dayMonth(day) : DosarFormat.longDay(day)
    }

    /// The verb for the deadline, by what kind of duty it is.
    static func verb(for kind: ObligationKind, daysRemaining days: Int) -> String {
        let late = days < 0
        switch kind {
        case .legal, .insurance, .renewal:
            return late ? String(localized: "A expirat", comment: "Due line verb, past") : String(localized: "Expiră", comment: "Due line verb")
        case .tax, .payment:
            return late ? String(localized: "Trebuia plătit", comment: "Due line verb, past") : String(localized: "De plătit", comment: "Due line verb")
        case .health, .maintenance, .routine:
            return late ? String(localized: "Trebuia făcut", comment: "Due line verb, past") : String(localized: "De făcut", comment: "Due line verb")
        }
    }

    /// "Expiră în 5 zile · 7 noiembrie", "De plătit azi · 2 noiembrie", "A expirat acum 3 zile · 30 octombrie".
    static func line(kind: ObligationKind, due: CalendarDay, today: CalendarDay, calendar: Calendar = .current) -> String {
        let days = today.days(to: due, calendar: calendar)
        return "\(verb(for: kind, daysRemaining: days)) \(relative(daysRemaining: days)) · \(date(due, today: today))"
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
