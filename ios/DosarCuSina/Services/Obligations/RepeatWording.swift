import Foundation

/// How a deadline repeats, in words: the one wording for "Se repetă" in the deadline form,
/// the deadline's page and the confirmations after a change. Counts go through the String
/// Catalog's plural variations („În fiecare zi”, „La fiecare 3 zile”, „La fiecare 20 de zile”).
enum RepeatWording {
    /// The choices of "Se repetă".
    static func title(of frequency: RepeatChoice.Frequency) -> String {
        switch frequency {
        case .never: String(localized: "Nu se repetă", comment: "Repeat choice: a deadline that happens once.")
        case .day: String(localized: "Zilnic", comment: "Repeat choice: every day or every few days.")
        case .week: String(localized: "Săptămânal", comment: "Repeat choice: every week or every few weeks.")
        case .month: String(localized: "Lunar", comment: "Repeat choice: every month or every few months.")
        case .year: String(localized: "Anual", comment: "Repeat choice: every year or every few years.")
        }
    }

    /// „În fiecare zi”, „La fiecare 3 zile”, „În fiecare lună”, „La fiecare 2 ani”: how often,
    /// at the start of a sentence.
    static func every(_ count: Int, _ unit: RecurrenceInterval.Unit) -> String {
        let n = max(1, count)
        switch unit {
        case .day: return String(localized: "La fiecare \(n) zile", comment: "How often a deadline repeats, in days. Plural forms: În fiecare zi, La fiecare 3 zile, La fiecare 20 de zile.")
        case .week: return String(localized: "La fiecare \(n) săptămâni", comment: "How often a deadline repeats, in weeks. Plural forms: În fiecare săptămână, La fiecare 3 săptămâni, La fiecare 20 de săptămâni.")
        case .month: return String(localized: "La fiecare \(n) luni", comment: "How often a deadline repeats, in months. Plural forms: În fiecare lună, La fiecare 3 luni, La fiecare 20 de luni.")
        case .year: return String(localized: "La fiecare \(n) ani", comment: "How often a deadline repeats, in years. Plural forms: În fiecare an, La fiecare 2 ani, La fiecare 20 de ani.")
        }
    }

    /// „o zi”, „3 zile”, „o lună”, „2 ani”: one step of the repeat.
    static func step(_ count: Int, _ unit: RecurrenceInterval.Unit) -> String {
        switch unit {
        case .day: DayCount.phrase(count)
        case .week: CalendarCount.weeks(count)
        case .month: CalendarCount.months(count)
        case .year: CalendarCount.years(count)
        }
    }

    /// The two ways the next due day is counted, as the control offers them.
    static let anchors: [RecurrenceAnchor] = [.dueDate, .completion]

    static func title(of anchor: RecurrenceAnchor) -> String {
        switch anchor {
        case .dueDate: String(localized: "De la data termenului", comment: "Repeat: the next due day counts from this one's due day.")
        case .completion: String(localized: "De la data la care l-ai făcut", comment: "Repeat: the next due day counts from the day the deadline was done.")
        }
    }

    /// What each way means for the next due day, with this choice's step: „Următorul e la
    /// 3 zile după ce îl bifezi.”
    static func detail(of anchor: RecurrenceAnchor, every count: Int, _ unit: RecurrenceInterval.Unit) -> String {
        let step = step(count, unit)
        switch anchor {
        case .dueDate:
            return String(localized: "Următorul e la \(step) după termen, oricând îl bifezi.", comment: "Repeat counted from the due day: the next one is this long after the due day, whenever it is ticked off.")
        case .completion:
            return String(localized: "Următorul e la \(step) după ce îl bifezi.", comment: "Repeat counted from the day it was done: the next one is this long after it is ticked off.")
        }
    }

    /// The rule in one sentence, for every kind of rule: „La fiecare 3 zile, de la data la care
    /// l-ai făcut.”, „În fiecare an, pe 31 martie și pe 30 septembrie.”, „Nu se repetă.”
    static func sentence(_ rule: RecurrenceRule) -> String {
        String(localized: "\(phrase(rule)).", comment: "How a deadline repeats, as a sentence: the words of the rule and a full stop.")
    }

    /// The rule in words, without the full stop, to go on in a line: „La fiecare 3 zile, de la
    /// data la care l-ai făcut · Îți amintesc …” (`ReminderWording.schedule`).
    static func phrase(_ rule: RecurrenceRule) -> String {
        switch rule {
        case .none:
            return String(localized: "Nu se repetă", comment: "How a deadline repeats: once.")
        case .interval(let interval, let anchor):
            let often = every(interval.every, interval.unit)
            switch anchor {
            case .dueDate:
                return String(localized: "\(often), de la data termenului", comment: "How a deadline repeats, counted from its due day, e.g. „În fiecare lună, de la data termenului.”")
            case .completion:
                return String(localized: "\(often), de la data la care l-ai făcut", comment: "How a deadline repeats, counted from the day it was done, e.g. „La fiecare 3 zile, de la data la care l-ai făcut.”")
            }
        case .fixedDates(let dates):
            let days = dates.sorted().map { date in
                // A leap year, so 29 February is written as itself.
                String(localized: "pe \(DosarFormat.dayMonth(CalendarDay(year: 2000, month: date.month, day: date.day)))", comment: "Part of a repeat sentence: on a day of the year, e.g. „pe 31 martie”.")
            }
            let list = days.formatted(.list(type: .and).locale(.dosarDefault))
            return String(localized: "În fiecare an, \(list)", comment: "A deadline due on the same days every year, e.g. „În fiecare an, pe 31 martie și pe 30 septembrie.”")
        case .metric(let every, let unit, let fallback):
            let counter = MeasurementUnit.written(every, in: unit)
            guard let fallback else {
                return String(localized: "La fiecare \(counter)", comment: "A deadline due every so much of a counter, e.g. „La fiecare 10.000 km.”")
            }
            let often = Self.midSentence(Self.every(fallback.every, fallback.unit))
            return String(localized: "La fiecare \(counter) sau \(often), ce vine mai întâi", comment: "A deadline due every so much of a counter or after a time, e.g. „La fiecare 10.000 km sau în fiecare an, ce vine mai întâi.”")
        case .legal(let legal):
            switch legal {
            case .vehicleITP:
                return String(localized: "Cum cere legea pentru ITP, după vârsta mașinii și cum o folosești", comment: "How the ITP repeats: by the legal rule, from the car's age and use.")
            }
        case .unreadable:
            return String(localized: "Se repetă după o regulă pe care o știe o versiune mai nouă a aplicației. Actualizează aplicația ca s-o vezi", comment: "A repeat rule written by a newer version of the app.")
        }
    }

    /// The same words in the middle of a sentence: „în fiecare an”.
    private static func midSentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).lowercased(with: .dosarDefault) + text.dropFirst()
    }
}
