import Foundation
import Testing
@testable import DosarCuSina

/// Comprehensive unit test suite for `CadenceCalculator`.
///
/// Covers:
/// 1. Leap year identification (Gregorian 4, 100, 400 rules).
/// 2. Calendar cadence arithmetic: days, weeks, months, years, annual/biannual heuristics.
/// 3. Leap year rollover: Feb 29 on leap years (2024, 2028) vs clamping to Feb 28 on non-leap years (2025, 2026, 2027).
/// 4. End-of-month clamping across all month boundaries (Jan 31 -> Feb 28/29, Mar 31 -> Apr 30, etc.).
/// 5. Telemetry projection burn-rate estimation: Δmetric / Δdays.
/// 6. Boundary & edge cases: negative rate / odometer rollback protection, zero rate fallback, target metric already exceeded.
/// 7. Event urgency status classification: completed, overdue, urgent, upcoming, planned.
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
    
    /// Verifies leap year identification across standard, century, and 400-year boundary cases.
    @Test func isLeapYear_RuleVerification() throws {
        // Standard leap years (divisible by 4, not 100)
        try assertTrue(CadenceCalculator.isLeapYear(2024), "2024 must be a leap year")
        try assertTrue(CadenceCalculator.isLeapYear(2028), "2028 must be a leap year")
        try assertTrue(CadenceCalculator.isLeapYear(2032), "2032 must be a leap year")
        
        // 400-year century leap years (divisible by 400)
        try assertTrue(CadenceCalculator.isLeapYear(2000), "2000 must be a leap year (divisible by 400)")
        try assertTrue(CadenceCalculator.isLeapYear(2400), "2400 must be a leap year (divisible by 400)")
        
        // Standard common years
        try assertFalse(CadenceCalculator.isLeapYear(2025), "2025 is not a leap year")
        try assertFalse(CadenceCalculator.isLeapYear(2026), "2026 is not a leap year")
        try assertFalse(CadenceCalculator.isLeapYear(2027), "2027 is not a leap year")
        
        // Century common years (divisible by 100, not 400)
        try assertFalse(CadenceCalculator.isLeapYear(1900), "1900 is not a leap year (divisible by 100, not 400)")
        try assertFalse(CadenceCalculator.isLeapYear(2100), "2100 is not a leap year (divisible by 100, not 400)")
    }
    
    /// Verifies leap year rollover from February 29th clamping to February 28th on non-leap years (2025, 2026, 2027).
    @Test func leapYearRollover_Feb29ClampingOnNonLeapYears() throws {
        let calendar = Calendar.gregorianUTC
        let feb29_2024 = makeDate(year: 2024, month: 2, day: 29, calendar: calendar)
        
        // 1 year later (2025) -> Feb 28, 2025
        let date2025 = CadenceCalculator.addYears(to: feb29_2024, years: 1, calendar: calendar)
        let comp2025 = calendar.dateComponents([.year, .month, .day], from: date2025)
        try assertEqual(comp2025.year, 2025, "Year should be 2025")
        try assertEqual(comp2025.month, 2, "Month should be February")
        try assertEqual(comp2025.day, 28, "Feb 29 on leap 2024 must clamp to Feb 28 on non-leap 2025")
        
        // 2 years later (2026) -> Feb 28, 2026
        let date2026 = CadenceCalculator.addYears(to: feb29_2024, years: 2, calendar: calendar)
        let comp2026 = calendar.dateComponents([.year, .month, .day], from: date2026)
        try assertEqual(comp2026.year, 2026, "Year should be 2026")
        try assertEqual(comp2026.month, 2, "Month should be February")
        try assertEqual(comp2026.day, 28, "Feb 29 on leap 2024 must clamp to Feb 28 on non-leap 2026")
        
        // 3 years later (2027) -> Feb 28, 2027
        let date2027 = CadenceCalculator.addYears(to: feb29_2024, years: 3, calendar: calendar)
        let comp2027 = calendar.dateComponents([.year, .month, .day], from: date2027)
        try assertEqual(comp2027.year, 2027, "Year should be 2027")
        try assertEqual(comp2027.month, 2, "Month should be February")
        try assertEqual(comp2027.day, 28, "Feb 29 on leap 2024 must clamp to Feb 28 on non-leap 2027")
        
        // Verify calculateNextDueDate with interval .annual
        let annualNext = CadenceCalculator.calculateNextDueDate(from: feb29_2024, interval: .annual, calendar: calendar)
        let compAnnual = calendar.dateComponents([.year, .month, .day], from: annualNext)
        try assertEqual(compAnnual.year, 2025, "Annual interval should roll to 2025")
        try assertEqual(compAnnual.month, 2, "Month should remain February")
        try assertEqual(compAnnual.day, 28, "Annual recurrence from Feb 29 2024 must be Feb 28 2025")
    }
    
    /// Verifies leap year rollover preserves February 29th when advancing to another leap year (2028).
    @Test func leapYearRollover_Feb29PreservedOnLeapYears() throws {
        let calendar = Calendar.gregorianUTC
        let feb29_2024 = makeDate(year: 2024, month: 2, day: 29, calendar: calendar)
        
        // 4 years later (2028 - next leap year) -> Feb 29, 2028
        let date2028 = CadenceCalculator.addYears(to: feb29_2024, years: 4, calendar: calendar)
        let comp2028 = calendar.dateComponents([.year, .month, .day], from: date2028)
        try assertEqual(comp2028.year, 2028, "Year should be 2028")
        try assertEqual(comp2028.month, 2, "Month should be February")
        try assertEqual(comp2028.day, 29, "Feb 29 on leap 2024 must remain Feb 29 on leap 2028")
        
        // 8 years later (2032 - leap year) -> Feb 29, 2032
        let date2032 = CadenceCalculator.addYears(to: feb29_2024, years: 8, calendar: calendar)
        let comp2032 = calendar.dateComponents([.year, .month, .day], from: date2032)
        try assertEqual(comp2032.year, 2032, "Year should be 2032")
        try assertEqual(comp2032.month, 2, "Month should be February")
        try assertEqual(comp2032.day, 29, "Feb 29 on leap 2024 must remain Feb 29 on leap 2032")
    }
    
    /// Verifies annual recurrence heuristic via cadenceDays (365 and 366 days).
    @Test func annualRecurrenceViaCadenceDays_365And366() throws {
        let calendar = Calendar.gregorianUTC
        let feb29_2024 = makeDate(year: 2024, month: 2, day: 29, calendar: calendar)
        
        // 365 days cadence from Feb 29 2024 -> should trigger annual heuristic and clamp to Feb 28 2025
        let next365 = CadenceCalculator.calculateNextDueDate(from: feb29_2024, cadenceDays: 365, calendar: calendar)
        let comp365 = calendar.dateComponents([.year, .month, .day], from: next365)
        try assertEqual(comp365.year, 2025, "Annual 365-day recurrence should land in 2025")
        try assertEqual(comp365.month, 2, "Month should be February")
        try assertEqual(comp365.day, 28, "Annual 365-day recurrence from Feb 29 2024 must clamp to Feb 28 2025")
        
        // 366 days cadence from Feb 29 2024 -> also triggers annual heuristic and clamps to Feb 28 2025
        let next366 = CadenceCalculator.calculateNextDueDate(from: feb29_2024, cadenceDays: 366, calendar: calendar)
        let comp366 = calendar.dateComponents([.year, .month, .day], from: next366)
        try assertEqual(comp366.year, 2025, "Annual 366-day recurrence should land in 2025")
        try assertEqual(comp366.month, 2, "Month should be February")
        try assertEqual(comp366.day, 28, "Annual 366-day recurrence from Feb 29 2024 must clamp to Feb 28 2025")
        
        // Standard non-leap date
        let regularDate = makeDate(year: 2026, month: 7, day: 15, calendar: calendar)
        let regularNext = CadenceCalculator.calculateNextDueDate(from: regularDate, cadenceDays: 365, calendar: calendar)
        let compRegular = calendar.dateComponents([.year, .month, .day], from: regularNext)
        try assertEqual(compRegular.year, 2027, "Year should be 2027")
        try assertEqual(compRegular.month, 7, "Month should be July")
        try assertEqual(compRegular.day, 15, "Day should be 15")
    }
    
    /// Verifies biannual recurrence heuristic via cadenceDays (730 and 731 days, e.g. ITP vehicle inspection).
    @Test func biannualRecurrenceViaCadenceDays_730And731() throws {
        let calendar = Calendar.gregorianUTC
        let feb29_2024 = makeDate(year: 2024, month: 2, day: 29, calendar: calendar)
        
        // 730 days from Feb 29 2024 -> lands in 2026 (non-leap year), clamps to Feb 28 2026
        let next730 = CadenceCalculator.calculateNextDueDate(from: feb29_2024, cadenceDays: 730, calendar: calendar)
        let comp730 = calendar.dateComponents([.year, .month, .day], from: next730)
        try assertEqual(comp730.year, 2026, "Biannual 730-day recurrence should land in 2026")
        try assertEqual(comp730.month, 2, "Month should be February")
        try assertEqual(comp730.day, 28, "Biannual recurrence from Feb 29 2024 must clamp to Feb 28 2026")
        
        // 731 days from Feb 29 2024
        let next731 = CadenceCalculator.calculateNextDueDate(from: feb29_2024, cadenceDays: 731, calendar: calendar)
        let comp731 = calendar.dateComponents([.year, .month, .day], from: next731)
        try assertEqual(comp731.year, 2026, "Biannual 731-day recurrence should land in 2026")
        try assertEqual(comp731.month, 2, "Month should be February")
        try assertEqual(comp731.day, 28, "Biannual recurrence from Feb 29 2024 must clamp to Feb 28 2026")
    }
    
    /// Verifies explicit interval calendar arithmetic (.days, .weeks, .months, .years).
    @Test func calendarCadenceInterval_DaysWeeksMonthsYears() throws {
        let calendar = Calendar.gregorianUTC
        let baseDate = makeDate(year: 2026, month: 5, day: 1, calendar: calendar)
        
        // Days
        let plus30Days = CadenceCalculator.calculateNextDueDate(from: baseDate, interval: .days(30), calendar: calendar)
        let compDays = calendar.dateComponents([.year, .month, .day], from: plus30Days)
        try assertEqual(compDays.year, 2026, "Year should be 2026")
        try assertEqual(compDays.month, 5, "Month should be May")
        try assertEqual(compDays.day, 31, "May 1 + 30 days must be May 31")
        
        // Weeks
        let plus2Weeks = CadenceCalculator.calculateNextDueDate(from: baseDate, interval: .weeks(2), calendar: calendar)
        let compWeeks = calendar.dateComponents([.year, .month, .day], from: plus2Weeks)
        try assertEqual(compWeeks.year, 2026, "Year should be 2026")
        try assertEqual(compWeeks.month, 5, "Month should be May")
        try assertEqual(compWeeks.day, 15, "May 1 + 2 weeks must be May 15")
        
        // Months
        let plus3Months = CadenceCalculator.calculateNextDueDate(from: baseDate, interval: .months(3), calendar: calendar)
        let compMonths = calendar.dateComponents([.year, .month, .day], from: plus3Months)
        try assertEqual(compMonths.year, 2026, "Year should be 2026")
        try assertEqual(compMonths.month, 8, "Month should be August")
        try assertEqual(compMonths.day, 1, "May 1 + 3 months must be August 1")
        
        // Years
        let plus2Years = CadenceCalculator.calculateNextDueDate(from: baseDate, interval: .years(2), calendar: calendar)
        let compYears = calendar.dateComponents([.year, .month, .day], from: plus2Years)
        try assertEqual(compYears.year, 2028, "Year should be 2028")
        try assertEqual(compYears.month, 5, "Month should be May")
        try assertEqual(compYears.day, 1, "May 1, 2026 + 2 years must be May 1, 2028")
    }
    
    /// Verifies end-of-month clamping across various month boundaries (Jan 31 -> Feb 28, Mar 31 -> Apr 30, etc.).
    @Test func addMonths_EndOfMonthClamping() throws {
        let calendar = Calendar.gregorianUTC
        
        // Jan 31, 2026 (non-leap) + 1 month -> Feb 28, 2026
        let jan31_2026 = makeDate(year: 2026, month: 1, day: 31, calendar: calendar)
        let feb2026 = CadenceCalculator.addMonths(to: jan31_2026, months: 1, calendar: calendar)
        let compFeb2026 = calendar.dateComponents([.year, .month, .day], from: feb2026)
        try assertEqual(compFeb2026.year, 2026, "Year should be 2026")
        try assertEqual(compFeb2026.month, 2, "Month should be February")
        try assertEqual(compFeb2026.day, 28, "Jan 31 + 1 month in common year 2026 must clamp to Feb 28")
        
        // Jan 31, 2024 (leap) + 1 month -> Feb 29, 2024
        let jan31_2024 = makeDate(year: 2024, month: 1, day: 31, calendar: calendar)
        let feb2024 = CadenceCalculator.addMonths(to: jan31_2024, months: 1, calendar: calendar)
        let compFeb2024 = calendar.dateComponents([.year, .month, .day], from: feb2024)
        try assertEqual(compFeb2024.year, 2024, "Year should be 2024")
        try assertEqual(compFeb2024.month, 2, "Month should be February")
        try assertEqual(compFeb2024.day, 29, "Jan 31 + 1 month in leap year 2024 must clamp to Feb 29")
        
        // Mar 31, 2026 + 1 month -> Apr 30, 2026
        let mar31_2026 = makeDate(year: 2026, month: 3, day: 31, calendar: calendar)
        let apr2026 = CadenceCalculator.addMonths(to: mar31_2026, months: 1, calendar: calendar)
        let compApr2026 = calendar.dateComponents([.year, .month, .day], from: apr2026)
        try assertEqual(compApr2026.year, 2026, "Year should be 2026")
        try assertEqual(compApr2026.month, 4, "Month should be April")
        try assertEqual(compApr2026.day, 30, "Mar 31 + 1 month must clamp to Apr 30")
        
        // May 31, 2026 + 1 month -> Jun 30, 2026
        let may31_2026 = makeDate(year: 2026, month: 5, day: 31, calendar: calendar)
        let jun2026 = CadenceCalculator.addMonths(to: may31_2026, months: 1, calendar: calendar)
        let compJun2026 = calendar.dateComponents([.year, .month, .day], from: jun2026)
        try assertEqual(compJun2026.year, 2026, "Year should be 2026")
        try assertEqual(compJun2026.month, 6, "Month should be June")
        try assertEqual(compJun2026.day, 30, "May 31 + 1 month must clamp to Jun 30")
        
        // Aug 31, 2026 + 1 month -> Sep 30, 2026
        let aug31_2026 = makeDate(year: 2026, month: 8, day: 31, calendar: calendar)
        let sep2026 = CadenceCalculator.addMonths(to: aug31_2026, months: 1, calendar: calendar)
        let compSep2026 = calendar.dateComponents([.year, .month, .day], from: sep2026)
        try assertEqual(compSep2026.year, 2026, "Year should be 2026")
        try assertEqual(compSep2026.month, 9, "Month should be September")
        try assertEqual(compSep2026.day, 30, "Aug 31 + 1 month must clamp to Sep 30")
        
        // Oct 31, 2026 + 1 month -> Nov 30, 2026
        let oct31_2026 = makeDate(year: 2026, month: 10, day: 31, calendar: calendar)
        let nov2026 = CadenceCalculator.addMonths(to: oct31_2026, months: 1, calendar: calendar)
        let compNov2026 = calendar.dateComponents([.year, .month, .day], from: nov2026)
        try assertEqual(compNov2026.year, 2026, "Year should be 2026")
        try assertEqual(compNov2026.month, 11, "Month should be November")
        try assertEqual(compNov2026.day, 30, "Oct 31 + 1 month must clamp to Nov 30")
    }
    
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
    
    /// Verifies event urgency status classification across all thresholds.
    @Test func urgencyStatus_AllCategories() throws {
        let calendar = Calendar.gregorianUTC
        let today = makeDate(year: 2026, month: 5, day: 15, calendar: calendar)
        
        // 1. Completed
        let statusCompleted = CadenceCalculator.calculateUrgencyStatus(
            dueDate: makeDate(year: 2026, month: 5, day: 1, calendar: calendar),
            isCompleted: true,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusCompleted, .completed, "Completed event must return .completed")
        
        // 2. Overdue: 5 days ago
        let statusOverdue = CadenceCalculator.calculateUrgencyStatus(
            dueDate: makeDate(year: 2026, month: 5, day: 10, calendar: calendar),
            isCompleted: false,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusOverdue, .overdue(days: 5), "Past due date must return .overdue(days: 5)")
        
        // 3. Urgent: today (0 days)
        let statusToday = CadenceCalculator.calculateUrgencyStatus(
            dueDate: today,
            isCompleted: false,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusToday, .urgent(days: 0), "Due today must return .urgent(days: 0)")
        
        // 4. Urgent: 3 days remaining
        let statusUrgent = CadenceCalculator.calculateUrgencyStatus(
            dueDate: makeDate(year: 2026, month: 5, day: 18, calendar: calendar),
            isCompleted: false,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusUrgent, .urgent(days: 3), "Due in 3 days must return .urgent(days: 3)")
        
        // 5. Urgent: 7 days remaining (boundary)
        let statusUrgent7 = CadenceCalculator.calculateUrgencyStatus(
            dueDate: makeDate(year: 2026, month: 5, day: 22, calendar: calendar),
            isCompleted: false,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusUrgent7, .urgent(days: 7), "Due in 7 days must return .urgent(days: 7)")
        
        // 6. Upcoming: 14 days remaining
        let statusUpcoming = CadenceCalculator.calculateUrgencyStatus(
            dueDate: makeDate(year: 2026, month: 5, day: 29, calendar: calendar),
            isCompleted: false,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusUpcoming, .upcoming(days: 14), "Due in 14 days must return .upcoming(days: 14)")
        
        // 7. Upcoming: 30 days remaining (boundary)
        let statusUpcoming30 = CadenceCalculator.calculateUrgencyStatus(
            dueDate: makeDate(year: 2026, month: 6, day: 14, calendar: calendar),
            isCompleted: false,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusUpcoming30, .upcoming(days: 30), "Due in 30 days must return .upcoming(days: 30)")
        
        // 8. Planned: 45 days remaining
        let statusPlanned = CadenceCalculator.calculateUrgencyStatus(
            dueDate: makeDate(year: 2026, month: 6, day: 29, calendar: calendar),
            isCompleted: false,
            currentDate: today,
            calendar: calendar
        )
        try assertEqual(statusPlanned, .planned(days: 45), "Due in 45 days must return .planned(days: 45)")
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
