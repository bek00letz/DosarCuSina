import Foundation

// Plain-language wording for section pages, kept out of the views so it is tested.

/// The label of the full-width "log a visit" button in a section's Istoric pocket.
enum VisitWording {
    /// Worked out from the category: a car goes to the service, a pet to the vet,
    /// a home calls a tradesperson.
    static func buttonTitle(templateKey: String, heroStyle: HeroStyle) -> String {
        switch (heroStyle, templateKey) {
        case (.vehicle, _), (_, BuiltInTemplates.Key.bike):
            return String(localized: "Am fost la service", comment: "Button that logs a visit to the car service.")
        case (.pet, _):
            return String(localized: "Am fost la veterinar", comment: "Button that logs a vet visit.")
        case (.home, _):
            return String(localized: "Am chemat un meseriaș", comment: "Button that logs a tradesperson's visit at home.")
        case (_, BuiltInTemplates.Key.health):
            return String(localized: "Am fost la medic", comment: "Button that logs a doctor's visit.")
        default:
            return String(localized: "Am făcut o lucrare", comment: "Button that logs work done on something.")
        }
    }
}

/// How a reminder profile reads in plain words: "Te anunț cu 30 de zile înainte".
enum ReminderWording {
    static func summary(leadDays: [Int], locale: Locale = .dosarDefault) -> String {
        let days = Array(Set(leadDays.filter { $0 >= 0 })).sorted(by: >)
        guard !days.isEmpty else {
            return String(localized: "Nu te anunț, doar îl vezi în listă", comment: "Reminder summary when an obligation has no reminders.")
        }
        let parts = days.map(part)
        let joined = parts.formatted(.list(type: .and).locale(locale))
        return String(localized: "Te anunț \(joined)", comment: "Reminder summary, e.g. 'Te anunț cu 30 de zile înainte și în ziua respectivă'.")
    }

    private static func part(_ days: Int) -> String {
        switch days {
        case 0: return String(localized: "în ziua respectivă", comment: "Reminder on the due day.")
        case 1: return String(localized: "cu o zi înainte", comment: "Reminder one day before.")
        default: return String(localized: "cu \(DayCount.phrase(days)) înainte", comment: "Reminder N days before.")
        }
    }
}

/// "1 an", "3 ani", "20 de ani"; "1 lună", "5 luni", "20 de luni".
enum CalendarCount {
    static func years(_ count: Int) -> String {
        String(localized: "\(abs(count)) ani", comment: "A number of years, with Romanian plural forms.")
    }

    static func months(_ count: Int) -> String {
        String(localized: "\(abs(count)) luni", comment: "A number of months, with Romanian plural forms.")
    }
}

/// A pet's or a person's age in plain words: "3 ani", "1 an și 4 luni", "5 luni".
enum AgeWording {
    static func text(born: CalendarDay, today: CalendarDay, calendar: Calendar = .current) -> String? {
        guard born <= today else { return nil }
        let parts = calendar.dateComponents([.year, .month], from: born.startDate(in: calendar), to: today.startDate(in: calendar))
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        if years == 0 {
            return months == 0
                ? String(localized: "sub o lună", comment: "Age younger than one month.")
                : CalendarCount.months(months)
        }
        // Months stop mattering once someone is a few years old.
        if months == 0 || years >= 3 { return CalendarCount.years(years) }
        return String(localized: "\(CalendarCount.years(years)) și \(CalendarCount.months(months))", comment: "Age in years and months, e.g. '1 an și 4 luni'.")
    }
}

/// The "last time" line for a component in the Istoric pocket:
/// "acum 18.200 km · 14 mar. 2025 · 420 lei".
enum ComponentLine {
    static func detail(_ occurrence: ComponentOccurrence, unit: String?, locale: Locale = .dosarDefault, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let since = occurrence.metricSince, let unit, !unit.isEmpty {
            let distance = since.formatted(.number.locale(locale).precision(.fractionLength(0)))
            parts.append(String(localized: "acum \(distance) \(unit)", comment: "How far the counter has moved since a job, e.g. 'acum 18.200 km'."))
        }
        parts.append(occurrence.date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))
        if let cost = occurrence.cost {
            parts.append(cost.formattedCompact(locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}

/// What a section has cost, per currency, for the Bani pocket.
struct MoneySummary: Equatable {
    var allTime: MoneyTotals
    var lastTwelveMonths: MoneyTotals
    var jobCount: Int

    static func make(entries: [(date: Date, cost: MoneyTotals)], now: Date, calendar: Calendar = .current) -> MoneySummary {
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        var all = MoneyTotals()
        var recent = MoneyTotals()
        var count = 0
        for entry in entries where !entry.cost.isEmpty {
            count += 1
            for amount in entry.cost.amounts {
                all.add(amount)
                if entry.date >= yearAgo { recent.add(amount) }
            }
        }
        return MoneySummary(allTime: all, lastTwelveMonths: recent, jobCount: count)
    }
}
