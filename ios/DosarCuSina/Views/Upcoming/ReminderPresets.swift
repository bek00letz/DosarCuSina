import Foundation

/// The simple choices on "Când te anunț", and how lead days read in plain words.
///
/// Lead days are the obligation's own (`ReminderProfile.leadDays`); presets are
/// only a friendlier way to pick them. A profile from a blueprint may hold
/// other values (a passport's 90 days): those show as their own rows, worded
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
    /// A lead in words: "o zi", "7 zile", "o lună", "6 luni", "un an". The one wording
    /// for leads (`DurationWording.lead`), so the reminder that fires reads the same.
    static func phrase(days: Int) -> String {
        DurationWording.lead(days: days)
    }

    /// The day a profile's leads count back from, as the person reads it: the due day, or
    /// for a document with a travel cut-off (a passport) the last day it is good for travel.
    enum Anchor: Sendable {
        case dueDay
        case travelCutoff

        init(_ profile: ReminderProfile) {
            self = profile.hasTravelCutoff ? .travelCutoff : .dueDay
        }
    }

    /// The row title for one lead: "În ziua termenului", "Cu 7 zile înainte", and for a
    /// passport "În ultima zi bună de călătorit".
    static func rowTitle(days: Int, from anchor: Anchor) -> String {
        guard days == 0 else {
            return String(localized: "Cu \(phrase(days: days)) înainte", comment: "Reminder choice: this long before the due day")
        }
        switch anchor {
        case .dueDay: return String(localized: "În ziua termenului", comment: "Reminder choice: on the due day")
        case .travelCutoff: return String(localized: "În ultima zi bună de călătorit", comment: "Reminder choice: on the last day a passport is good for travel")
        }
    }

    /// "Te anunț cu o lună și cu 7 zile înainte și în ziua termenului." For a passport:
    /// "Te anunț cu 3 luni înainte de ultima zi bună de călătorit și în ziua aceea."
    static func sentence(_ profile: ReminderProfile) -> String {
        let leadDays = profile.leadDays
        let before = leadDays.filter { $0 > 0 }.sorted(by: >).map { String(localized: "cu \(phrase(days: $0))", comment: "Part of the reminder sentence") }
        let onTheDay = leadDays.contains(0)
        guard !before.isEmpty else {
            guard onTheDay else { return String(localized: "Nu te anunț dinainte.", comment: "Reminder sentence: no reminders chosen") }
            switch Anchor(profile) {
            case .dueDay: return String(localized: "Te anunț în ziua termenului.", comment: "Reminder sentence: only on the due day")
            case .travelCutoff: return String(localized: "Te anunț în ultima zi bună de călătorit.", comment: "Reminder sentence: only on the last day a passport is good for travel")
            }
        }
        let list = before.formatted(.list(type: .and).locale(.dosarDefault))
        switch Anchor(profile) {
        case .dueDay:
            return onTheDay
                ? String(localized: "Te anunț \(list) înainte și în ziua termenului.", comment: "Reminder sentence: leads before, and on the day")
                : String(localized: "Te anunț \(list) înainte.", comment: "Reminder sentence: leads before the due day")
        case .travelCutoff:
            return onTheDay
                ? String(localized: "Te anunț \(list) înainte de ultima zi bună de călătorit și în ziua aceea.", comment: "Reminder sentence for a passport: leads before the last day it is good for travel, and on that day")
                : String(localized: "Te anunț \(list) înainte de ultima zi bună de călătorit.", comment: "Reminder sentence for a passport: leads before the last day it is good for travel")
        }
    }

    /// "Bun de călătorit până pe 12 februarie 2031." for a document with a travel cut-off
    /// expiring on `day`; nil for every other document.
    static func travelLine(expiring day: CalendarDay, profile: ReminderProfile, today: CalendarDay, calendar: Calendar = .dosar) -> String? {
        guard let cutoff = profile.urgencyRule.travelCutoff(before: day, calendar: calendar) else { return nil }
        return String(localized: "Bun de călătorit până pe \(DueWording.date(cutoff, today: today)).", comment: "A passport's last day good for travel, six months before it expires")
    }

    /// "Expiră pe 12 august 2031. Te anunț cu 3 luni și cu o lună înainte." The line
    /// under an expiry date, shown before saving so the reminder is never a surprise. A
    /// passport's says when it stops being good for travel too. A document whose validity
    /// follows its issue by a rule (`validityMonths`: a cazier judiciar) says so instead of
    /// "Expiră pe".
    static func expiryLine(_ day: CalendarDay, profile: ReminderProfile, today: CalendarDay, validityMonths: Int? = nil,
                           calendar: Calendar = .dosar) -> String {
        let date = DueWording.date(day, today: today)
        let opening = validityMonths.map { validityOpening(day, months: $0, today: today) } ?? String(localized: "Expiră pe \(date).")
        return [opening, travelLine(expiring: day, profile: profile, today: today, calendar: calendar), sentence(profile)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// "E valabil până pe 15 aprilie 2027, la 6 luni de la eliberare." A validity worked out
    /// from the issue date by the document's rule, not printed on it. The one wording, for
    /// "Scriu eu" and capture's review.
    static func validityOpening(_ day: CalendarDay, months: Int, today: CalendarDay) -> String {
        let date = DueWording.date(day, today: today)
        return String(localized: "E valabil până pe \(date), la \(CalendarCount.months(months)) de la eliberare.",
                      comment: "Capture review: a document's validity worked out from its issue date, e.g. „la 6 luni de la eliberare”.")
    }

    /// The follow-up line under the sentence, when it is on.
    static let followUp = String(localized: "Dacă nu e rezolvat, îți mai amintesc o dată a doua zi după termen.", comment: "Reminder sentence: follow-up after the due date")
}
