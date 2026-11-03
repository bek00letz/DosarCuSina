import Foundation

/// Pure mathematical and calendar recurrence engine for life cadence calculations.
///
/// Handles calendar recurrence (daily, monthly, yearly with leap year Feb 29 -> Feb 28 clamping)
/// and telemetry projections (odometer km/day, hours/day, cycles/day with rollback guards).
public final class CadenceCalculator: Sendable {
    
    // MARK: - Types
    
    /// Supported calendar recurrence intervals.
    public enum CalendarCadenceInterval: Sendable, Equatable {
        case days(Int)
        case weeks(Int)
        case months(Int)
        case years(Int)
        case annual
    }
    
    /// A single timestamped telemetry observation.
    public struct TelemetryReading: Sendable, Equatable {
        public let date: Date
        public let metric: Double
        
        public init(date: Date, metric: Double) {
            self.date = date
            self.metric = metric
        }
    }
    
    /// Result of a telemetry-based due date projection.
    public struct TelemetryProjection: Sendable, Equatable {
        public let estimatedDueDate: Date
        public let dailyBurnRate: Double
        public let remainingMetric: Double
        public let daysRemaining: Int
        public let isDueImmediately: Bool
        public let isEstimatedFromBaseline: Bool
        public let hasRollbackAnomaly: Bool
        
        public init(
            estimatedDueDate: Date,
            dailyBurnRate: Double,
            remainingMetric: Double,
            daysRemaining: Int,
            isDueImmediately: Bool,
            isEstimatedFromBaseline: Bool,
            hasRollbackAnomaly: Bool
        ) {
            self.estimatedDueDate = estimatedDueDate
            self.dailyBurnRate = dailyBurnRate
            self.remainingMetric = remainingMetric
            self.daysRemaining = daysRemaining
            self.isDueImmediately = isDueImmediately
            self.isEstimatedFromBaseline = isEstimatedFromBaseline
            self.hasRollbackAnomaly = hasRollbackAnomaly
        }
    }
    
    public init() {}
    
    // MARK: - Calendar Cadence Engine
    
    /// Checks whether a given Gregorian year is a leap year.
    public static func isLeapYear(_ year: Int) -> Bool {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }
    
    /// Computes the next calendar due date based on a day-count cadence.
    ///
    /// For annual intervals (365 or 366 days), accurately preserves the anniversary date
    /// and clamps February 29th to February 28th on non-leap years.
    ///
    /// - Parameters:
    ///   - lastDate: The reference or previous due date.
    ///   - cadenceDays: The recurrence interval in days.
    ///   - calendar: Calendar to use for arithmetic (defaults to `.current`).
    /// - Returns: The calculated next due date.
    public static func calculateNextDueDate(
        from lastDate: Date,
        cadenceDays: Int,
        calendar: Calendar = .current
    ) -> Date {
        guard cadenceDays > 0 else { return lastDate }
        
        // Annual recurrence heuristic: 365 or 366 days
        if cadenceDays == 365 || cadenceDays == 366 {
            return addYears(to: lastDate, years: 1, calendar: calendar)
        }
        
        // Biannual recurrence heuristic: 730 or 731 days
        if cadenceDays == 730 || cadenceDays == 731 {
            return addYears(to: lastDate, years: 2, calendar: calendar)
        }
        
        // Standard day addition
        return calendar.date(byAdding: .day, value: cadenceDays, to: lastDate)
            ?? lastDate.addingTimeInterval(Double(cadenceDays) * 86400.0)
    }
    
    /// Computes the next calendar due date based on an explicit cadence interval enum.
    ///
    /// - Parameters:
    ///   - lastDate: The reference date.
    ///   - interval: Recurrence interval (.days, .weeks, .months, .years, .annual).
    ///   - calendar: Calendar instance.
    /// - Returns: The next due date.
    public static func calculateNextDueDate(
        from lastDate: Date,
        interval: CalendarCadenceInterval,
        calendar: Calendar = .current
    ) -> Date {
        switch interval {
        case .days(let days):
            guard days > 0 else { return lastDate }
            return calendar.date(byAdding: .day, value: days, to: lastDate)
                ?? lastDate.addingTimeInterval(Double(days) * 86400.0)
            
        case .weeks(let weeks):
            guard weeks > 0 else { return lastDate }
            return calendar.date(byAdding: .weekOfYear, value: weeks, to: lastDate)
                ?? lastDate.addingTimeInterval(Double(weeks) * 7.0 * 86400.0)
            
        case .months(let months):
            guard months > 0 else { return lastDate }
            return addMonths(to: lastDate, months: months, calendar: calendar)
            
        case .years(let years):
            guard years > 0 else { return lastDate }
            return addYears(to: lastDate, years: years, calendar: calendar)
            
        case .annual:
            return addYears(to: lastDate, years: 1, calendar: calendar)
        }
    }
    
    /// Adds years to a date with strict February 29th leap year clamping.
    ///
    /// If the source date is February 29th and the target year is not a leap year,
    /// the date is clamped to February 28th.
    public static func addYears(to date: Date, years: Int, calendar: Calendar = .current) -> Date {
        guard years != 0 else { return date }
        
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .timeZone],
            from: date
        )
        guard let currentYear = components.year,
              let currentMonth = components.month,
              let currentDay = components.day else {
            return calendar.date(byAdding: .year, value: years, to: date) ?? date
        }
        
        let targetYear = currentYear + years
        let isFeb29 = (currentMonth == 2 && currentDay == 29)
        
        if isFeb29 && !isLeapYear(targetYear) {
            components.year = targetYear
            components.month = 2
            components.day = 28
        } else {
            components.year = targetYear
        }
        
        return calendar.date(from: components)
            ?? calendar.date(byAdding: .year, value: years, to: date)
            ?? date
    }
    
    /// Adds months to a date with end-of-month clamping (e.g., Jan 31 -> Feb 28/29).
    ///
    /// - Parameter dayOfMonth: the day a series keeps (31 for "the 31st"). The result
    ///   is that day, or the target month's last day when it is shorter. Without it,
    ///   the date's own day is used, so a date already clamped (28 February) would
    ///   carry its shorter day forward.
    public static func addMonths(to date: Date, months: Int, dayOfMonth: Int? = nil, calendar: Calendar = .current) -> Date {
        guard months != 0 || dayOfMonth != nil else { return date }
        
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .timeZone],
            from: date
        )
        guard let currentYear = components.year,
              let currentMonth = components.month,
              let currentDay = components.day else {
            return calendar.date(byAdding: .month, value: months, to: date) ?? date
        }
        
        let totalMonths = (currentYear * 12 + (currentMonth - 1)) + months
        let targetYear = totalMonths / 12
        let targetMonth = (totalMonths % 12) + 1
        
        let daysInTargetMonth: Int
        switch targetMonth {
        case 1, 3, 5, 7, 8, 10, 12:
            daysInTargetMonth = 31
        case 4, 6, 9, 11:
            daysInTargetMonth = 30
        case 2:
            daysInTargetMonth = isLeapYear(targetYear) ? 29 : 28
        default:
            daysInTargetMonth = 30
        }
        
        components.year = targetYear
        components.month = targetMonth
        components.day = min(dayOfMonth ?? currentDay, daysInTargetMonth)
        
        return calendar.date(from: components)
            ?? calendar.date(byAdding: .month, value: months, to: date)
            ?? date
    }
    
    // MARK: - Telemetry Cadence Engine
    
    /// Projects the next due date based on telemetry history and consumption rate.
    ///
    /// - Parameters:
    ///   - currentMetric: The current counter reading (e.g. 142,500 km).
    ///   - targetMetric: The threshold when service is due (e.g. 150,000 km).
    ///   - history: Historical telemetry readings `(date, metric)`.
    ///   - baselineDailyRate: Optional category default burn-rate (e.g. 35.0 km/day for vehicles).
    ///   - currentDate: Reference date for projection (defaults to `Date()`).
    ///   - calendar: Calendar instance.
    /// - Returns: A `TelemetryProjection` containing the burn rate and estimated deadline, or `nil` if projection cannot be calculated.
    public static func projectTelemetryDueDate(
        currentMetric: Double,
        targetMetric: Double,
        history: [(date: Date, metric: Double)],
        baselineDailyRate: Double? = nil,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TelemetryProjection? {
        let readings = history.map { TelemetryReading(date: $0.date, metric: $0.metric) }
        return projectTelemetryDueDate(
            currentMetric: currentMetric,
            targetMetric: targetMetric,
            readings: readings,
            baselineDailyRate: baselineDailyRate,
            currentDate: currentDate,
            calendar: calendar
        )
    }
    
    /// Projects the next due date based on structured telemetry readings.
    public static func projectTelemetryDueDate(
        currentMetric: Double,
        targetMetric: Double,
        readings: [TelemetryReading],
        baselineDailyRate: Double? = nil,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TelemetryProjection? {
        let remainingMetric = targetMetric - currentMetric
        
        // Target already exceeded: immediate action required
        if remainingMetric <= 0 {
            let startOfToday = calendar.startOfDay(for: currentDate)
            return TelemetryProjection(
                estimatedDueDate: startOfToday,
                dailyBurnRate: 0.0,
                remainingMetric: remainingMetric,
                daysRemaining: 0,
                isDueImmediately: true,
                isEstimatedFromBaseline: false,
                hasRollbackAnomaly: false
            )
        }
        
        // The one cleaned series: a reading that breaks the order (a typo, one kept aside)
        // is skipped and flagged, never a reason to stop projecting.
        let series = ReadingSeries(readings)
        let sorted = series.readings
        let hasRollback = !series.setAside.isEmpty
        
        var calculatedRate: Double? = nil
        
        // Compute burn rate if we have >= 2 points
        if sorted.count >= 2 {
            let first = sorted.first!
            let last = sorted.last!
            let deltaMetric = last.metric - first.metric
            
            let startOfFirst = calendar.startOfDay(for: first.date)
            let startOfLast = calendar.startOfDay(for: last.date)
            let deltaDays: Double
            if let compDays = calendar.dateComponents([.day], from: startOfFirst, to: startOfLast).day, compDays > 0 {
                let timeDiffFirst = first.date.timeIntervalSince(startOfFirst)
                let timeDiffLast = last.date.timeIntervalSince(startOfLast)
                deltaDays = Double(compDays) + ((timeDiffLast - timeDiffFirst) / 86400.0)
            } else {
                deltaDays = last.date.timeIntervalSince(first.date) / 86400.0
            }
            
            // Guard against zero time delta or zero metric progression
            if deltaDays > 0.001 && deltaMetric > 0 {
                calculatedRate = deltaMetric / deltaDays
            }
        }
        
        // Determine effective daily rate
        let effectiveRate: Double
        let isBaseline: Bool
        
        if let rate = calculatedRate, rate > 0 {
            effectiveRate = rate
            isBaseline = false
        } else if let baseline = baselineDailyRate, baseline > 0 {
            effectiveRate = baseline
            isBaseline = true
        } else {
            // No valid rate could be determined (zero rate, rollback with no baseline, or insufficient history)
            return nil
        }
        
        // Guard against Double-to-Int overflow when effectiveRate is extremely small (e.g. 1e-15)
        // Cap calculation at a realistic maximum projection horizon (100 years = 36,500 days)
        let rawDays = ceil(remainingMetric / effectiveRate)
        let maxProjectionDays: Double = 36500.0
        let daysToTarget: Int
        if rawDays.isNaN || rawDays.isInfinite || rawDays > maxProjectionDays {
            daysToTarget = Int(maxProjectionDays)
        } else {
            daysToTarget = max(1, Int(rawDays))
        }
        let estimatedDate = calendar.date(byAdding: .day, value: daysToTarget, to: currentDate)
            ?? currentDate.addingTimeInterval(Double(daysToTarget) * 86400.0)
        
        return TelemetryProjection(
            estimatedDueDate: estimatedDate,
            dailyBurnRate: effectiveRate,
            remainingMetric: remainingMetric,
            daysRemaining: daysToTarget,
            isDueImmediately: false,
            isEstimatedFromBaseline: isBaseline,
            hasRollbackAnomaly: hasRollback
        )
    }
    
    // MARK: - Urgency & Status Utilities
    
    /// Computes the exact number of days remaining until `dueDate`.
    ///
    /// Negative values indicate the deadline has passed.
    public static func daysRemaining(
        from currentDate: Date = Date(),
        to dueDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        let startOfToday = calendar.startOfDay(for: currentDate)
        let startOfDue = calendar.startOfDay(for: dueDate)
        let components = calendar.dateComponents([.day], from: startOfToday, to: startOfDue)
        return components.day ?? 0
    }
}
