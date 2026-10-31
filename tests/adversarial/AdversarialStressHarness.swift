import Foundation

// MARK: - Minimal Terminal Test Reporter

var totalTests = 0
var passedTests = 0
var failedTests = 0

func assertTest(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    totalTests += 1
    if condition {
        passedTests += 1
        print("  \u{001B}[32m✔ PASS\u{001B}[0m [\(totalTests)] \(name)")
    } else {
        failedTests += 1
        print("  \u{001B}[31m✘ FAIL\u{001B}[0m [\(totalTests)] \(name) (line \(line))")
    }
}

func dateFrom(year: Int, month: Int, day: Int, hour: Int = 12, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
    var c = DateComponents()
    c.year = year
    c.month = month
    c.day = day
    c.hour = hour
    c.minute = 0
    c.second = 0
    c.timeZone = TimeZone(secondsFromGMT: 0)
    return calendar.date(from: c)!
}

func componentsOf(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> (year: Int, month: Int, day: Int) {
    var cal = calendar
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let comps = cal.dateComponents([.year, .month, .day], from: date)
    return (comps.year!, comps.month!, comps.day!)
}

// MARK: - SUITE 1: LEAP YEAR & CALENDAR RECURRENCE ADVERSARIAL STRESS

func runLeapYearStressTests() {
    print("\n\u{001B}[1m=== SUITE 1: LEAP YEAR & CALENDAR RECURRENCE ADVERSARIAL STRESS ===\u{001B}[0m")
    
    // 1.1 Gregorian 400-year, 100-year, 4-year rule checks
    let leapYears = [1600, 2000, 2024, 2028, 2400, 2004, 2008, 2012, 2016, 2020, 2032]
    for y in leapYears {
        assertTest(CadenceCalculator.isLeapYear(y), "Year \(y) must be identified as leap year")
    }
    
    let nonLeapYears = [1700, 1800, 1900, 2100, 2200, 2300, 2025, 2026, 2027, 2029, 2030, 2031]
    for y in nonLeapYears {
        assertTest(!CadenceCalculator.isLeapYear(y), "Year \(y) must be identified as non-leap year")
    }
    
    // 1.2 Feb 29 advancing 1, 2, 3, 4, 5, 8, 100, 400 years
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    
    let feb29_2024 = dateFrom(year: 2024, month: 2, day: 29, calendar: cal)
    
    // +1 year -> Feb 28, 2025
    let plus1 = CadenceCalculator.addYears(to: feb29_2024, years: 1, calendar: cal)
    let c1 = componentsOf(plus1, calendar: cal)
    assertTest(c1.year == 2025 && c1.month == 2 && c1.day == 28, "Feb 29, 2024 + 1 year = Feb 28, 2025 (got \(c1))")
    
    // +2 years -> Feb 28, 2026
    let plus2 = CadenceCalculator.addYears(to: feb29_2024, years: 2, calendar: cal)
    let c2 = componentsOf(plus2, calendar: cal)
    assertTest(c2.year == 2026 && c2.month == 2 && c2.day == 28, "Feb 29, 2024 + 2 years = Feb 28, 2026 (got \(c2))")
    
    // +3 years -> Feb 28, 2027
    let plus3 = CadenceCalculator.addYears(to: feb29_2024, years: 3, calendar: cal)
    let c3 = componentsOf(plus3, calendar: cal)
    assertTest(c3.year == 2027 && c3.month == 2 && c3.day == 28, "Feb 29, 2024 + 3 years = Feb 28, 2027 (got \(c3))")
    
    // +4 years -> Feb 29, 2028
    let plus4 = CadenceCalculator.addYears(to: feb29_2024, years: 4, calendar: cal)
    let c4 = componentsOf(plus4, calendar: cal)
    assertTest(c4.year == 2028 && c4.month == 2 && c4.day == 29, "Feb 29, 2024 + 4 years = Feb 29, 2028 (got \(c4))")
    
    // +5 years -> Feb 28, 2029
    let plus5 = CadenceCalculator.addYears(to: feb29_2024, years: 5, calendar: cal)
    let c5 = componentsOf(plus5, calendar: cal)
    assertTest(c5.year == 2029 && c5.month == 2 && c5.day == 28, "Feb 29, 2024 + 5 years = Feb 28, 2029 (got \(c5))")
    
    // +76 years -> 2100 (non-leap century!)
    let plus76 = CadenceCalculator.addYears(to: feb29_2024, years: 76, calendar: cal)
    let c76 = componentsOf(plus76, calendar: cal)
    assertTest(c76.year == 2100 && c76.month == 2 && c76.day == 28, "Feb 29, 2024 + 76 years = Feb 28, 2100 century clamp (got \(c76))")
    
    // +376 years -> 2400 (400-year leap century!)
    let plus376 = CadenceCalculator.addYears(to: feb29_2024, years: 376, calendar: cal)
    let c376 = componentsOf(plus376, calendar: cal)
    assertTest(c376.year == 2400 && c376.month == 2 && c376.day == 29, "Feb 29, 2024 + 376 years = Feb 29, 2400 400-year leap preservation (got \(c376))")
    
    // 1.3 Annual cadence heuristic (365 & 366 days)
    let nextAnnual365 = CadenceCalculator.calculateNextDueDate(from: feb29_2024, cadenceDays: 365, calendar: cal)
    let cAnnual365 = componentsOf(nextAnnual365, calendar: cal)
    assertTest(cAnnual365.year == 2025 && cAnnual365.month == 2 && cAnnual365.day == 28, "365-day recurrence from Feb 29, 2024 preserves Feb 28 anniversary in 2025 (got \(cAnnual365))")
    
    let nextAnnual366 = CadenceCalculator.calculateNextDueDate(from: feb29_2024, cadenceDays: 366, calendar: cal)
    let cAnnual366 = componentsOf(nextAnnual366, calendar: cal)
    assertTest(cAnnual366.year == 2025 && cAnnual366.month == 2 && cAnnual366.day == 28, "366-day recurrence from Feb 29, 2024 preserves Feb 28 anniversary in 2025 (got \(cAnnual366))")
    
    // Biannual 730/731 days (e.g. vehicle ITP)
    let nextBiannual = CadenceCalculator.calculateNextDueDate(from: feb29_2024, cadenceDays: 730, calendar: cal)
    let cBiannual = componentsOf(nextBiannual, calendar: cal)
    assertTest(cBiannual.year == 2026 && cBiannual.month == 2 && cBiannual.day == 28, "730-day recurrence from Feb 29, 2024 advances to Feb 28, 2026 (got \(cBiannual))")
    
    // 1.4 Month rollover clamping across all 12 calendar months:
    // Testing end-of-month dates advancing by 1 month:
    let monthClampTests: [(fromYear: Int, fromMonth: Int, fromDay: Int, expYear: Int, expMonth: Int, expDay: Int)] = [
        (2024, 1, 31, 2024, 2, 29), // Jan 31 -> Feb 29 (leap 2024)
        (2025, 1, 31, 2025, 2, 28), // Jan 31 -> Feb 28 (non-leap 2025)
        (2024, 1, 30, 2024, 2, 29), // Jan 30 -> Feb 29 (leap 2024)
        (2025, 1, 30, 2025, 2, 28), // Jan 30 -> Feb 28 (non-leap 2025)
        (2024, 2, 29, 2024, 3, 29), // Feb 29 -> Mar 29
        (2025, 2, 28, 2025, 3, 28), // Feb 28 -> Mar 28
        (2024, 3, 31, 2024, 4, 30), // Mar 31 -> Apr 30
        (2024, 4, 30, 2024, 5, 30), // Apr 30 -> May 30
        (2024, 5, 31, 2024, 6, 30), // May 31 -> Jun 30
        (2024, 6, 30, 2024, 7, 30), // Jun 30 -> Jul 30
        (2024, 7, 31, 2024, 8, 31), // Jul 31 -> Aug 31
        (2024, 8, 31, 2024, 9, 30), // Aug 31 -> Sep 30
        (2024, 9, 30, 2024, 10, 30), // Sep 30 -> Oct 30
        (2024, 10, 31, 2024, 11, 30), // Oct 31 -> Nov 30
        (2024, 11, 30, 2024, 12, 30), // Nov 30 -> Dec 30
        (2024, 12, 31, 2025, 1, 31), // Dec 31 -> Jan 31 (next year)
    ]
    
    for t in monthClampTests {
        let fromDate = dateFrom(year: t.fromYear, month: t.fromMonth, day: t.fromDay, calendar: cal)
        let nextDate = CadenceCalculator.addMonths(to: fromDate, months: 1, calendar: cal)
        let c = componentsOf(nextDate, calendar: cal)
        assertTest(
            c.year == t.expYear && c.month == t.expMonth && c.day == t.expDay,
            "addMonths(1) from \(t.fromYear)-\(t.fromMonth)-\(t.fromDay) = \(t.expYear)-\(t.expMonth)-\(t.expDay) (got \(c))"
        )
    }
    
    // Multi-month additions across year boundaries:
    // Aug 31, 2024 + 6 months -> Feb 28, 2025 (non-leap)
    let aug31_2024 = dateFrom(year: 2024, month: 8, day: 31, calendar: cal)
    let plus6m = CadenceCalculator.addMonths(to: aug31_2024, months: 6, calendar: cal)
    let c6m = componentsOf(plus6m, calendar: cal)
    assertTest(c6m.year == 2025 && c6m.month == 2 && c6m.day == 28, "Aug 31, 2024 + 6 months = Feb 28, 2025 (got \(c6m))")
    
    // Aug 31, 2023 + 6 months -> Feb 29, 2024 (leap)
    let aug31_2023 = dateFrom(year: 2023, month: 8, day: 31, calendar: cal)
    let plus6mLeap = CadenceCalculator.addMonths(to: aug31_2023, months: 6, calendar: cal)
    let c6mLeap = componentsOf(plus6mLeap, calendar: cal)
    assertTest(c6mLeap.year == 2024 && c6mLeap.month == 2 && c6mLeap.day == 29, "Aug 31, 2023 + 6 months = Feb 29, 2024 (got \(c6mLeap))")
}

// MARK: - SUITE 2: TELEMETRY BURN-RATE ADVERSARIAL STRESS

func runTelemetryStressTests() {
    print("\n\u{001B}[1m=== SUITE 2: TELEMETRY BURN-RATE ADVERSARIAL STRESS ===\u{001B}[0m")
    
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    
    let baseDate = dateFrom(year: 2026, month: 1, day: 1, calendar: cal)
    
    // 2.1 Zero distance delta (odometer did not move across 30 days)
    let zeroDeltaHistory = [
        (date: baseDate, metric: 100000.0),
        (date: baseDate.addingTimeInterval(30 * 86400), metric: 100000.0)
    ]
    // Without baseline: must return nil safely (no division by zero crash)
    let projZeroNoBase = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 100000.0,
        targetMetric: 110000.0,
        history: zeroDeltaHistory,
        baselineDailyRate: nil,
        currentDate: baseDate.addingTimeInterval(30 * 86400),
        calendar: cal
    )
    assertTest(projZeroNoBase == nil, "Zero distance delta without baseline returns nil safely")
    
    // With baseline: must fall back to baseline rate (e.g. 35.0 km/day)
    let projZeroWithBase = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 100000.0,
        targetMetric: 103500.0,
        history: zeroDeltaHistory,
        baselineDailyRate: 35.0,
        currentDate: baseDate.addingTimeInterval(30 * 86400),
        calendar: cal
    )
    assertTest(projZeroWithBase != nil, "Zero distance delta with baseline produces projection")
    if let p = projZeroWithBase {
        assertTest(p.isEstimatedFromBaseline == true, "Projection is marked as estimated from baseline")
        assertTest(p.dailyBurnRate == 35.0, "Daily burn rate matches baseline rate")
        assertTest(p.daysRemaining == 100, "Days remaining calculated correctly (3500 / 35 = 100)")
    }
    
    // 2.2 Odometer rollback / negative delta
    let rollbackHistory = [
        (date: baseDate, metric: 150000.0),
        (date: baseDate.addingTimeInterval(15 * 86400), metric: 120000.0)
    ]
    let projRollbackNoBase = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 120000.0,
        targetMetric: 130000.0,
        history: rollbackHistory,
        baselineDailyRate: nil,
        currentDate: baseDate.addingTimeInterval(15 * 86400),
        calendar: cal
    )
    assertTest(projRollbackNoBase == nil, "Rollback anomaly without baseline returns nil")
    
    let projRollbackWithBase = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 120000.0,
        targetMetric: 130000.0,
        history: rollbackHistory,
        baselineDailyRate: 40.0,
        currentDate: baseDate.addingTimeInterval(15 * 86400),
        calendar: cal
    )
    assertTest(projRollbackWithBase != nil, "Rollback anomaly with baseline produces fallback projection")
    if let p = projRollbackWithBase {
        assertTest(p.hasRollbackAnomaly == true, "Rollback anomaly flag is TRUE")
        assertTest(p.isEstimatedFromBaseline == true, "Rollback fallback is marked baseline")
    }
    
    // Intermittent rollback in 4 readings (first < last, but intermediate dropped)
    let intermediateRollback = [
        (date: baseDate, metric: 100000.0),
        (date: baseDate.addingTimeInterval(10 * 86400), metric: 110000.0),
        (date: baseDate.addingTimeInterval(20 * 86400), metric: 105000.0), // rollback!
        (date: baseDate.addingTimeInterval(30 * 86400), metric: 112000.0)
    ]
    let projIntermittent = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 112000.0,
        targetMetric: 120000.0,
        history: intermediateRollback,
        baselineDailyRate: 50.0,
        currentDate: baseDate.addingTimeInterval(30 * 86400),
        calendar: cal
    )
    assertTest(projIntermittent?.hasRollbackAnomaly == true, "Intermediate consecutive reading rollback flagged as anomaly")
    
    // 2.3 Extreme telemetry values (> 1,000,000 km)
    let megaHistory = [
        (date: baseDate, metric: 1_250_000.0),
        (date: baseDate.addingTimeInterval(50 * 86400), metric: 1_255_000.0) // 5,000 km in 50 days = 100 km/day
    ]
    let projMega = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 1_255_000.0,
        targetMetric: 1_270_000.0, // 15,000 km remaining / 100 = 150 days
        history: megaHistory,
        baselineDailyRate: nil,
        currentDate: baseDate.addingTimeInterval(50 * 86400),
        calendar: cal
    )
    assertTest(projMega != nil, "High odometer values (>1M km) project successfully")
    if let p = projMega {
        assertTest(abs(p.dailyBurnRate - 100.0) < 0.01, "Burn rate accurately computed for >1M km (got \(p.dailyBurnRate))")
        assertTest(p.daysRemaining == 150, "Days remaining for >1M km is 150 (got \(p.daysRemaining))")
    }
    
    // 2.4 Zero days elapsed (two readings at identical timestamp)
    let zeroDaysHistory = [
        (date: baseDate, metric: 10000.0),
        (date: baseDate, metric: 10050.0)
    ]
    let projZeroDays = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 10050.0,
        targetMetric: 15000.0,
        history: zeroDaysHistory,
        baselineDailyRate: nil,
        currentDate: baseDate,
        calendar: cal
    )
    assertTest(projZeroDays == nil, "Identical timestamp (zero days elapsed) returns nil without division-by-zero crash")
    
    // 2.5 Exactly 1 day elapsed
    let oneDayHistory = [
        (date: baseDate, metric: 20000.0),
        (date: baseDate.addingTimeInterval(86400), metric: 20060.0) // 60 km in 1 day
    ]
    let projOneDay = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 20060.0,
        targetMetric: 20360.0, // 300 km remaining / 60 km/day = 5 days
        history: oneDayHistory,
        baselineDailyRate: nil,
        currentDate: baseDate.addingTimeInterval(86400),
        calendar: cal
    )
    assertTest(projOneDay != nil, "1 day elapsed projects cleanly")
    if let p = projOneDay {
        assertTest(abs(p.dailyBurnRate - 60.0) < 0.01, "Daily rate for 1-day interval is 60.0 km/day (got \(p.dailyBurnRate))")
        assertTest(p.daysRemaining == 5, "Days remaining is 5 (got \(p.daysRemaining))")
    }
    
    // 2.6 Target already exceeded
    let projExceeded = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 15500.0,
        targetMetric: 15000.0,
        history: oneDayHistory,
        currentDate: baseDate,
        calendar: cal
    )
    assertTest(projExceeded != nil, "Target exceeded returns immediate projection")
    if let p = projExceeded {
        assertTest(p.isDueImmediately == true, "Target exceeded has isDueImmediately = true")
        assertTest(p.daysRemaining == 0, "Target exceeded daysRemaining == 0")
        assertTest(p.remainingMetric == -500.0, "Remaining metric is -500.0")
    }
    
    // 2.7 Target exactly met
    let projExact = CadenceCalculator.projectTelemetryDueDate(
        currentMetric: 15000.0,
        targetMetric: 15000.0,
        history: oneDayHistory,
        currentDate: baseDate,
        calendar: cal
    )
    assertTest(projExact?.isDueImmediately == true, "Target exactly met has isDueImmediately = true")
}

// MARK: - SUITE 3: ROMANIAN UTILITY REGEX ADVERSARIAL STRESS

func runRomanianUtilityRegexStressTests() {
    print("\n\u{001B}[1m=== SUITE 3: ROMANIAN UTILITY REGEX ADVERSARIAL STRESS ===\u{001B}[0m")
    
    let parser = RomanianUtilityParser.shared
    
    // 3.1 Case insensitivity & OCR noise in provider detection
    let messyDigi = """
    sc rcs & rds sa bucuresti
    FACTURA seria FCR nr 89412
    cod client: 12345678
    Data scadenta: 28.02.2026
    Total de plata: 145,50 LEI
    Cod plata: 98765432
    """
    let resDigi = parser.parseUtilityBill(text: messyDigi)
    assertTest(resDigi.provider == .digi, "Messy lowercase 'rcs & rds' detected as DIGI")
    assertTest(resDigi.clientCode == "12345678", "Digi client code extracted correctly (got \(resDigi.clientCode ?? "nil"))")
    assertTest(resDigi.totalAmount == 145.50, "Digi total amount 145,50 LEI parsed (got \(resDigi.totalAmount ?? -1))")
    assertTest(resDigi.barcodeRaw == "98765432", "Digi cod plata extracted (got \(resDigi.barcodeRaw ?? "nil"))")
    
    // 3.2 Complex number formats and currencies
    let amountsToTest: [(raw: String, expected: Double)] = [
        ("Total de plata: 14.502,30 LEI", 14502.30),
        ("Total factura: 123,45 RON", 123.45),
        ("De plata: 0,99 lei", 0.99),
        ("Rest de plata: 2.500,00 EUR", 2500.00),
        ("Total: 50.00 lei", 50.00)
    ]
    for (raw, exp) in amountsToTest {
        let snippet = "Furnizor Test S.A. Cod client: 10293847 Scadenta: 15.11.2026 \(raw)"
        let parsed = parser.parseUtilityBill(text: snippet)
        assertTest(
            parsed.totalAmount != nil && abs(parsed.totalAmount! - exp) < 0.01,
            "Amount '\(raw)' correctly parsed as \(exp) (got \(parsed.totalAmount ?? -1))"
        )
    }
    
    // 3.3 Mixed Date Separators (. / -)
    let dateSeparators = [
        ("Data scadenta: 25.11.2026", 2026, 11, 25),
        ("Data scadentei: 25/11/2026", 2026, 11, 25),
        ("Termen plata: 25-11-2026", 2026, 11, 25)
    ]
    for (dStr, expY, expM, expD) in dateSeparators {
        let snippet = "DIGI ROMANIA Cod client: 12345678 \(dStr) Total: 100,00 LEI"
        let parsed = parser.parseUtilityBill(text: snippet)
        assertTest(parsed.dueDate != nil, "Date with separator parsed for '\(dStr)'")
        if let d = parsed.dueDate {
            let c = componentsOf(d)
            assertTest(c.year == expY && c.month == expM && c.day == expD, "Date components match \(expY)-\(expM)-\(expD) (got \(c))")
        }
    }
    
    // 3.4 Written Romanian Month Parsing
    let writtenMonthSnippets = [
        ("Data scadenta: 15 ianuarie 2026", 2026, 1, 15),
        ("Scadenta: 28 februarie 2026", 2026, 2, 28),
        ("Termen de plata: 31 martie 2026", 2026, 3, 31),
        ("Data scadentei: 30 aprilie 2026", 2026, 4, 30),
        ("Scadent la: 15 mai 2026", 2026, 5, 15),
        ("Data limita de plata: 30 iunie 2026", 2026, 6, 30),
        ("Scadenta: 31 iulie 2026", 2026, 7, 31),
        ("Data scadenta: 31 august 2026", 2026, 8, 31),
        ("Plateste pana la: 30 septembrie 2026", 2026, 9, 30),
        ("Data scadenta: 31 octombrie 2026", 2026, 10, 31),
        ("Data scadentei: 15 noiembrie 2026", 2026, 11, 15),
        ("Scadenta: 31 decembrie 2026", 2026, 12, 31)
    ]
    for (wStr, expY, expM, expD) in writtenMonthSnippets {
        let snippet = "ENGIE Romania S.A. Cod client: 194820192 Index nou: 1450 mc \(wStr) Total de plata: 210,50 LEI"
        let parsed = parser.parseUtilityBill(text: snippet)
        assertTest(parsed.dueDate != nil, "Written month parsed for '\(wStr)'")
        if let d = parsed.dueDate {
            let c = componentsOf(d)
            assertTest(c.year == expY && c.month == expM && c.day == expD, "Written month date matches \(expY)-\(expM)-\(expD) (got \(c))")
        }
    }
    
    // 3.5 All 7 Providers with tricky text inputs:
    
    // 1) PPC / Enel with long utility barcode and '30...' client code
    let ppcText = """
    PPC ENERGIE MUNTENIA S.A.
    Cod client: 3004928192
    Loc de consum: 50492819
    Scadent la: 14.12.2026
    Index vechi: 12400
    Index nou autocitit: 12650
    Total de plata: 341,85 LEI
    00030049281920000000003418514122026000000000
    """
    let resPpc = parser.parseUtilityBill(text: ppcText)
    assertTest(resPpc.provider == .ppcEnel, "Provider PPC recognized")
    assertTest(resPpc.clientCode == "3004928192", "PPC client code 3004928192 extracted (got \(resPpc.clientCode ?? "nil"))")
    assertTest(resPpc.indexReading == 12650.0, "PPC index nou autocitit 12650 extracted (got \(resPpc.indexReading ?? -1))")
    assertTest(resPpc.totalAmount == 341.85, "PPC total 341.85 extracted (got \(resPpc.totalAmount ?? -1))")
    assertTest(resPpc.barcodeRaw != nil && resPpc.barcodeRaw!.hasPrefix("00030049"), "PPC long barcode extracted")
    
    // 2) Hidroelectrica with 1.8.0 active energy & POD code
    let hidroText = """
    SPEEH HIDROELECTRICA S.A.
    Cod client: 748291
    Factura nr: 2026094812
    POD: RO001E1029384756
    1.8.0 Energie activa: 4892.5
    Data emiterii: 10.10.2026
    Data scadenta: 25.11.2026
    Total de plata: 395,20 LEI
    """
    let resHidro = parser.parseUtilityBill(text: hidroText)
    assertTest(resHidro.provider == .hidroelectrica, "Provider Hidroelectrica recognized")
    assertTest(resHidro.clientCode == "748291", "Hidroelectrica client code extracted (got \(resHidro.clientCode ?? "nil"))")
    assertTest(resHidro.indexReading == 4892.5, "Hidroelectrica 1.8.0 active energy extracted (got \(resHidro.indexReading ?? -1))")
    assertTest(resHidro.totalAmount == 395.20, "Hidroelectrica total amount extracted (got \(resHidro.totalAmount ?? -1))")
    assertTest(resHidro.barcodeRaw == "RO001E1029384756", "Hidroelectrica POD barcode extracted (got \(resHidro.barcodeRaw ?? "nil"))")
    
    // 3) E.ON with Cod incasare & client code
    let eonText = """
    E.ON ENERGIE ROMANIA S.A.
    Cod incasare: 1948201948
    Cod client: 1948201948
    Index nou: 3410
    Scadenta: 20.12.2026
    Total de plata: 289,00 LEI
    """
    let resEon = parser.parseUtilityBill(text: eonText)
    assertTest(resEon.provider == .eon, "Provider E.ON recognized")
    assertTest(resEon.clientCode == "1948201948", "E.ON client code extracted (got \(resEon.clientCode ?? "nil"))")
    assertTest(resEon.indexReading == 3410.0, "E.ON index reading extracted (got \(resEon.indexReading ?? -1))")
    assertTest(resEon.totalAmount == 289.00, "E.ON total amount extracted (got \(resEon.totalAmount ?? -1))")
    
    // 4) Engie with gas meter index in mc and 'referinta partener'
    let engieText = """
    ENGIE ROMANIA S.A.
    Referinta partener: 1029384756
    Factura fiscala nr: 10928374
    Index nou: 2981 mc
    Data emiterii: 05.10.2026
    Data scadenta: 04.11.2026
    Total de plata: 184,65 LEI
    """
    let resEngie = parser.parseUtilityBill(text: engieText)
    assertTest(resEngie.provider == .engie, "Provider ENGIE recognized")
    assertTest(resEngie.clientCode == "1029384756", "Engie referinta partener extracted as clientCode (got \(resEngie.clientCode ?? "nil"))")
    assertTest(resEngie.indexReading == 2981.0, "Engie gas index 2981 extracted (got \(resEngie.indexReading ?? -1))")
    assertTest(resEngie.totalAmount == 184.65, "Engie total amount extracted (got \(resEngie.totalAmount ?? -1))")
    
    // 5) Orange with alphanumeric invoice and subscriber code
    let orangeText = """
    ORANGE ROMANIA S.A.
    Cod abonat: 89410294
    Factura nr: ORG8492019
    Scadenta: 18.11.2026
    Total de plata: 95,20 LEI
    """
    let resOrange = parser.parseUtilityBill(text: orangeText)
    assertTest(resOrange.provider == .orange, "Provider Orange recognized")
    assertTest(resOrange.clientCode == "89410294", "Orange cod abonat extracted (got \(resOrange.clientCode ?? "nil"))")
    assertTest(resOrange.totalAmount == 95.20, "Orange total amount extracted (got \(resOrange.totalAmount ?? -1))")
    
    // 6) Vodafone with client number and invoice series
    let vodafoneText = """
    VODAFONE ROMANIA S.A.
    Cod client: 49201948
    Numar factura: VDF9820194
    Data scadenta: 22.11.2026
    Total de plata: 115,00 RON
    """
    let resVodafone = parser.parseUtilityBill(text: vodafoneText)
    assertTest(resVodafone.provider == .vodafone, "Provider Vodafone recognized")
    assertTest(resVodafone.clientCode == "49201948", "Vodafone cod client extracted (got \(resVodafone.clientCode ?? "nil"))")
    assertTest(resVodafone.totalAmount == 115.00, "Vodafone total amount extracted (got \(resVodafone.totalAmount ?? -1))")
    
    // 7) General / Chitanta fallback
    let chitantaText = """
    ASOCIATIE DE PROPRIETARI BLOC A4
    Chitanta seria INT nr 49201
    Numar client: AP-42
    Data: 10.11.2026
    Suma de plata: 240,00 LEI
    """
    let resChitanta = parser.parseUtilityBill(text: chitantaText)
    assertTest(resChitanta.provider == .general, "Generic receipt recognized as General")
    assertTest(resChitanta.totalAmount == 240.00, "Generic receipt sum parsed (got \(resChitanta.totalAmount ?? -1))")
}

// MARK: - MAIN ENTRY

@main
struct AdversarialRunner {
    static func main() {
        print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
        print("\u{001B}[1m\u{001B}[36m    DOSAR CU ȘINĂ — EMPIRICAL ADVERSARIAL STRESS SUITE (iOS)     \u{001B}[0m")
        print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
        
        runLeapYearStressTests()
        runTelemetryStressTests()
        runRomanianUtilityRegexStressTests()
        
        print("\n\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
        print("\u{001B}[1mRESULTS: Total: \(totalTests) | Passed: \(passedTests) | Failed: \(failedTests)\u{001B}[0m")
        if failedTests == 0 {
            print("\u{001B}[32m\u{001B}[1m🎉 ALL EMPIRICAL ADVERSARIAL TESTS PASSED (100%)\u{001B}[0m")
            print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
            exit(0)
        } else {
            print("\u{001B}[31m\u{001B}[1m⚠️ ADVERSARIAL TESTS DETECTED FAILURES!\u{001B}[0m")
            print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
            exit(1)
        }
    }
}
