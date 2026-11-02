import Foundation

// Plain-language wording for section pages, kept out of the views so it is tested.

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
        return DurationWording.yearsAndMonths(years: years, months: months)
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
