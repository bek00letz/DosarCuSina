import Foundation

/// What the engine knows about an asset when it works out the next date.
public struct RecurrenceContext: Sendable {
    public var assetValues: FieldValues
    /// Counter readings (odometer, shots), oldest first.
    public var readings: [CadenceCalculator.TelemetryReading]
    /// The counter now, when known.
    public var currentMetric: Double?
    /// The day of the month a series counted from its due dates keeps (31 for
    /// "the 31st"), from `RecurrenceEngine.seriesStart`. Nil uses the due day's own.
    public var seriesDayOfMonth: Int?

    public init(
        assetValues: FieldValues = FieldValues(),
        readings: [CadenceCalculator.TelemetryReading] = [],
        currentMetric: Double? = nil,
        seriesDayOfMonth: Int? = nil
    ) {
        self.assetValues = assetValues
        self.readings = readings
        self.currentMetric = currentMetric
        self.seriesDayOfMonth = seriesDayOfMonth
    }
}

/// The next cycle of a repeating obligation.
public struct NextDue: Hashable, Sendable {
    public var day: CalendarDay
    /// For counter-based obligations, the reading at which it is due.
    public var metric: Double?
}

/// Pure date math for obligations: first due dates from blueprints and the
/// next due date after a completion. All calendar arithmetic goes through
/// `CadenceCalculator`, which handles month ends and 29 February.
///
/// A series counted from its due dates remembers its day of the month: every
/// date is that day, or the month's last day when the month is shorter, so a
/// payment on the 31st is due on 28 February and on 31 March again.
public enum RecurrenceEngine {

    /// Counter-based obligations without a calendar fallback are re-checked after this long.
    public static let defaultMetricFallback = RecurrenceInterval.months(6)

    // MARK: Next cycle

    /// The next due date after completing the cycle due on `due`, or nil for one-off rules.
    public static func nextDue(
        after due: CalendarDay,
        completedOn: CalendarDay,
        rule: RecurrenceRule,
        context: RecurrenceContext = RecurrenceContext(),
        calendar: Calendar = .current
    ) -> NextDue? {
        switch rule {
        case .none:
            return nil

        case .interval(let interval, .dueDate):
            return NextDue(day: add(interval, to: due, dayOfMonth: context.seriesDayOfMonth, calendar: calendar))

        case .interval(let interval, .completion):
            return NextDue(day: add(interval, to: completedOn, calendar: calendar))

        case .fixedDates(let dates):
            guard !dates.isEmpty else { return nil }
            return NextDue(day: nextFixedDate(after: due, dates: dates, calendar: calendar))

        case .metric(let every, _, let fallback):
            let reading = context.currentMetric ?? context.readings.last?.metric
            let fallbackDay = add(fallback ?? defaultMetricFallback, to: completedOn, calendar: calendar)
            guard let reading else { return NextDue(day: fallbackDay, metric: nil) }
            let target = reading + every
            let projected = CadenceCalculator.projectTelemetryDueDate(
                currentMetric: reading,
                targetMetric: target,
                readings: context.readings,
                currentDate: completedOn.noonDate(in: calendar),
                calendar: calendar
            ).map { CalendarDay($0.estimatedDueDate, calendar: calendar) }
            // Due at the counter target or the calendar fallback, whichever comes first.
            let day = projected.map { min($0, fallbackDay) } ?? fallbackDay
            return NextDue(day: max(day, completedOn.adding(days: 1, calendar: calendar)), metric: target)

        case .legal(let legalRule):
            switch legalRule {
            case .vehicleITP:
                let interval = itpInterval(values: context.assetValues, on: completedOn)
                return NextDue(day: add(interval, to: completedOn, calendar: calendar))
            }
        }
    }

    // MARK: First cycle

    /// The first due date for a blueprint, or nil when the person has to enter it
    /// (`.ask`) or the field it depends on is empty.
    public static func firstDue(
        for blueprint: ObligationBlueprint,
        values: FieldValues,
        today: CalendarDay,
        calendar: Calendar = .current
    ) -> CalendarDay? {
        switch blueprint.firstDue {
        case .ask:
            return nil
        case .field(let key, let offset):
            guard let day = values[key]?.dateValue else { return nil }
            return day.adding(days: offset, calendar: calendar)
        case .afterInterval(let interval):
            return add(interval, to: today, calendar: calendar)
        case .nextFixedDate:
            guard case .fixedDates(let dates) = blueprint.recurrence, !dates.isEmpty else { return nil }
            return nextFixedDate(onOrAfter: today, dates: dates, calendar: calendar)
        }
    }

    // MARK: Building blocks

    /// `day` moved on by `interval`. Months and years land on `dayOfMonth` (the
    /// series' day), or the month's last day when it is shorter; without it, on
    /// `day`'s own day.
    public static func add(_ interval: RecurrenceInterval, to day: CalendarDay, dayOfMonth: Int? = nil, calendar: Calendar = .current) -> CalendarDay {
        let start = day.noonDate(in: calendar)
        let next: Date
        switch interval.unit {
        case .day: next = CadenceCalculator.calculateNextDueDate(from: start, interval: .days(interval.every), calendar: calendar)
        case .week: next = CadenceCalculator.calculateNextDueDate(from: start, interval: .weeks(interval.every), calendar: calendar)
        case .month: next = CadenceCalculator.addMonths(to: start, months: interval.every, dayOfMonth: dayOfMonth, calendar: calendar)
        case .year: next = CadenceCalculator.addMonths(to: start, months: interval.every * 12, dayOfMonth: dayOfMonth, calendar: calendar)
        }
        return CalendarDay(next, calendar: calendar)
    }

    /// One completion as the series sees it: the cycle it closed and the due day it moved to.
    public struct SeriesStep: Hashable, Sendable {
        public var cycle: CalendarDay?
        public var next: CalendarDay?

        public init(cycle: CalendarDay?, next: CalendarDay?) {
            self.cycle = cycle
            self.next = next
        }
    }

    /// The first due day of the unbroken series `current` belongs to. Walks back
    /// through the completions, newest first, while each one moved the date to the
    /// cycle after it; a due day the person set by hand starts a new series. Its day
    /// of the month is the day the series keeps.
    public static func seriesStart(current: CalendarDay, completions: [SeriesStep]) -> CalendarDay {
        var start = current
        for step in completions {
            guard let next = step.next, next == start, let cycle = step.cycle else { break }
            start = cycle
        }
        return start
    }

    /// The first of `dates` strictly after `day`.
    public static func nextFixedDate(after day: CalendarDay, dates: [MonthDay], calendar: Calendar = .current) -> CalendarDay {
        nextFixedDate(onOrAfter: day.adding(days: 1, calendar: calendar), dates: dates, calendar: calendar)
    }

    /// The first of `dates` on or after `day`.
    public static func nextFixedDate(onOrAfter day: CalendarDay, dates: [MonthDay], calendar: Calendar = .current) -> CalendarDay {
        let candidates = [day.year, day.year + 1].flatMap { year in
            dates.map { $0.day(inYear: year, calendar: calendar) }
        }
        return candidates.filter { $0 >= day }.min() ?? day
    }

    /// ITP interval for a passenger car (OUG 195/2002, RNTR 1): every 6 months for
    /// ridesharing and taxis; otherwise every 2 years while the car is at most 12
    /// years old and every year after. An unknown age gets the shorter interval,
    /// so a reminder is never late.
    public static func itpInterval(values: FieldValues, on day: CalendarDay) -> RecurrenceInterval {
        if values["vehicle.usage"]?.textValue.flatMap({ VehicleUse.options.option(for: $0)?.key }) == VehicleUse.commercial {
            return .months(6)
        }
        guard let year = values["vehicle.year"]?.numberValue else { return .years(1) }
        let age = day.year - Int(year)
        return age <= 12 ? .years(2) : .years(1)
    }
}
