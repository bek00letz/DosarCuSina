import Foundation
import Testing
@testable import DosarCuSina

/// Comprehensive unit test suite for `CadenceCalculator`.
///
/// Calendar arithmetic (leap years, month ends, days, weeks, months and years) is
/// `CalendarDay`'s and is pinned in `MonthArithmeticTests`.
///
/// Covers:
/// 1. Telemetry projection burn-rate estimation: Δmetric / Δdays.
/// 2. Boundary & edge cases: negative rate / odometer rollback protection, zero rate fallback, target metric already exceeded.
/// 3. Event urgency status classification: completed, overdue, urgent, upcoming, planned.
@Suite struct CadenceCalculatorTests {
    
    // MARK: - Date Helpers
    
    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, calendar: Calendar = .gregorianUTC) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components)!
    }
    
    // MARK: - Test Cases
    
    /// Verifies telemetry projection burn rate estimation: Δmetric / Δdays.
    /// Scenario: 10,000 km on Day 0, 12,000 km on Day 40. Target: 15,000 km.
    /// Expected rate = (12,000 - 10,000) / 40 = 50 km/day.
    /// Remaining metric = 15,000 - 12,000 = 3,000 km.
    /// Expected days = 3,000 / 50 = 60 days.
    @Test func telemetryProjection_NormalRateEstimation() throws {
        let calendar = Calendar.gregorianUTC
        let day0 = makeDate(year: 2026, month: 1, day: 1, calendar: calendar)
        let day40 = makeDate(year: 2026, month: 2, day: 10, calendar: calendar)
        
        let history = [
            (date: day0, metric: 10_000.0),
            (date: day40, metric: 12_000.0)
        ]
        
        guard let projection = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 12_000.0,
            targetMetric: 15_000.0,
            history: history,
            currentDate: day40,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Projection should not be nil", file: #file, line: #line)
        }
        
        try assertAlmostEqual(projection.dailyBurnRate, 50.0, accuracy: 0.1, "Daily burn rate should be 50.0 km/day")
        try assertAlmostEqual(projection.remainingMetric, 3_000.0, accuracy: 0.1, "Remaining metric should be 3000 km")
        try assertEqual(projection.daysRemaining, 60, "Estimated days remaining should be 60 days")
        try assertFalse(projection.isDueImmediately, "Should not be due immediately")
        try assertFalse(projection.isEstimatedFromBaseline, "Should be computed from real data, not baseline")
        try assertFalse(projection.hasRollbackAnomaly, "Should not have rollback anomaly")
        
        let expectedDueDate = calendar.date(byAdding: .day, value: 60, to: day40)!
        let compEstimated = calendar.dateComponents([.year, .month, .day], from: projection.estimatedDueDate)
        let compExpected = calendar.dateComponents([.year, .month, .day], from: expectedDueDate)
        try assertEqual(compEstimated.year, compExpected.year, "Due year match")
        try assertEqual(compEstimated.month, compExpected.month, "Due month match")
        try assertEqual(compEstimated.day, compExpected.day, "Due day match")
    }
    
    /// Verifies telemetry projection with multiple history points.
    @Test func telemetryProjection_MultipleReadings() throws {
        let calendar = Calendar.gregorianUTC
        let d1 = makeDate(year: 2026, month: 1, day: 1, calendar: calendar)
        let d2 = makeDate(year: 2026, month: 1, day: 15, calendar: calendar)
        let d3 = makeDate(year: 2026, month: 1, day: 31, calendar: calendar)
        
        let history = [
            (date: d1, metric: 50_000.0),
            (date: d2, metric: 50_750.0), // +750 over 14 days
            (date: d3, metric: 51_500.0)  // +1500 over 30 days -> 50 km/day
        ]
        
        guard let projection = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 51_500.0,
            targetMetric: 53_000.0,
            history: history,
            currentDate: d3,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Projection should not be nil", file: #file, line: #line)
        }
        
        try assertAlmostEqual(projection.dailyBurnRate, 50.0, accuracy: 0.2, "Burn rate should be ~50 km/day")
        try assertAlmostEqual(projection.remainingMetric, 1_500.0, accuracy: 0.1, "Remaining metric should be 1500 km")
        try assertEqual(projection.daysRemaining, 30, "Days remaining should be 30")
        try assertFalse(projection.isDueImmediately, "Should not be due immediately")
    }
    
    /// Verifies target already exceeded condition (e.g. current 15,200 km, target 15,000 km).
    @Test func telemetryProjection_TargetAlreadyExceeded() throws {
        let calendar = Calendar.gregorianUTC
        let today = makeDate(year: 2026, month: 6, day: 1, calendar: calendar)
        
        let history = [
            (date: makeDate(year: 2026, month: 5, day: 1, calendar: calendar), metric: 14_000.0),
            (date: today, metric: 15_200.0)
        ]
        
        guard let projection = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 15_200.0,
            targetMetric: 15_000.0,
            history: history,
            currentDate: today,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Projection should not be nil", file: #file, line: #line)
        }
        
        try assertTrue(projection.isDueImmediately, "Must be flagged as due immediately")
        try assertEqual(projection.daysRemaining, 0, "Days remaining must be 0")
        try assertAlmostEqual(projection.remainingMetric, -200.0, accuracy: 0.1, "Remaining metric should be -200.0 km")
        try assertAlmostEqual(projection.dailyBurnRate, 0.0, accuracy: 0.01, "Burn rate should be 0.0")
        try assertFalse(projection.hasRollbackAnomaly, "Target exceeded is not a rollback anomaly")
    }
    
    /// Verifies odometer rollback / negative progression anomaly protection.
    /// Scenario: Day 0 = 50,000 km, Day 20 = 45,000 km (regression).
    @Test func telemetryProjection_NegativeRateOdometerRollbackProtection() throws {
        let calendar = Calendar.gregorianUTC
        let day0 = makeDate(year: 2026, month: 1, day: 1, calendar: calendar)
        let day20 = makeDate(year: 2026, month: 1, day: 21, calendar: calendar)
        
        let history = [
            (date: day0, metric: 50_000.0),
            (date: day20, metric: 45_000.0) // Anomaly: reading regressed!
        ]
        
        // Case A: Without baseline rate fallback, engine returns nil safely to avoid corrupted negative dates
        let noBaselineProj = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 45_000.0,
            targetMetric: 60_000.0,
            history: history,
            baselineDailyRate: nil,
            currentDate: day20,
            calendar: calendar
        )
        try assertNil(noBaselineProj, "Without baseline rate, rollback anomaly should return nil to protect against bogus dates")
        
        // Case B: With baseline rate fallback (e.g. 35.0 km/day vehicle default), returns projection flagged with rollback anomaly
        guard let baselineProj = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 45_000.0,
            targetMetric: 60_000.0,
            history: history,
            baselineDailyRate: 35.0,
            currentDate: day20,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Projection with baseline rate should succeed", file: #file, line: #line)
        }
        
        try assertTrue(baselineProj.hasRollbackAnomaly, "Must flag hasRollbackAnomaly == true")
        try assertTrue(baselineProj.isEstimatedFromBaseline, "Must flag isEstimatedFromBaseline == true")
        try assertAlmostEqual(baselineProj.dailyBurnRate, 35.0, accuracy: 0.1, "Daily rate must be 35.0 km/day baseline")
        try assertEqual(baselineProj.daysRemaining, Int(ceil(15_000.0 / 35.0)), "Days remaining must use baseline burn rate")
    }
    
    /// Verifies zero rate / zero metric progression fallback.
    /// Scenario: Car parked for a month (Day 0 = 10,000 km, Day 30 = 10,000 km).
    @Test func telemetryProjection_ZeroRateFallback() throws {
        let calendar = Calendar.gregorianUTC
        let day0 = makeDate(year: 2026, month: 1, day: 1, calendar: calendar)
        let day30 = makeDate(year: 2026, month: 1, day: 31, calendar: calendar)
        
        let history = [
            (date: day0, metric: 10_000.0),
            (date: day30, metric: 10_000.0) // Zero progression
        ]
        
        // Case A: Without baseline rate, returns nil to guard against division by zero
        let noBaselineProj = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 10_000.0,
            targetMetric: 15_000.0,
            history: history,
            baselineDailyRate: nil,
            currentDate: day30,
            calendar: calendar
        )
        try assertNil(noBaselineProj, "Zero progression without baseline must return nil to guard against division by zero")
        
        // Case B: With baseline rate (e.g. 25.0 km/day), falls back to baseline safely
        guard let baselineProj = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 10_000.0,
            targetMetric: 15_000.0,
            history: history,
            baselineDailyRate: 25.0,
            currentDate: day30,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Projection with baseline should succeed", file: #file, line: #line)
        }
        
        try assertTrue(baselineProj.isEstimatedFromBaseline, "Must be flagged as estimated from baseline")
        try assertAlmostEqual(baselineProj.dailyBurnRate, 25.0, accuracy: 0.1, "Daily burn rate should equal baseline")
        try assertEqual(baselineProj.daysRemaining, 200, "5,000 / 25 = 200 days")
    }
    
    /// Verifies single reading telemetry fallback to baseline daily rate.
    @Test func telemetryProjection_SingleReadingFallback() throws {
        let calendar = Calendar.gregorianUTC
        let day0 = makeDate(year: 2026, month: 3, day: 1, calendar: calendar)
        
        let history = [
            (date: day0, metric: 20_000.0)
        ]
        
        // Without baseline -> nil
        let noBaseline = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 20_000.0,
            targetMetric: 30_000.0,
            history: history,
            baselineDailyRate: nil,
            currentDate: day0,
            calendar: calendar
        )
        try assertNil(noBaseline, "Single reading without baseline must return nil")
        
        // With baseline 40.0 km/day -> 250 days
        guard let withBaseline = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 20_000.0,
            targetMetric: 30_000.0,
            history: history,
            baselineDailyRate: 40.0,
            currentDate: day0,
            calendar: calendar
        ) else {
            throw TestAssertionError(message: "Should return projection with baseline", file: #file, line: #line)
        }
        
        try assertTrue(withBaseline.isEstimatedFromBaseline, "Should be estimated from baseline")
        try assertAlmostEqual(withBaseline.dailyBurnRate, 40.0, accuracy: 0.1, "Daily burn rate should match baseline")
        try assertEqual(withBaseline.daysRemaining, 250, "10,000 / 40 = 250 days")
    }
    
    /// Verifies protection against fatal Double-to-Int conversion trap when burn rate is microscopic.
    @Test func telemetryProjection_TinyRateDoubleToIntOverflowProtection() throws {
        let calendar = Calendar.gregorianUTC
        let day0 = makeDate(year: 2026, month: 1, day: 1, calendar: calendar)
        let day10 = makeDate(year: 2026, month: 1, day: 11, calendar: calendar)
        
        let history = [
            (date: day0, metric: 10_000.0),
            (date: day10, metric: 10_000.0000000001) // Microscopic progression
        ]
        
        // Without clamping, remainingMetric / rate would exceed Double(Int.max) and fatalError
        let proj = CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 10_000.0000000001,
            targetMetric: 50_000.0,
            history: history,
            currentDate: day10,
            calendar: calendar
        )
        
        guard let p = proj else {
            throw TestAssertionError(message: "Tiny burn rate projection should return clamped projection instead of trapping", file: #file, line: #line)
        }
        try assertTrue(p.daysRemaining > 0, "Days remaining must be positive")
        try assertTrue(p.daysRemaining <= 36500, "Days remaining must be capped at 36,500 days horizon")
    }
    
    // MARK: - Runner
    
}

// MARK: - Calendar Extension for UTC Tests

private extension Calendar {
    static var gregorianUTC: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }
}
