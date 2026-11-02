import Foundation
import SwiftUI

// MARK: - Financial Data Transfer Objects & Summaries

/// Cash flow forecast comparing upcoming committed obligations against prior actual spend.
public struct CashFlowForecast: @unchecked Sendable {
    public let days30Committed: Double
    public let days60Committed: Double
    public let days90Committed: Double
    public let prior30DaysActual: Double
    public let prior60DaysActual: Double
    public let prior90DaysActual: Double
    public let upcomingEventsNext30Days: [LifecycleEvent]
    public let upcomingEventsNext60Days: [LifecycleEvent]
    public let upcomingEventsNext90Days: [LifecycleEvent]
    
    public init(
        days30Committed: Double,
        days60Committed: Double,
        days90Committed: Double,
        prior30DaysActual: Double,
        prior60DaysActual: Double,
        prior90DaysActual: Double,
        upcomingEventsNext30Days: [LifecycleEvent] = [],
        upcomingEventsNext60Days: [LifecycleEvent] = [],
        upcomingEventsNext90Days: [LifecycleEvent] = []
    ) {
        self.days30Committed = days30Committed
        self.days60Committed = days60Committed
        self.days90Committed = days90Committed
        self.prior30DaysActual = prior30DaysActual
        self.prior60DaysActual = prior60DaysActual
        self.prior90DaysActual = prior90DaysActual
        self.upcomingEventsNext30Days = upcomingEventsNext30Days
        self.upcomingEventsNext60Days = upcomingEventsNext60Days
        self.upcomingEventsNext90Days = upcomingEventsNext90Days
    }
}

/// Category spending summary item for hierarchical spend breakdowns.
public struct CategorySpendSummary: Identifiable, Sendable, Equatable {
    public var id: String { category.rawValue }
    public let category: AssetCategory
    public let amount: Double
    public let percentage: Double
    
    public init(category: AssetCategory, amount: Double, percentage: Double) {
        self.category = category
        self.amount = amount
        self.percentage = percentage
    }
}

/// Breakdown of fixed household overhead (recurring) vs discrete interventions (non-recurring).
public struct SpendBreakdown: Sendable {
    public let recurringAnnualTotal: Double
    public let recurringMonthlyBaseline: Double
    public let nonRecurringAnnualTotal: Double
    public let recurringPercentage: Double
    public let nonRecurringPercentage: Double
    public let topRecurringCategories: [CategorySpendSummary]
    public let topNonRecurringCategories: [CategorySpendSummary]
    
    public init(
        recurringAnnualTotal: Double,
        recurringMonthlyBaseline: Double,
        nonRecurringAnnualTotal: Double,
        recurringPercentage: Double,
        nonRecurringPercentage: Double,
        topRecurringCategories: [CategorySpendSummary],
        topNonRecurringCategories: [CategorySpendSummary]
    ) {
        self.recurringAnnualTotal = recurringAnnualTotal
        self.recurringMonthlyBaseline = recurringMonthlyBaseline
        self.nonRecurringAnnualTotal = nonRecurringAnnualTotal
        self.recurringPercentage = recurringPercentage
        self.nonRecurringPercentage = nonRecurringPercentage
        self.topRecurringCategories = topRecurringCategories
        self.topNonRecurringCategories = topNonRecurringCategories
    }
}

/// Comprehensive Total Cost of Ownership (TCO) summary per household asset.
public struct AssetTCOSummary: Identifiable, Sendable {
    public let id: UUID
    public let assetName: String
    public let category: AssetCategory
    public let iconName: String
    public let accentColorHex: String
    public let purchasePrice: Double
    public let eventsCost: Double
    public let serviceItemsCost: Double
    public let measurementsCost: Double
    public let lifetimeTCO: Double
    public let trailing12MonthsCost: Double
    
    public init(
        id: UUID,
        assetName: String,
        category: AssetCategory,
        iconName: String,
        accentColorHex: String,
        purchasePrice: Double,
        eventsCost: Double,
        serviceItemsCost: Double,
        measurementsCost: Double,
        lifetimeTCO: Double,
        trailing12MonthsCost: Double
    ) {
        self.id = id
        self.assetName = assetName
        self.category = category
        self.iconName = iconName
        self.accentColorHex = accentColorHex
        self.purchasePrice = purchasePrice
        self.eventsCost = eventsCost
        self.serviceItemsCost = serviceItemsCost
        self.measurementsCost = measurementsCost
        self.lifetimeTCO = lifetimeTCO
        self.trailing12MonthsCost = trailing12MonthsCost
    }
}

/// Individual normalized subscription line item with free trial and contract retention status.
public struct SubscriptionItem: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let providerName: String?
    public let billingCycle: String
    public let originalAmount: Double
    public let currencyCode: String
    public let monthlyNormalizedRON: Double
    public let annualCommitmentRON: Double
    public let paymentCardLast4: String?
    public let contractEndDate: Date?
    public let isFreeTrial: Bool
    public let isTrialConvertingSoon: Bool
    public let isRetentionWindowActive: Bool
    public let daysUntilContractEnd: Int?
    
    public init(
        id: UUID = UUID(),
        name: String,
        providerName: String? = nil,
        billingCycle: String = "Lunar",
        originalAmount: Double,
        currencyCode: String = "RON",
        monthlyNormalizedRON: Double,
        annualCommitmentRON: Double,
        paymentCardLast4: String? = nil,
        contractEndDate: Date? = nil,
        isFreeTrial: Bool = false,
        isTrialConvertingSoon: Bool = false,
        isRetentionWindowActive: Bool = false,
        daysUntilContractEnd: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.providerName = providerName
        self.billingCycle = billingCycle
        self.originalAmount = originalAmount
        self.currencyCode = currencyCode
        self.monthlyNormalizedRON = monthlyNormalizedRON
        self.annualCommitmentRON = annualCommitmentRON
        self.paymentCardLast4 = paymentCardLast4
        self.contractEndDate = contractEndDate
        self.isFreeTrial = isFreeTrial
        self.isTrialConvertingSoon = isTrialConvertingSoon
        self.isRetentionWindowActive = isRetentionWindowActive
        self.daysUntilContractEnd = daysUntilContractEnd
    }
}

/// Normalized subscription burn rate metrics and alert monitors.
public struct SubscriptionBurnRate: Sendable {
    public let totalMonthlyBurnRate: Double
    public let totalAnnualCommitment: Double
    public let activeSubscriptionsCount: Int
    public let freeTrialsCount: Int
    public let trialConversionsSoonCount: Int
    public let retentionOpportunitiesCount: Int
    public let items: [SubscriptionItem]
    
    public init(
        totalMonthlyBurnRate: Double,
        totalAnnualCommitment: Double,
        activeSubscriptionsCount: Int,
        freeTrialsCount: Int,
        trialConversionsSoonCount: Int = 0,
        retentionOpportunitiesCount: Int = 0,
        items: [SubscriptionItem]
    ) {
        self.totalMonthlyBurnRate = totalMonthlyBurnRate
        self.totalAnnualCommitment = totalAnnualCommitment
        self.activeSubscriptionsCount = activeSubscriptionsCount
        self.freeTrialsCount = freeTrialsCount
        self.trialConversionsSoonCount = trialConversionsSoonCount
        self.retentionOpportunitiesCount = retentionOpportunitiesCount
        self.items = items
    }
}

/// Monthly telemetry utility curve for seasonal consumption modeling.
public struct MonthlyUtilityCurve: Identifiable, Sendable {
    public let id: String                    // "2026-05"
    public let year: Int
    public let month: Int
    public let monthLabel: String            // "Mai 2026"
    public let shortMonthLabel: String       // "Mai"
    public let electricityKWh: Double
    public let gasM3: Double
    public let waterM3: Double
    public let estimatedCostRON: Double
    
    public init(
        id: String,
        year: Int,
        month: Int,
        monthLabel: String,
        shortMonthLabel: String,
        electricityKWh: Double,
        gasM3: Double,
        waterM3: Double,
        estimatedCostRON: Double
    ) {
        self.id = id
        self.year = year
        self.month = month
        self.monthLabel = monthLabel
        self.shortMonthLabel = shortMonthLabel
        self.electricityKWh = electricityKWh
        self.gasM3 = gasM3
        self.waterM3 = waterM3
        self.estimatedCostRON = estimatedCostRON
    }
}

/// Master financial intelligence summary aggregating all 5 analytical dimensions.
public struct HouseholdFinancialPulse: @unchecked Sendable {
    public let cashFlow: CashFlowForecast
    public let spendBreakdown: SpendBreakdown
    public let rankedTCO: [AssetTCOSummary]
    public let subscriptionPulse: SubscriptionBurnRate
    public let utilityCurves: [MonthlyUtilityCurve]
    public let referenceDate: Date
    
    public init(
        cashFlow: CashFlowForecast,
        spendBreakdown: SpendBreakdown,
        rankedTCO: [AssetTCOSummary],
        subscriptionPulse: SubscriptionBurnRate,
        utilityCurves: [MonthlyUtilityCurve],
        referenceDate: Date = Date()
    ) {
        self.cashFlow = cashFlow
        self.spendBreakdown = spendBreakdown
        self.rankedTCO = rankedTCO
        self.subscriptionPulse = subscriptionPulse
        self.utilityCurves = utilityCurves
        self.referenceDate = referenceDate
    }
}

// MARK: - Financial Pulse Calculator Engine

/// High-precision financial intelligence engine providing cash-flow projections,
/// recurring vs non-recurring spend modeling, asset TCO, subscription burn rate,
/// and seasonal utility consumption curves across all 8 household domains.
public final class FinancialPulseCalculator: Sendable {
    
    // MARK: - Public Master Calculation Method
    
    /// Computes the complete household financial pulse across all 5 dimensions.
    public static func calculatePulse(
        assets: [Asset],
        events: [LifecycleEvent]? = nil,
        serviceItems: [ServiceItem]? = nil,
        measurements: [MeasurementLog]? = nil,
        referenceDate: Date = Date()
    ) -> HouseholdFinancialPulse {
        let calendar = Calendar.current
        let startOfRefDate = calendar.startOfDay(for: referenceDate)
        
        // Resolve unified arrays
        let resolvedEvents = resolveEvents(assets: assets, events: events)
        let resolvedServiceItems = resolveServiceItems(assets: assets, serviceItems: serviceItems)
        let resolvedMeasurements = resolveMeasurements(assets: assets, measurements: measurements)
        
        // 1. Cash Flow Forecast (30 / 60 / 90 days)
        let cashFlow = computeCashFlowForecast(
            events: resolvedEvents,
            serviceItems: resolvedServiceItems,
            measurements: resolvedMeasurements,
            referenceDate: referenceDate,
            startOfRefDate: startOfRefDate,
            calendar: calendar
        )
        
        // 2. Spend Breakdown (Recurring vs Non-Recurring)
        let spendBreakdown = computeSpendBreakdown(
            assets: assets,
            events: resolvedEvents,
            serviceItems: resolvedServiceItems,
            referenceDate: referenceDate,
            startOfRefDate: startOfRefDate,
            calendar: calendar
        )
        
        // 3. Asset Total Cost of Ownership (TCO)
        let rankedTCO = computeAssetTCO(
            assets: assets,
            events: resolvedEvents,
            serviceItems: resolvedServiceItems,
            measurements: resolvedMeasurements,
            referenceDate: referenceDate,
            startOfRefDate: startOfRefDate,
            calendar: calendar
        )
        
        // 4. Subscription Normalized Burn Rate
        let subscriptionPulse = computeSubscriptionBurnRate(
            assets: assets,
            events: resolvedEvents,
            referenceDate: referenceDate,
            startOfRefDate: startOfRefDate,
            calendar: calendar
        )
        
        // 5. Seasonal Utility Consumption Curves
        let utilityCurves = computeSeasonalUtilityCurves(
            measurements: resolvedMeasurements,
            referenceDate: referenceDate,
            calendar: calendar
        )
        
        return HouseholdFinancialPulse(
            cashFlow: cashFlow,
            spendBreakdown: spendBreakdown,
            rankedTCO: rankedTCO,
            subscriptionPulse: subscriptionPulse,
            utilityCurves: utilityCurves,
            referenceDate: referenceDate
        )
    }
    
    // MARK: - 1. Cash Flow Forecast Calculation
    
    public static func computeCashFlowForecast(
        events: [LifecycleEvent],
        serviceItems: [ServiceItem],
        measurements: [MeasurementLog],
        referenceDate: Date,
        startOfRefDate: Date,
        calendar: Calendar = .current
    ) -> CashFlowForecast {
        guard let d30Ahead = calendar.date(byAdding: .day, value: 30, to: startOfRefDate),
              let d60Ahead = calendar.date(byAdding: .day, value: 60, to: startOfRefDate),
              let d90Ahead = calendar.date(byAdding: .day, value: 90, to: startOfRefDate),
              let d30Prior = calendar.date(byAdding: .day, value: -30, to: startOfRefDate),
              let d60Prior = calendar.date(byAdding: .day, value: -60, to: startOfRefDate),
              let d90Prior = calendar.date(byAdding: .day, value: -90, to: startOfRefDate) else {
            return CashFlowForecast(
                days30Committed: 0, days60Committed: 0, days90Committed: 0,
                prior30DaysActual: 0, prior60DaysActual: 0, prior90DaysActual: 0
            )
        }
        
        var days30Committed: Double = 0
        var days60Committed: Double = 0
        var days90Committed: Double = 0
        var upcoming30: [LifecycleEvent] = []
        var upcoming60: [LifecycleEvent] = []
        var upcoming90: [LifecycleEvent] = []
        
        // Upcoming uncompleted events
        for event in events {
            guard !event.isCompleted, let cost = event.cost, cost > 0 else { continue }
            let due = event.dueDate
            if due >= startOfRefDate && due <= d90Ahead {
                if due <= d30Ahead {
                    days30Committed += cost
                    upcoming30.append(event)
                }
                if due <= d60Ahead {
                    days60Committed += cost
                    upcoming60.append(event)
                }
                days90Committed += cost
                upcoming90.append(event)
            }
        }
        
        upcoming30.sort { $0.dueDate < $1.dueDate }
        upcoming60.sort { $0.dueDate < $1.dueDate }
        upcoming90.sort { $0.dueDate < $1.dueDate }
        
        // Historical actual spend in prior 30 / 60 / 90 days
        var prior30Actual: Double = 0
        var prior60Actual: Double = 0
        var prior90Actual: Double = 0
        
        // 1. Completed events
        for event in events {
            guard event.isCompleted || event.completedDate != nil,
                  let cost = event.cost, cost > 0 else { continue }
            let date = event.completedDate ?? event.dueDate
            if date >= d90Prior && date <= referenceDate {
                if date >= d30Prior { prior30Actual += cost }
                if date >= d60Prior { prior60Actual += cost }
                prior90Actual += cost
            }
        }
        
        // 2. Service items actual interventions
        for item in serviceItems {
            let cost = item.totalEffectiveCost
            guard cost > 0 else { continue }
            let date = item.serviceDate
            if date >= d90Prior && date <= referenceDate {
                if date >= d30Prior { prior30Actual += cost }
                if date >= d60Prior { prior60Actual += cost }
                prior90Actual += cost
            }
        }
        
        // 3. Measurement logs utility spend
        for measurement in measurements {
            guard let cost = measurement.estimatedCost, cost > 0 else { continue }
            let date = measurement.recordedAt
            if date >= d90Prior && date <= referenceDate {
                if date >= d30Prior { prior30Actual += cost }
                if date >= d60Prior { prior60Actual += cost }
                prior90Actual += cost
            }
        }
        
        return CashFlowForecast(
            days30Committed: days30Committed,
            days60Committed: days60Committed,
            days90Committed: days90Committed,
            prior30DaysActual: prior30Actual,
            prior60DaysActual: prior60Actual,
            prior90DaysActual: prior90Actual,
            upcomingEventsNext30Days: upcoming30,
            upcomingEventsNext60Days: upcoming60,
            upcomingEventsNext90Days: upcoming90
        )
    }
    
    // MARK: - 2. Recurring vs Non-Recurring Spend Split
    
    public static func computeSpendBreakdown(
        assets: [Asset],
        events: [LifecycleEvent],
        serviceItems: [ServiceItem],
        referenceDate: Date,
        startOfRefDate: Date,
        calendar: Calendar = .current
    ) -> SpendBreakdown {
        let t12mStart = calendar.date(byAdding: .day, value: -365, to: startOfRefDate) ?? startOfRefDate
        
        var recurringAnnualTotal: Double = 0
        var nonRecurringAnnualTotal: Double = 0
        var recurringCategoryTotals: [AssetCategory: Double] = [:]
        var nonRecurringCategoryTotals: [AssetCategory: Double] = [:]
        
        // Track handled asset IDs for direct subscription properties
        var accountedAssetSubscriptionIds: Set<UUID> = []
        
        // A. Process events
        for event in events {
            guard let cost = event.cost, cost > 0 else { continue }
            let category = event.asset?.category ?? .custom
            let isRecurring = isRecurringEvent(event)
            
            if isRecurring {
                let annualizedCost = annualizeEventCost(event, cost: cost)
                recurringAnnualTotal += annualizedCost
                recurringCategoryTotals[category, default: 0] += annualizedCost
                if let assetId = event.asset?.id {
                    accountedAssetSubscriptionIds.insert(assetId)
                }
            } else {
                // Non-recurring event: consider if in trailing 12 months
                let eventDate = event.completedDate ?? event.dueDate
                if eventDate >= t12mStart && eventDate <= referenceDate {
                    nonRecurringAnnualTotal += cost
                    nonRecurringCategoryTotals[category, default: 0] += cost
                }
            }
        }
        
        // B. Process subscription assets not covered by explicit events
        for asset in assets {
            if asset.category == .subscriptions || (asset.recurringAmount != nil && asset.recurringAmount! > 0) {
                if !accountedAssetSubscriptionIds.contains(asset.id), let recAmount = asset.recurringAmount, recAmount > 0 {
                    let monthlyRate = normalizeToMonthlyRate(amount: recAmount, cycle: asset.billingCycle)
                    let annualized = monthlyRate * 12.0
                    recurringAnnualTotal += annualized
                    recurringCategoryTotals[asset.category, default: 0] += annualized
                }
            }
        }
        
        // C. Process discrete service items (non-recurring) in trailing 12 months
        for item in serviceItems {
            let cost = item.totalEffectiveCost
            guard cost > 0 else { continue }
            if item.serviceDate >= t12mStart && item.serviceDate <= referenceDate {
                let category = item.asset?.category ?? .custom
                nonRecurringAnnualTotal += cost
                nonRecurringCategoryTotals[category, default: 0] += cost
            }
        }
        
        // D. Calculate percentages and sorted summaries
        let recurringMonthlyBaseline = recurringAnnualTotal / 12.0
        let totalSpendCombined = recurringAnnualTotal + nonRecurringAnnualTotal
        
        let recPct = totalSpendCombined > 0 ? (recurringAnnualTotal / totalSpendCombined) * 100.0 : 0.0
        let nonRecPct = totalSpendCombined > 0 ? (nonRecurringAnnualTotal / totalSpendCombined) * 100.0 : 0.0
        
        let topRecurring = recurringCategoryTotals.map { cat, amt in
            CategorySpendSummary(
                category: cat,
                amount: amt,
                percentage: recurringAnnualTotal > 0 ? (amt / recurringAnnualTotal) * 100.0 : 0.0
            )
        }.sorted { $0.amount > $1.amount }
        
        let topNonRecurring = nonRecurringCategoryTotals.map { cat, amt in
            CategorySpendSummary(
                category: cat,
                amount: amt,
                percentage: nonRecurringAnnualTotal > 0 ? (amt / nonRecurringAnnualTotal) * 100.0 : 0.0
            )
        }.sorted { $0.amount > $1.amount }
        
        return SpendBreakdown(
            recurringAnnualTotal: recurringAnnualTotal,
            recurringMonthlyBaseline: recurringMonthlyBaseline,
            nonRecurringAnnualTotal: nonRecurringAnnualTotal,
            recurringPercentage: recPct,
            nonRecurringPercentage: nonRecPct,
            topRecurringCategories: topRecurring,
            topNonRecurringCategories: topNonRecurring
        )
    }
    
    // MARK: - 3. Asset Total Cost of Ownership (TCO)
    
    public static func computeAssetTCO(
        assets: [Asset],
        events: [LifecycleEvent],
        serviceItems: [ServiceItem],
        measurements: [MeasurementLog],
        referenceDate: Date,
        startOfRefDate: Date,
        calendar: Calendar = .current
    ) -> [AssetTCOSummary] {
        let t12mStart = calendar.date(byAdding: .day, value: -365, to: startOfRefDate) ?? startOfRefDate
        
        // Group items by asset id
        var eventsByAsset: [UUID: [LifecycleEvent]] = [:]
        for ev in events {
            if let aId = ev.asset?.id {
                eventsByAsset[aId, default: []].append(ev)
            }
        }
        
        var serviceByAsset: [UUID: [ServiceItem]] = [:]
        for si in serviceItems {
            if let aId = si.asset?.id {
                serviceByAsset[aId, default: []].append(si)
            }
        }
        
        var measurementsByAsset: [UUID: [MeasurementLog]] = [:]
        for m in measurements {
            if let aId = m.asset?.id {
                measurementsByAsset[aId, default: []].append(m)
            }
        }
        
        var summaries: [AssetTCOSummary] = []
        
        for asset in assets {
            let purchase = asset.purchasePrice ?? 0.0
            let assetEvents = eventsByAsset[asset.id] ?? asset.events
            let assetServices = serviceByAsset[asset.id] ?? asset.serviceItems
            let assetMeasurements = measurementsByAsset[asset.id] ?? asset.measurements
            
            let evCost = assetEvents.compactMap { $0.cost }.reduce(0, +)
            let srvCost = assetServices.map { $0.totalEffectiveCost }.reduce(0, +)
            let measCost = assetMeasurements.compactMap { $0.estimatedCost }.reduce(0, +)
            let lifetimeTCO = purchase + evCost + srvCost + measCost
            
            // Trailing 12 months
            var t12m: Double = 0
            if let purchaseDate = asset.purchaseOrIssueDate, purchaseDate >= t12mStart && purchaseDate <= referenceDate {
                t12m += purchase
            }
            
            for ev in assetEvents {
                guard let cost = ev.cost, cost > 0 else { continue }
                let date = ev.completedDate ?? ev.dueDate
                if date >= t12mStart && date <= referenceDate {
                    t12m += cost
                }
            }
            
            for si in assetServices {
                let cost = si.totalEffectiveCost
                guard cost > 0 else { continue }
                if si.serviceDate >= t12mStart && si.serviceDate <= referenceDate {
                    t12m += cost
                }
            }
            
            for m in assetMeasurements {
                guard let cost = m.estimatedCost, cost > 0 else { continue }
                if m.recordedAt >= t12mStart && m.recordedAt <= referenceDate {
                    t12m += cost
                }
            }
            
            summaries.append(AssetTCOSummary(
                id: asset.id,
                assetName: asset.name,
                category: asset.category,
                iconName: asset.iconName,
                accentColorHex: asset.accentColorHex,
                purchasePrice: purchase,
                eventsCost: evCost,
                serviceItemsCost: srvCost,
                measurementsCost: measCost,
                lifetimeTCO: lifetimeTCO,
                trailing12MonthsCost: t12m
            ))
        }
        
        return summaries.sorted { $0.lifetimeTCO > $1.lifetimeTCO }
    }
    
    // MARK: - 4. Subscription Normalized Burn Rate
    
    public static func computeSubscriptionBurnRate(
        assets: [Asset],
        events: [LifecycleEvent],
        referenceDate: Date,
        startOfRefDate: Date,
        calendar: Calendar = .current
    ) -> SubscriptionBurnRate {
        var items: [SubscriptionItem] = []
        var processedAssetIds = Set<UUID>()
        
        // A. Assets marked as subscriptions or having recurringAmount
        for asset in assets {
            if asset.category == .subscriptions || (asset.recurringAmount != nil && asset.recurringAmount! > 0) {
                processedAssetIds.insert(asset.id)
                let originalAmount = asset.recurringAmount ?? 0.0
                let cycle = asset.billingCycle ?? "Lunar"
                let monthlyRON = normalizeToMonthlyRate(amount: originalAmount, cycle: cycle)
                let annualRON = monthlyRON * 12.0
                
                let isTrial = isFreeTrialSubscription(asset: asset, event: nil, originalAmount: originalAmount)
                
                var daysUntilEnd: Int? = nil
                var isConvertingSoon = false
                var isRetentionActive = false
                
                if let contractEnd = asset.contractEndDate {
                    let days = calendar.dateComponents([.day], from: startOfRefDate, to: calendar.startOfDay(for: contractEnd)).day ?? 0
                    daysUntilEnd = days
                    if isTrial && days >= 0 && days <= 7 {
                        isConvertingSoon = true
                    }
                    if !isTrial && days <= 60 && days >= -30 {
                        isRetentionActive = true
                    }
                } else if isTrial {
                    // Check if there is an upcoming lifecycle event for this asset
                    if let nextEvent = asset.events.filter({ !$0.isCompleted }).sorted(by: { $0.dueDate < $1.dueDate }).first {
                        let days = calendar.dateComponents([.day], from: startOfRefDate, to: calendar.startOfDay(for: nextEvent.dueDate)).day ?? 0
                        daysUntilEnd = days
                        if days >= 0 && days <= 7 {
                            isConvertingSoon = true
                        }
                    }
                }
                
                items.append(SubscriptionItem(
                    id: asset.id,
                    name: asset.name,
                    providerName: asset.providerName,
                    billingCycle: cycle,
                    originalAmount: originalAmount,
                    currencyCode: asset.currencyCode,
                    monthlyNormalizedRON: monthlyRON,
                    annualCommitmentRON: annualRON,
                    paymentCardLast4: asset.paymentCardLast4,
                    contractEndDate: asset.contractEndDate,
                    isFreeTrial: isTrial,
                    isTrialConvertingSoon: isConvertingSoon,
                    isRetentionWindowActive: isRetentionActive,
                    daysUntilContractEnd: daysUntilEnd
                ))
            }
        }
        
        // B. Standalone subscription events without a dedicated subscription asset
        for event in events {
            if let asset = event.asset, processedAssetIds.contains(asset.id) {
                continue
            }
            if event.coverageType == "Abonament" || event.title.localizedCaseInsensitiveContains("abonament") {
                let originalAmount = event.cost ?? 0.0
                let cycle: String
                if let cadence = event.cadenceDays {
                    if cadence <= 7 { cycle = "Săptămânal" }
                    else if cadence <= 35 { cycle = "Lunar" }
                    else if cadence <= 95 { cycle = "Trimestrial" }
                    else { cycle = "Anual" }
                } else {
                    cycle = "Lunar"
                }
                
                let monthlyRON = normalizeToMonthlyRate(amount: originalAmount, cycle: cycle)
                let annualRON = monthlyRON * 12.0
                let isTrial = isFreeTrialSubscription(asset: nil, event: event, originalAmount: originalAmount)
                
                let days = calendar.dateComponents([.day], from: startOfRefDate, to: calendar.startOfDay(for: event.dueDate)).day ?? 0
                let isConvertingSoon = isTrial && days >= 0 && days <= 7
                let isRetentionActive = !isTrial && days <= 60 && days >= -30
                
                items.append(SubscriptionItem(
                    id: event.id,
                    name: event.title,
                    providerName: event.provider,
                    billingCycle: cycle,
                    originalAmount: originalAmount,
                    currencyCode: event.currency,
                    monthlyNormalizedRON: monthlyRON,
                    annualCommitmentRON: annualRON,
                    paymentCardLast4: nil,
                    contractEndDate: event.dueDate,
                    isFreeTrial: isTrial,
                    isTrialConvertingSoon: isConvertingSoon,
                    isRetentionWindowActive: isRetentionActive,
                    daysUntilContractEnd: days
                ))
            }
        }
        
        let totalMonthly = items.reduce(0.0) { $0 + $1.monthlyNormalizedRON }
        let totalAnnual = totalMonthly * 12.0
        let activeCount = items.count
        let freeTrialsCount = items.filter { $0.isFreeTrial }.count
        let trialConvertingCount = items.filter { $0.isTrialConvertingSoon }.count
        let retentionCount = items.filter { $0.isRetentionWindowActive }.count
        
        return SubscriptionBurnRate(
            totalMonthlyBurnRate: totalMonthly,
            totalAnnualCommitment: totalAnnual,
            activeSubscriptionsCount: activeCount,
            freeTrialsCount: freeTrialsCount,
            trialConversionsSoonCount: trialConvertingCount,
            retentionOpportunitiesCount: retentionCount,
            items: items.sorted { $0.monthlyNormalizedRON > $1.monthlyNormalizedRON }
        )
    }
    
    // MARK: - 5. Seasonal Utility Consumption Curves
    
    public static func computeSeasonalUtilityCurves(
        measurements: [MeasurementLog],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> [MonthlyUtilityCurve] {
        let romanianMonths = ["Ianuarie", "Februarie", "Martie", "Aprilie", "Mai", "Iunie", "Iulie", "August", "Septembrie", "Octombrie", "Noiembrie", "Decembrie"]
        let romanianShortMonths = ["Ian", "Feb", "Mar", "Apr", "Mai", "Iun", "Iul", "Aug", "Sep", "Oct", "Noi", "Dec"]
        
        var curves: [MonthlyUtilityCurve] = []
        
        for monthOffset in (0..<12).reversed() {
            guard let targetDate = calendar.date(byAdding: .month, value: -monthOffset, to: referenceDate) else {
                continue
            }
            let year = calendar.component(.year, from: targetDate)
            let month = calendar.component(.month, from: targetDate)
            let monthId = String(format: "%04d-%02d", year, month)
            let shortName = romanianShortMonths[max(0, min(11, month - 1))]
            let longName = romanianMonths[max(0, min(11, month - 1))]
            let fullLabel = "\(longName) \(year)"
            
            var electricity: Double = 0
            var gas: Double = 0
            var water: Double = 0
            var costTotal: Double = 0
            
            for m in measurements {
                let mYear = calendar.component(.year, from: m.recordedAt)
                let mMonth = calendar.component(.month, from: m.recordedAt)
                guard mYear == year && mMonth == month else { continue }
                
                let delta = m.deltaFromPrevious ?? (m.value > 0 ? m.value : 0.0)
                let cost = m.estimatedCost ?? (delta * (m.unitPrice ?? 0.0))
                
                switch m.domain {
                case .electricityMeter:
                    electricity += delta
                case .gasMeter:
                    gas += delta
                case .coldWaterMeter, .hotWaterMeter:
                    water += delta
                default:
                    break
                }
                costTotal += cost
            }
            
            curves.append(MonthlyUtilityCurve(
                id: monthId,
                year: year,
                month: month,
                monthLabel: fullLabel,
                shortMonthLabel: shortName,
                electricityKWh: electricity,
                gasM3: gas,
                waterM3: water,
                estimatedCostRON: costTotal
            ))
        }
        
        return curves
    }
    
    // MARK: - Normalization Helpers
    
    /// Normalizes any billing cycle frequency string into a monthly amount in RON.
    public static func normalizeToMonthlyRate(amount: Double, cycle: String?) -> Double {
        guard let cycle = cycle?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !cycle.isEmpty else {
            return amount
        }
        
        if cycle.contains("săptăm") || cycle.contains("saptam") || cycle.contains("week") {
            return (amount * 52.0) / 12.0
        } else if cycle.contains("trimestr") || cycle.contains("quarter") || cycle.contains("3 luni") {
            return amount / 3.0
        } else if cycle.contains("semestr") || cycle.contains("semi") || cycle.contains("6 luni") {
            return amount / 6.0
        } else if cycle.contains("anual") || cycle.contains("year") || cycle.contains("12 luni") || cycle == "an" || cycle == "1 an" {
            return amount / 12.0
        } else {
            // Default to monthly
            return amount
        }
    }
    
    /// Determines whether an asset or event represents a free trial subscription.
    public static func isFreeTrialSubscription(asset: Asset?, event: LifecycleEvent?, originalAmount: Double) -> Bool {
        if originalAmount <= 0.001 { return true }
        let assetNotes = asset?.notes?.lowercased() ?? ""
        let assetName = asset?.name.lowercased() ?? ""
        let eventTitle = event?.title.lowercased() ?? ""
        let eventDesc = event?.eventDescription?.lowercased() ?? ""
        let combined = "\(assetNotes) \(assetName) \(eventTitle) \(eventDesc)"
        let tokens = Set(combined.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        
        let wordKeywords = ["trial", "gratuit", "gratuita", "gratuită", "free", "probă", "proba"]
        for kw in wordKeywords {
            if tokens.contains(kw) {
                return true
            }
        }
        
        let phraseKeywords = ["zile gratuite", "0 ron", "fără cost", "fara cost", "perioadă de probă", "perioada de proba"]
        for phrase in phraseKeywords {
            if combined.contains(phrase) {
                return true
            }
        }
        return false
    }
    
    /// Evaluates if a lifecycle event represents recurring fixed overhead.
    private static func isRecurringEvent(_ event: LifecycleEvent) -> Bool {
        if event.cadenceDays != nil { return true }
        if event.isAutoRenew { return true }
        if event.asset?.category == .subscriptions { return true }
        
        let lower = event.title.lowercased()
        let recurringKeywords = ["abonament", "factura", "factură", "impozit", "rca", "casco", "pad", "chirie", "itp", "iscir", "vig", "rig", "rovinietă", "rovinieta", "mentenanță", "mentenanta"]
        return recurringKeywords.some { lower.contains($0) }
    }
    
    /// Computes the annualized recurring cost for an event.
    private static func annualizeEventCost(_ event: LifecycleEvent, cost: Double) -> Double {
        if let cadence = event.cadenceDays, cadence > 0 {
            return (cost * 365.0) / Double(cadence)
        }
        if event.isAutoRenew {
            return cost * 1.0
        }
        if let asset = event.asset, asset.category == .subscriptions {
            let monthly = normalizeToMonthlyRate(amount: cost, cycle: asset.billingCycle)
            return monthly * 12.0
        }
        return cost
    }
    
    // MARK: - Array Resolution Helpers
    
    private static func resolveEvents(assets: [Asset], events: [LifecycleEvent]?) -> [LifecycleEvent] {
        if let events = events { return events }
        return assets.flatMap { $0.events }
    }
    
    private static func resolveServiceItems(assets: [Asset], serviceItems: [ServiceItem]?) -> [ServiceItem] {
        if let serviceItems = serviceItems { return serviceItems }
        return assets.flatMap { $0.serviceItems }
    }
    
    private static func resolveMeasurements(assets: [Asset], measurements: [MeasurementLog]?) -> [MeasurementLog] {
        if let measurements = measurements { return measurements }
        return assets.flatMap { $0.measurements }
    }
}

// MARK: - Array Helper
private extension Array {
    func some(_ predicate: (Element) -> Bool) -> Bool {
        contains(where: predicate)
    }
}
