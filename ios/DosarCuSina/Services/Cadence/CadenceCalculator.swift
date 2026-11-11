import Foundation

/// Telemetry projections for counter-based cadences (odometer km/day, hours/day,
/// cycles/day, with rollback guards).
///
/// Calendar arithmetic (days, months, years, month ends, 29 February) is `CalendarDay`'s,
/// the one place it lives; `RecurrenceEngine.add` moves a deadline by its interval.
public final class CadenceCalculator: Sendable {
    
    // MARK: - Types
    
    /// A single timestamped telemetry observation.
    public struct TelemetryReading: Sendable, Equatable {
        public let date: Date
        public let metric: Double
        /// The first reading of a new counter (`MeasurementLog.startsCounter`): the readings
        /// from it on count on their own (`ReadingSeries.counters`).
        public let startsCounter: Bool
        /// An estimate of the counter (`MeasurementLog.isEstimate`): it counts only until a
        /// later reading of its counter is lower (`ReadingSeries`).
        public let isEstimate: Bool

        public init(date: Date, metric: Double, startsCounter: Bool = false, isEstimate: Bool = false) {
            self.date = date
            self.metric = metric
            self.startsCounter = startsCounter
            self.isEstimate = isEstimate
        }

        /// The same reading, at the same moment and value, whether or not it starts a counter.
        public func isSameReading(as other: TelemetryReading) -> Bool {
            date == other.date && metric == other.metric
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
        calendar: Calendar = .dosar
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
        calendar: Calendar = .dosar
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
        // is skipped and flagged, never a reason to stop projecting. Each counter counts on
        // its own, so a new meter or dashboard is never a jump (`ReadingSeries.progress`).
        let series = ReadingSeries(readings)
        let hasRollback = !series.setAside.isEmpty
        
        var calculatedRate: Double? = nil
        
        // Compute burn rate if a counter has >= 2 points
        if let progress = series.progress(days: { first, last in
            let startOfFirst = calendar.startOfDay(for: first)
            let startOfLast = calendar.startOfDay(for: last)
            if let compDays = calendar.dateComponents([.day], from: startOfFirst, to: startOfLast).day, compDays > 0 {
                let timeDiffFirst = first.timeIntervalSince(startOfFirst)
                let timeDiffLast = last.timeIntervalSince(startOfLast)
                return Double(compDays) + ((timeDiffLast - timeDiffFirst) / 86400.0)
            }
            return last.timeIntervalSince(first) / 86400.0
        }) {
            // Guard against zero time delta or zero metric progression
            if progress.days > 0.001 && progress.distance > 0 {
                calculatedRate = progress.distance / progress.days
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
}
