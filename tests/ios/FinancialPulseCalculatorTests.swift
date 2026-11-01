import Foundation
import SwiftData

/// Comprehensive unit test suite for FinancialPulseCalculator covering all 5 analytical dimensions:
/// 1. 30 / 60 / 90-day cash flow forecast (committed upcoming vs prior actuals).
/// 2. Recurring vs Non-recurring spend split and monthly baseline.
/// 3. Asset Total Cost of Ownership (TCO) lifetime & trailing 12-month rankings.
/// 4. Subscription normalized monthly burn rate and contract retention alerts.
/// 5. Seasonal utility consumption curves across electricity, gas, and water.
public final class FinancialPulseCalculatorTests: Sendable {
    
    // MARK: - Test 1: Cash Flow Forecast (30 / 60 / 90 Days)
    public static func testCashFlowForecastCommittedAndActuals() throws {
        let calendar = Calendar.current
        let refDate = Date()
        let startOfRef = calendar.startOfDay(for: refDate)
        
        let due15 = calendar.date(byAdding: .day, value: 15, to: startOfRef)!
        let due45 = calendar.date(byAdding: .day, value: 45, to: startOfRef)!
        let due75 = calendar.date(byAdding: .day, value: 75, to: startOfRef)!
        let due120 = calendar.date(byAdding: .day, value: 120, to: startOfRef)! // outside 90d
        
        // Upcoming uncompleted events
        let ev1 = LifecycleEvent(title: "RCA Asigurare", dueDate: due15, cost: 600.0)
        let ev2 = LifecycleEvent(title: "Revizie ISCIR", dueDate: due45, cost: 450.0)
        let ev3 = LifecycleEvent(title: "Impozit Clădire", dueDate: due75, cost: 300.0)
        let ev4 = LifecycleEvent(title: "Service Anual", dueDate: due120, cost: 1000.0)
        let evCompletedUpcoming = LifecycleEvent(title: "Deja Plătit", dueDate: due15, isCompleted: true, cost: 500.0)
        
        // Prior actual events
        let prior10 = calendar.date(byAdding: .day, value: -10, to: startOfRef)!
        let prior50 = calendar.date(byAdding: .day, value: -50, to: startOfRef)!
        let prior80 = calendar.date(byAdding: .day, value: -80, to: startOfRef)!
        let prior120 = calendar.date(byAdding: .day, value: -120, to: startOfRef)! // outside 90d
        
        let evPast1 = LifecycleEvent(title: "Factură Hidro", dueDate: prior10, completedDate: prior10, isCompleted: true, cost: 180.0)
        let evPast2 = LifecycleEvent(title: "Taxă Drum", dueDate: prior50, completedDate: prior50, isCompleted: true, cost: 120.0)
        let evPast3 = LifecycleEvent(title: "Consult Medical", dueDate: prior80, completedDate: prior80, isCompleted: true, cost: 250.0)
        let evPastOld = LifecycleEvent(title: "Piese Vechi", dueDate: prior120, completedDate: prior120, isCompleted: true, cost: 800.0)
        
        // Prior service items
        let srvPast1 = ServiceItem(name: "Schimb Filtre", cost: 200.0, serviceDate: prior10)
        let srvPast2 = ServiceItem(name: "Schimb Ulei", laborCost: 150.0, partsCost: 250.0, serviceDate: prior50) // total 400
        
        // Prior utility measurement
        let measPast1 = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor",
            value: 4600.0,
            recordedAt: prior10,
            previousValue: 4400.0,
            unitPrice: 0.70
        ) // delta 200 * 0.70 = 140.0
        
        let allEvents = [ev1, ev2, ev3, ev4, evCompletedUpcoming, evPast1, evPast2, evPast3, evPastOld]
        let allServices = [srvPast1, srvPast2]
        let allMeasurements = [measPast1]
        
        let forecast = FinancialPulseCalculator.computeCashFlowForecast(
            events: allEvents,
            serviceItems: allServices,
            measurements: allMeasurements,
            referenceDate: refDate,
            startOfRefDate: startOfRef,
            calendar: calendar
        )
        
        // Committed upcoming verification
        // 30d: ev1 (600) = 600
        try assertAlmostEqual(forecast.days30Committed, 600.0, accuracy: 0.01, "30-day committed must be 600 RON")
        // 60d: ev1 (600) + ev2 (450) = 1050
        try assertAlmostEqual(forecast.days60Committed, 1050.0, accuracy: 0.01, "60-day committed must be 1050 RON")
        // 90d: ev1 (600) + ev2 (450) + ev3 (300) = 1350 (ev4 is at 120d, excluded)
        try assertAlmostEqual(forecast.days90Committed, 1350.0, accuracy: 0.01, "90-day committed must be 1350 RON")
        
        // Actual historical verification
        // Prior 30d: evPast1 (180) + srvPast1 (200) + measPast1 (140) = 520
        try assertAlmostEqual(forecast.prior30DaysActual, 520.0, accuracy: 0.01, "Prior 30-day actuals must be 520 RON")
        // Prior 60d: 520 + evPast2 (120) + srvPast2 (400) = 1040
        try assertAlmostEqual(forecast.prior60DaysActual, 1040.0, accuracy: 0.01, "Prior 60-day actuals must be 1040 RON")
        // Prior 90d: 1040 + evPast3 (250) = 1290 (evPastOld is at -120d, excluded)
        try assertAlmostEqual(forecast.prior90DaysActual, 1290.0, accuracy: 0.01, "Prior 90-day actuals must be 1290 RON")
    }
    
    // MARK: - Test 2: Recurring vs Non-Recurring Spend Split
    public static func testRecurringVsNonRecurringSpendSplit() throws {
        let calendar = Calendar.current
        let refDate = Date()
        let startOfRef = calendar.startOfDay(for: refDate)
        
        let assetHome = Asset(name: "Apartament", category: .home)
        let assetCar = Asset(name: "Dacia Duster", category: .vehicle)
        let assetSub = Asset(name: "Digi Net", category: .subscriptions, billingCycle: "Lunar", recurringAmount: 50.0)
        
        // Recurring event with cadence 365 days (annual: 365 RON/an -> 365.0)
        let evRCA = LifecycleEvent(title: "Asigurare RCA", dueDate: refDate, cost: 730.0, cadenceDays: 365)
        evRCA.asset = assetCar
        
        // Recurring event with cadence 30 days (monthly: 100 RON/luna -> 1216.66 RON/an)
        let evInternet = LifecycleEvent(title: "Factură Utilități", dueDate: refDate, cost: 100.0, cadenceDays: 30)
        evInternet.asset = assetHome
        
        // Non-recurring service item in trailing 12m
        let srvRepair = ServiceItem(name: "Înlocuire Ambreiaj", cost: 1500.0, serviceDate: refDate)
        srvRepair.asset = assetCar
        
        let breakdown = FinancialPulseCalculator.computeSpendBreakdown(
            assets: [assetHome, assetCar, assetSub],
            events: [evRCA, evInternet],
            serviceItems: [srvRepair],
            referenceDate: refDate,
            startOfRefDate: startOfRef,
            calendar: calendar
        )
        
        // Recurring:
        // evRCA: 730 * 365/365 = 730 RON/an
        // evInternet: 100 * 365/30 = 1216.666 RON/an
        // assetSub: 50 * 12 = 600 RON/an
        // Total recurring annual = 730 + 1216.67 + 600 = 2546.67 RON
        try assertAlmostEqual(breakdown.recurringAnnualTotal, 2546.67, accuracy: 1.0, "Annual recurring must be ~2546.67 RON")
        try assertAlmostEqual(breakdown.recurringMonthlyBaseline, 2546.67 / 12.0, accuracy: 1.0, "Monthly baseline must be ~212.22 RON")
        
        // Non-recurring:
        // srvRepair: 1500.0
        try assertAlmostEqual(breakdown.nonRecurringAnnualTotal, 1500.0, accuracy: 0.01, "Non-recurring annual must be 1500 RON")
        
        // Total = 2546.67 + 1500 = 4046.67
        // Rec % = 2546.67 / 4046.67 * 100 = ~62.9%
        // Non-rec % = 1500 / 4046.67 * 100 = ~37.1%
        try assertTrue(breakdown.recurringPercentage > 60.0 && breakdown.recurringPercentage < 65.0, "Recurring percentage should be ~62.9%")
        try assertTrue(breakdown.nonRecurringPercentage > 35.0 && breakdown.nonRecurringPercentage < 40.0, "Non-recurring percentage should be ~37.1%")
        
        // Verify category rankings
        try assertTrue(breakdown.topNonRecurringCategories.contains { $0.category == .vehicle }, "Top non-recurring category must include vehicles")
    }
    
    // MARK: - Test 3: Asset Total Cost of Ownership (TCO)
    public static func testAssetTotalCostOfOwnershipRankings() throws {
        let calendar = Calendar.current
        let refDate = Date()
        let startOfRef = calendar.startOfDay(for: refDate)
        
        // Asset 1: Car with purchase price, events, service items
        let car = Asset(name: "VW Golf", category: .vehicle, purchasePrice: 25000.0)
        let evCar = LifecycleEvent(title: "RCA", dueDate: refDate, cost: 800.0)
        evCar.asset = car
        let srvCar = ServiceItem(name: "Distribuție", cost: 1200.0, serviceDate: refDate)
        srvCar.asset = car
        
        // Asset 2: Apartment with purchase price, events, utility measurements
        let apt = Asset(name: "Apartament 3 Camere", category: .home, purchasePrice: 450000.0)
        let evApt = LifecycleEvent(title: "Impozit", dueDate: refDate, cost: 350.0)
        evApt.asset = apt
        let measApt = MeasurementLog(
            domain: .gasMeter,
            metricName: "Contor Gaze",
            value: 1500.0,
            recordedAt: refDate,
            previousValue: 1400.0,
            unitPrice: 3.10
        ) // 100 m3 * 3.10 = 310.0 RON
        measApt.asset = apt
        
        let tcoList = FinancialPulseCalculator.computeAssetTCO(
            assets: [car, apt],
            events: [evCar, evApt],
            serviceItems: [srvCar],
            measurements: [measApt],
            referenceDate: refDate,
            startOfRefDate: startOfRef,
            calendar: calendar
        )
        
        try assertEqual(tcoList.count, 2)
        // Apartment must rank #1 due to purchase price
        try assertEqual(tcoList[0].assetName, "Apartament 3 Camere")
        try assertAlmostEqual(tcoList[0].purchasePrice, 450000.0, accuracy: 0.01)
        try assertAlmostEqual(tcoList[0].eventsCost, 350.0, accuracy: 0.01)
        try assertAlmostEqual(tcoList[0].measurementsCost, 310.0, accuracy: 0.01)
        try assertAlmostEqual(tcoList[0].lifetimeTCO, 450660.0, accuracy: 0.01)
        
        // Car must rank #2
        try assertEqual(tcoList[1].assetName, "VW Golf")
        try assertAlmostEqual(tcoList[1].purchasePrice, 25000.0, accuracy: 0.01)
        try assertAlmostEqual(tcoList[1].eventsCost, 800.0, accuracy: 0.01)
        try assertAlmostEqual(tcoList[1].serviceItemsCost, 1200.0, accuracy: 0.01)
        try assertAlmostEqual(tcoList[1].lifetimeTCO, 27000.0, accuracy: 0.01)
    }
    
    // MARK: - Test 4: Subscription Normalized Burn Rate & Alerts
    public static func testSubscriptionBurnRateAndAlerts() throws {
        let calendar = Calendar.current
        let refDate = Date()
        let startOfRef = calendar.startOfDay(for: refDate)
        
        // Weekly subscription: 10 RON/week -> 10 * 52 / 12 = 43.33 RON/mo
        let subWeekly = Asset(name: "Abonament Ziar", category: .subscriptions, billingCycle: "Săptămânal", recurringAmount: 10.0)
        
        // Monthly subscription: 45 RON/mo -> 45 RON/mo
        let subMonthly = Asset(name: "Netflix", category: .subscriptions, billingCycle: "Lunar", recurringAmount: 45.0)
        
        // Quarterly subscription: 90 RON/trimestru -> 30 RON/mo
        let subQuarterly = Asset(name: "Abonament Trimestrial", category: .subscriptions, billingCycle: "Trimestrial", recurringAmount: 90.0)
        
        // Annual subscription: 240 RON/an -> 20 RON/mo
        let subAnnual = Asset(name: "iCloud Storage", category: .subscriptions, billingCycle: "Anual", recurringAmount: 240.0)
        
        // Free trial converting in 5 days (under 7 days -> trial converting soon)
        let trialEnd = calendar.date(byAdding: .day, value: 5, to: startOfRef)!
        let subTrial = Asset(name: "YouTube Premium Free Trial", category: .subscriptions, notes: "Trial gratuit", billingCycle: "Lunar", recurringAmount: 0.0, contractEndDate: trialEnd)
        
        // Telecom subscription with contract ending in 25 days (retention window active!)
        let contractEnd = calendar.date(byAdding: .day, value: 25, to: startOfRef)!
        let subTelecom = Asset(name: "Digi Fibra 1000", category: .subscriptions, billingCycle: "Lunar", recurringAmount: 40.0, contractEndDate: contractEnd)
        
        let burnRate = FinancialPulseCalculator.computeSubscriptionBurnRate(
            assets: [subWeekly, subMonthly, subQuarterly, subAnnual, subTrial, subTelecom],
            events: [],
            referenceDate: refDate,
            startOfRefDate: startOfRef,
            calendar: calendar
        )
        
        // Check counts
        try assertEqual(burnRate.activeSubscriptionsCount, 6)
        try assertEqual(burnRate.freeTrialsCount, 1)
        try assertEqual(burnRate.trialConversionsSoonCount, 1, "Should flag 1 free trial converting in <= 7 days")
        try assertEqual(burnRate.retentionOpportunitiesCount, 1, "Should flag 1 telecom contract in retention window")
        
        // Check normalized monthly calculations:
        // Weekly: 43.33
        // Monthly: 45.0
        // Quarterly: 30.0
        // Annual: 20.0
        // Trial: 0.0
        // Telecom: 40.0
        // Total monthly burn: 43.33 + 45 + 30 + 20 + 0 + 40 = 178.33 RON
        try assertAlmostEqual(burnRate.totalMonthlyBurnRate, 178.33, accuracy: 0.1, "Total monthly burn rate must be ~178.33 RON")
        try assertAlmostEqual(burnRate.totalAnnualCommitment, 178.33 * 12.0, accuracy: 1.0, "Annual commitment must be ~2140 RON")
    }
    
    // MARK: - Test 5: Seasonal Utility Consumption Curves
    public static func testSeasonalUtilityConsumptionCurves() throws {
        let calendar = Calendar.current
        let refDate = Date()
        
        // Create measurements over recent months
        // Month 0 (current month): 150 kWh electricity, 20 m3 gas, 10 m3 water
        let mCurrentElec = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Curent",
            value: 2150.0,
            recordedAt: refDate,
            previousValue: 2000.0,
            unitPrice: 0.75
        ) // 150 kWh * 0.75 = 112.50 RON
        
        let mCurrentGas = MeasurementLog(
            domain: .gasMeter,
            metricName: "Index Gaz",
            value: 520.0,
            recordedAt: refDate,
            previousValue: 500.0,
            unitPrice: 3.0
        ) // 20 m3 * 3.0 = 60.0 RON
        
        let mCurrentWater = MeasurementLog(
            domain: .coldWaterMeter,
            metricName: "Index Apă Rece",
            value: 110.0,
            recordedAt: refDate,
            previousValue: 100.0,
            unitPrice: 5.0
        ) // 10 m3 * 5.0 = 50.0 RON
        
        // Month -1 (last month): 200 kWh electricity, 80 m3 gas (winter spike)
        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: refDate)!
        let mLastGas = MeasurementLog(
            domain: .gasMeter,
            metricName: "Index Gaz",
            value: 500.0,
            recordedAt: lastMonthDate,
            previousValue: 420.0,
            unitPrice: 3.0
        ) // 80 m3 * 3.0 = 240.0 RON
        
        let curves = FinancialPulseCalculator.computeSeasonalUtilityCurves(
            measurements: [mCurrentElec, mCurrentGas, mCurrentWater, mLastGas],
            referenceDate: refDate,
            calendar: calendar
        )
        
        // Must contain 12 months
        try assertEqual(curves.count, 12, "Must return exactly 12 chronological months")
        
        // Month 11 is the current month
        let currentCurve = curves[11]
        try assertAlmostEqual(currentCurve.electricityKWh, 150.0, accuracy: 0.01)
        try assertAlmostEqual(currentCurve.gasM3, 20.0, accuracy: 0.01)
        try assertAlmostEqual(currentCurve.waterM3, 10.0, accuracy: 0.01)
        // Cost: 112.50 + 60.0 + 50.0 = 222.50 RON
        try assertAlmostEqual(currentCurve.estimatedCostRON, 222.50, accuracy: 0.01)
        
        // Month 10 is last month: gas should be 80 m3
        let lastMonthCurve = curves[10]
        try assertAlmostEqual(lastMonthCurve.gasM3, 80.0, accuracy: 0.01)
        try assertAlmostEqual(lastMonthCurve.estimatedCostRON, 240.0, accuracy: 0.01)
    }
    
    // MARK: - Test 6: Unified Master Pulse Calculation
    public static func testUnifiedMasterPulseCalculation() throws {
        let refDate = Date()
        let apt = Asset(name: "Apartament", category: .home, purchasePrice: 350000.0)
        let ev = LifecycleEvent(title: "RCA", dueDate: refDate, cost: 700.0)
        ev.asset = apt
        let srv = ServiceItem(name: "Revizie Centrală", cost: 350.0, serviceDate: refDate)
        srv.asset = apt
        let meas = MeasurementLog(domain: .electricityMeter, metricName: "Contor", value: 1000.0, recordedAt: refDate, previousValue: 900.0, unitPrice: 0.8)
        meas.asset = apt
        
        let pulse = FinancialPulseCalculator.calculatePulse(
            assets: [apt],
            events: [ev],
            serviceItems: [srv],
            measurements: [meas],
            referenceDate: refDate
        )
        
        try assertEqual(pulse.rankedTCO.count, 1)
        try assertEqual(pulse.utilityCurves.count, 12)
        try assertTrue(pulse.rankedTCO[0].lifetimeTCO > 350000.0)
    }
    
    // MARK: - Test 7: Cash Flow Zero & Negative Edge Cases
    public static func testCashFlowZeroAndNegativeEdgeCases() throws {
        let refDate = Date()
        let calendar = Calendar.current
        let startOfRef = calendar.startOfDay(for: refDate)
        
        let dueIn5 = calendar.date(byAdding: .day, value: 5, to: startOfRef)!
        let zeroEvent = LifecycleEvent(title: "Event cu Cost 0", dueDate: dueIn5, cost: 0.0)
        let nilEvent = LifecycleEvent(title: "Event Fără Cost", dueDate: dueIn5, cost: nil)
        let negEvent = LifecycleEvent(title: "Event Negativ", dueDate: dueIn5, cost: -50.0)
        
        let forecast = FinancialPulseCalculator.computeCashFlowForecast(
            events: [zeroEvent, nilEvent, negEvent],
            serviceItems: [],
            measurements: [],
            referenceDate: refDate,
            startOfRefDate: startOfRef
        )
        
        try assertEqual(forecast.days30Committed, 0.0)
        try assertEqual(forecast.days60Committed, 0.0)
        try assertEqual(forecast.days90Committed, 0.0)
        try assertTrue(forecast.upcomingEventsNext30Days.isEmpty)
    }
    
    // MARK: - Test 8: Billing Cycle Normalization Variants & Fallbacks
    public static func testBillingCycleNormalizationVariants() throws {
        // Weekly: 120 RON * 52 / 12 = 520 RON/luna
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 120.0, cycle: "Săptămânal"), 520.0, accuracy: 0.01)
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 120.0, cycle: "weekly"), 520.0, accuracy: 0.01)
        
        // Trimestrial: 300 RON / 3 = 100 RON/luna
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 300.0, cycle: "Trimestrial"), 100.0, accuracy: 0.01)
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 300.0, cycle: "3 luni"), 100.0, accuracy: 0.01)
        
        // Semestrial: 600 RON / 6 = 100 RON/luna
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 600.0, cycle: "Semestrial"), 100.0, accuracy: 0.01)
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 600.0, cycle: "6 luni"), 100.0, accuracy: 0.01)
        
        // Anual: 1200 RON / 12 = 100 RON/luna
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 1200.0, cycle: "Anual"), 100.0, accuracy: 0.01)
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 1200.0, cycle: "12 luni"), 100.0, accuracy: 0.01)
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 1200.0, cycle: "1 an"), 100.0, accuracy: 0.01)
        
        // Default / Unknown: returns amount unchanged
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 55.0, cycle: "Lunar"), 55.0, accuracy: 0.01)
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 75.0, cycle: nil), 75.0, accuracy: 0.01)
        try assertAlmostEqual(FinancialPulseCalculator.normalizeToMonthlyRate(amount: 80.0, cycle: "necunoscut"), 80.0, accuracy: 0.01)
    }
    
    // MARK: - Test 9: Empty Data Safety Guards
    public static func testEmptyDataSafetyGuards() throws {
        let pulse = FinancialPulseCalculator.calculatePulse(
            assets: [],
            events: [],
            serviceItems: [],
            measurements: []
        )
        
        try assertEqual(pulse.cashFlow.days30Committed, 0.0)
        try assertEqual(pulse.spendBreakdown.recurringPercentage, 0.0)
        try assertEqual(pulse.spendBreakdown.nonRecurringPercentage, 0.0)
        try assertEqual(pulse.rankedTCO.count, 0)
        try assertEqual(pulse.subscriptionPulse.activeSubscriptionsCount, 0)
        try assertEqual(pulse.utilityCurves.count, 12)
        try assertEqual(pulse.utilityCurves[0].electricityKWh, 0.0)
    }
    
    // MARK: - Suite Runner
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () throws -> Void)] = [
            ("testCashFlowForecastCommittedAndActuals", testCashFlowForecastCommittedAndActuals),
            ("testRecurringVsNonRecurringSpendSplit", testRecurringVsNonRecurringSpendSplit),
            ("testAssetTotalCostOfOwnershipRankings", testAssetTotalCostOfOwnershipRankings),
            ("testSubscriptionBurnRateAndAlerts", testSubscriptionBurnRateAndAlerts),
            ("testSeasonalUtilityConsumptionCurves", testSeasonalUtilityConsumptionCurves),
            ("testUnifiedMasterPulseCalculation", testUnifiedMasterPulseCalculation),
            ("testCashFlowZeroAndNegativeEdgeCases", testCashFlowZeroAndNegativeEdgeCases),
            ("testBillingCycleNormalizationVariants", testBillingCycleNormalizationVariants),
            ("testEmptyDataSafetyGuards", testEmptyDataSafetyGuards)
        ]
        
        for (name, test) in tests {
            do {
                try test()
                passed += 1
            } catch let error as TestAssertionError {
                failed += 1
                failures.append(TestFailure(testName: name, message: error.message, file: error.file, line: error.line))
            } catch {
                failed += 1
                failures.append(TestFailure(testName: name, message: "\(error)", file: #file, line: #line))
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        return TestSuiteResult(
            suiteName: "FinancialPulseCalculatorTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
