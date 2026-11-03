import Foundation

/// The simple choices on "Când te anunț", and how lead days read in plain words.
///
/// Lead days are the obligation's own (`ReminderProfile.leadDays`); presets are
/// only a friendlier way to pick them. A profile from a blueprint may hold
/// other values (a passport's 180 days): those show as their own rows, worded
/// the same way, so nothing the engine knows is hidden.
enum ReminderPreset: Int, CaseIterable, Identifiable, Sendable {
    case dueDay = 0
    case oneDay = 1
    case oneWeek = 7
    case twoWeeks = 14
    case oneMonth = 30
    case twoMonths = 60

    var id: Int { rawValue }
    var days: Int { rawValue }

    /// The rows offered, largest lead first, with any other values the profile holds.
    static func rows(for leadDays: [Int]) -> [Int] {
        Array(Set(allCases.map(\.days) + leadDays)).sorted(by: >)
    }

    /// Lead days with `days` switched on or off, kept in the engine's order (largest first).
    static func toggling(_ days: Int, in leadDays: [Int]) -> [Int] {
        var set = Set(leadDays)
        if set.contains(days) { set.remove(days) } else { set.insert(days) }
        return set.sorted(by: >)
    }
}

enum ReminderWording {
    /// "o zi", "5 zile", "o săptămână", "două săptămâni", "o lună", "6 luni", "un an".
    static func phrase(days: Int) -> String {
        let days = abs(days)
        if days > 0, days % 365 == 0 { return years(days / 365) }
        if days >= 30, days % 30 == 0 { return months(days / 30) }
        if days >= 7, days % 7 == 0 { return weeks(days / 7) }
        if days == 1 { return String(localized: "o zi", comment: "Reminder lead: one day") }
        return DayCount.phrase(days)
    }

    /// The row title for one lead: "În ziua termenului", "Cu o săptămână înainte".
    static func rowTitle(days: Int) -> String {
        days == 0
            ? String(localized: "În ziua termenului", comment: "Reminder choice: on the due day")
            : String(localized: "Cu \(phrase(days: days)) înainte", comment: "Reminder choice: this long before the due day")
    }

    /// "Te anunț cu o lună și cu o săptămână înainte, și în ziua termenului."
    static func sentence(leadDays: [Int]) -> String {
        let before = leadDays.filter { $0 > 0 }.sorted(by: >).map { String(localized: "cu \(phrase(days: $0))", comment: "Part of the reminder sentence") }
        let onTheDay = leadDays.contains(0)
        if before.isEmpty {
            return onTheDay
                ? String(localized: "Te anunț în ziua termenului.", comment: "Reminder sentence: only on the due day")
                : String(localized: "Nu te anunț dinainte.", comment: "Reminder sentence: no reminders chosen")
        }
        let list = before.formatted(.list(type: .and).locale(.dosarDefault))
        return onTheDay
            ? String(localized: "Te anunț \(list) înainte și în ziua termenului.", comment: "Reminder sentence: leads before, and on the day")
            : String(localized: "Te anunț \(list) înainte.", comment: "Reminder sentence: leads before the due day")
    }

    /// "Expiră pe 12 august 2031. Te anunț cu 3 luni și cu o lună înainte." The line
    /// under an expiry date, shown before saving so the reminder is never a surprise.
    static func expiryLine(_ day: CalendarDay, leadDays: [Int], today: CalendarDay) -> String {
        let date = DueWording.date(day, today: today)
        return String(localized: "Expiră pe \(date).") + " " + sentence(leadDays: leadDays)
    }

    /// The follow-up line under the sentence, when it is on.
    static let followUp = String(localized: "Dacă nu e rezolvat, îți mai amintesc o dată a doua zi după termen.", comment: "Reminder sentence: follow-up after the due date")

    private static func months(_ n: Int) -> String {
        switch n {
        case 1: return String(localized: "o lună", comment: "Reminder lead: one month")
        case 2: return String(localized: "două luni", comment: "Reminder lead: two months")
        case 3...19: return String(localized: "\(n) luni", comment: "Reminder lead: 3–19 months")
        default: return String(localized: "\(n) de luni", comment: "Reminder lead: 20 or more months")
        }
    }

    private static func weeks(_ n: Int) -> String {
        switch n {
        case 1: return String(localized: "o săptămână", comment: "Reminder lead: one week")
        case 2: return String(localized: "două săptămâni", comment: "Reminder lead: two weeks")
        case 3...19: return String(localized: "\(n) săptămâni", comment: "Reminder lead: 3–19 weeks")
        default: return String(localized: "\(n) de săptămâni", comment: "Reminder lead: 20 or more weeks")
        }
    }

    private static func years(_ n: Int) -> String {
        switch n {
        case 1: return String(localized: "un an", comment: "Reminder lead: one year")
        case 2: return String(localized: "doi ani", comment: "Reminder lead: two years")
        case 3...19: return String(localized: "\(n) ani", comment: "Reminder lead: 3–19 years")
        default: return String(localized: "\(n) de ani", comment: "Reminder lead: 20 or more years")
        }
    }
}
