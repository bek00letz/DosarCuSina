import SwiftUI
import SwiftData
import Charts
#if canImport(UIKit)
import UIKit
#endif

/// Comprehensive household financial intelligence dashboard.
/// Adheres strictly to the Apple Craftsmanship & Polish Standard:
/// - Concentric geometry with continuous squircle corners.
/// - Tactile haptics and fluid spring animations.
/// - Swift Charts for cash-flow forecasting and seasonal consumption curves.
/// - 5 analytical dimensions: Cash Flow, Spend Split, Asset TCO, Subscriptions, Utilities.
public struct FinancialPulseView: View {
    @Query private var assets: [Asset]
    @Query private var events: [LifecycleEvent]
    @Query private var serviceItems: [ServiceItem]
    @Query private var measurements: [MeasurementLog]
    
    // Interactive State
    @State private var selectedHorizon: CashFlowHorizon = .days30
    @State private var selectedTCOSort: TCOSortMode = .lifetime
    @State private var selectedUtilityDomain: UtilityChartDomain = .electricity
    @State private var expandedAssetId: UUID? = nil
    
    public init() {}
    
    // MARK: - Enums
    
    public enum CashFlowHorizon: String, CaseIterable, Identifiable {
        case days30 = "30 Zile"
        case days60 = "60 Zile"
        case days90 = "90 Zile"
        
        public var id: String { rawValue }
        public var days: Int {
            switch self {
            case .days30: return 30
            case .days60: return 60
            case .days90: return 90
            }
        }
    }
    
    public enum TCOSortMode: String, CaseIterable, Identifiable {
        case lifetime = "Total Activ"
        case trailing12M = "Ultimele 12 Luni"
        
        public var id: String { rawValue }
    }
    
    public enum UtilityChartDomain: String, CaseIterable, Identifiable {
        case electricity = "Curent (kWh)"
        case gas = "Gaz (m³)"
        case water = "Apă (m³)"
        case cost = "Cost (RON)"
        
        public var id: String { rawValue }
        public var unit: String {
            switch self {
            case .electricity: return "kWh"
            case .gas, .water: return "m³"
            case .cost: return "RON"
            }
        }
        
        public var tintColor: Color {
            switch self {
            case .electricity: return .yellow
            case .gas: return .cyan
            case .water: return .blue
            case .cost: return .green
            }
        }
    }
    
    // MARK: - Semantic Background Colors
    
    private var groupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color.gray.opacity(0.08)
        #endif
    }
    
    private var cardBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }
    
    private var tertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        return Color.gray.opacity(0.18)
        #endif
    }
    
    // MARK: - Computed Pulse
    
    private var pulse: HouseholdFinancialPulse {
        FinancialPulseCalculator.calculatePulse(
            assets: assets,
            events: events,
            serviceItems: serviceItems,
            measurements: measurements
        )
    }
    
    // MARK: - Body
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // 1. Top KPI Summary Cards
                    topKPICardsSection
                    
                    // 2. 30 / 60 / 90-Day Cash Flow Forecast
                    cashFlowForecastSection
                    
                    // 3. Proportional Spend Split (Recurring vs Non-recurring)
                    spendSplitSection
                    
                    // 4. Asset Total Cost of Ownership (TCO)
                    assetTCOSection
                    
                    // 5. Subscription Burn Rate Monitor
                    subscriptionBurnRateSection
                    
                    // 6. Seasonal Utility Consumption Curves
                    seasonalUtilityCurvesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(groupedBackground.ignoresSafeArea())
            .navigationTitle("Finanțe & TCO")
        }
    }
    
    // MARK: - 1. Top KPI Summary Cards
    
    private var topKPICardsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Monthly Burn Rate KPI
                let monthlyRate = pulse.subscriptionPulse.totalMonthlyBurnRate + pulse.spendBreakdown.recurringMonthlyBaseline
                kpiCard(
                    title: "Rată Lunară Fixă",
                    value: String(format: "%.0f RON", monthlyRate),
                    subtitle: "Overhead recurent",
                    systemImage: "flame.fill",
                    tint: .orange
                )
                
                // Committed Cash Flow KPI
                let committedAmount: Double = {
                    switch selectedHorizon {
                    case .days30: return pulse.cashFlow.days30Committed
                    case .days60: return pulse.cashFlow.days60Committed
                    case .days90: return pulse.cashFlow.days90Committed
                    }
                }()
                
                kpiCard(
                    title: "Comis (\(selectedHorizon.rawValue))",
                    value: String(format: "%.0f RON", committedAmount),
                    subtitle: "Obligații scadente",
                    systemImage: "calendar.badge.clock",
                    tint: .blue
                )
            }
            
            // 12-Month Total Spend KPI
            let annualTotal = pulse.spendBreakdown.recurringAnnualTotal + pulse.spendBreakdown.nonRecurringAnnualTotal
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Cheltuieli Gospodărie (12 Luni)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(String(format: "%.0f", annualTotal)) RON")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "banknote.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.02), radius: 6, x: 0, y: 2)
            )
        }
    }
    
    private func kpiCard(title: String, value: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(tint)
            }
            
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Text(subtitle)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.02), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - 2. 30 / 60 / 90-Day Cash Flow Forecast Section
    
    private var cashFlowForecastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prognoză Flux Financiar")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Comparație scadențe viitoare vs cheltuieli istorice")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            
            // Horizon Picker
            Picker("Orizont Timp", selection: $selectedHorizon) {
                ForEach(CashFlowHorizon.allCases) { horizon in
                    Text(horizon.rawValue).tag(horizon)
                }
            }
            .pickerStyle(.segmented)
            
            // Forecast comparison values for current horizon
            let currentCommitted: Double = {
                switch selectedHorizon {
                case .days30: return pulse.cashFlow.days30Committed
                case .days60: return pulse.cashFlow.days60Committed
                case .days90: return pulse.cashFlow.days90Committed
                }
            }()
            
            let currentActual: Double = {
                switch selectedHorizon {
                case .days30: return pulse.cashFlow.prior30DaysActual
                case .days60: return pulse.cashFlow.prior60DaysActual
                case .days90: return pulse.cashFlow.prior90DaysActual
                }
            }()
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Obligații Scadente")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f", currentCommitted)) RON")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.blue)
                }
                
                Divider().frame(height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cheltuieli Istorice")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f", currentActual)) RON")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Difference Badge
                let diff = currentCommitted - currentActual
                Text(diff >= 0 ? "+\(String(format: "%.0f", diff)) RON" : "\(String(format: "%.0f", diff)) RON")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(diff > 0 ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                    )
                    .foregroundStyle(diff > 0 ? Color.orange : Color.green)
            }
            .padding(.vertical, 4)
            
            // Swift Charts Comparison Across 30, 60, and 90 Days
            let chartData: [CashFlowChartPoint] = [
                CashFlowChartPoint(horizon: "30z", type: "Istoric", amount: pulse.cashFlow.prior30DaysActual),
                CashFlowChartPoint(horizon: "30z", type: "Comis", amount: pulse.cashFlow.days30Committed),
                CashFlowChartPoint(horizon: "60z", type: "Istoric", amount: pulse.cashFlow.prior60DaysActual),
                CashFlowChartPoint(horizon: "60z", type: "Comis", amount: pulse.cashFlow.days60Committed),
                CashFlowChartPoint(horizon: "90z", type: "Istoric", amount: pulse.cashFlow.prior90DaysActual),
                CashFlowChartPoint(horizon: "90z", type: "Comis", amount: pulse.cashFlow.days90Committed)
            ]
            
            Chart(chartData) { item in
                BarMark(
                    x: .value("Orizont", item.horizon),
                    y: .value("Sumă", item.amount)
                )
                .foregroundStyle(by: .value("Tip", item.type))
                .position(by: .value("Tip", item.type))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale([
                "Istoric": Color.gray.opacity(0.5),
                "Comis": Color.blue
            ])
            .frame(height: 160)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    private struct CashFlowChartPoint: Identifiable {
        let id = UUID()
        let horizon: String
        let type: String
        let amount: Double
    }
    
    // MARK: - 3. Proportional Spend Split Section
    
    private var spendSplitSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Structură Cheltuieli Gospodărie")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Cheltuieli Recurente vs. Intervenții Punctuale")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.pie.fill")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
            }
            
            let recPct = pulse.spendBreakdown.recurringPercentage
            let nonRecPct = pulse.spendBreakdown.nonRecurringPercentage
            
            // Visual Progress Split Bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.indigo.gradient)
                        .frame(width: max(4, geo.size.width * CGFloat(recPct / 100.0)))
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.orange.gradient)
                        .frame(width: max(4, geo.size.width * CGFloat(nonRecPct / 100.0)))
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            
            // Legend & Totals
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.indigo).frame(width: 8, height: 8)
                        Text("Recurent: \(String(format: "%.1f", recPct))%")
                            .font(.caption.bold())
                    }
                    Text("\(String(format: "%.0f", pulse.spendBreakdown.recurringAnnualTotal)) RON/an")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("(\(String(format: "%.0f", pulse.spendBreakdown.recurringMonthlyBaseline)) RON/lună)")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Non-recurent: \(String(format: "%.1f", nonRecPct))%")
                            .font(.caption.bold())
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                    }
                    Text("\(String(format: "%.0f", pulse.spendBreakdown.nonRecurringAnnualTotal)) RON/an")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("(reparații, consulturi, piese)")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Top Recurring Categories Chips
            if !pulse.spendBreakdown.topRecurringCategories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top Categorii Recurente:")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pulse.spendBreakdown.topRecurringCategories.prefix(4)) { cat in
                                HStack(spacing: 4) {
                                    Image(systemName: cat.category.systemIcon)
                                        .font(.system(size: 10))
                                    Text("\(cat.category.title): \(String(format: "%.0f", cat.amount)) RON")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(cat.category.defaultColor.opacity(0.12))
                                )
                                .foregroundStyle(cat.category.defaultColor)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - 4. Asset Total Cost of Ownership (TCO) Section
    
    private var assetTCOSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cost Total de Deținere (TCO)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Clasament active după costul total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                Picker("Sortare", selection: $selectedTCOSort) {
                    ForEach(TCOSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            }
            
            let sortedAssets: [AssetTCOSummary] = {
                switch selectedTCOSort {
                case .lifetime:
                    return pulse.rankedTCO.sorted { $0.lifetimeTCO > $1.lifetimeTCO }
                case .trailing12M:
                    return pulse.rankedTCO.sorted { $0.trailing12MonthsCost > $1.trailing12MonthsCost }
                }
            }()
            
            if sortedAssets.isEmpty {
                Text("Adaugă un activ pentru a urmări TCO.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(sortedAssets.prefix(5).enumerated()), id: \.element.id) { index, asset in
                        tcoAssetRow(asset: asset, rank: index + 1)
                        if index < min(sortedAssets.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    private func tcoAssetRow(asset: AssetTCOSummary, rank: Int) -> some View {
        let isExpanded = expandedAssetId == asset.id
        let displayAmount = selectedTCOSort == .lifetime ? asset.lifetimeTCO : asset.trailing12MonthsCost
        
        return VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expandedAssetId = isExpanded ? nil : asset.id
                }
            } label: {
                HStack(spacing: 12) {
                    // Rank badge
                    Text("#\(rank)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .leading)
                    
                    // Icon
                    Image(systemName: asset.iconName)
                        .foregroundStyle(asset.category.defaultColor)
                        .font(.subheadline)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(asset.category.defaultColor.opacity(0.12))
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.assetName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(asset.category.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(String(format: "%.0f", displayAmount)) RON")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text(selectedTCOSort == .lifetime ? "pe viață" : "12 luni")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Expandable Breakdown
            if isExpanded {
                VStack(spacing: 6) {
                    HStack {
                        tcoBreakdownPill(label: "Achiziție", amount: asset.purchasePrice, tint: .gray)
                        tcoBreakdownPill(label: "Obligații/Asig.", amount: asset.eventsCost, tint: .blue)
                    }
                    HStack {
                        tcoBreakdownPill(label: "Revizii/Service", amount: asset.serviceItemsCost, tint: .orange)
                        tcoBreakdownPill(label: "Utilități/Consum", amount: asset.measurementsCost, tint: .teal)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tertiaryBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
    
    private func tcoBreakdownPill(label: String, amount: Double, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(String(format: "%.0f", amount)) RON")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(amount > 0 ? tint : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 5. Subscription Burn Rate Monitor Section
    
    private var subscriptionBurnRateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitor Abonamente & Contracte")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Normalizare lunară și avertismente retenție / trial")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "creditcard.and.123")
                    .font(.subheadline)
                    .foregroundStyle(.indigo)
            }
            
            // Summary Banner
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Burn Rate Lunar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f", pulse.subscriptionPulse.totalMonthlyBurnRate)) RON/lună")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Angajament Anual")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f", pulse.subscriptionPulse.totalAnnualCommitment)) RON/an")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.indigo.opacity(0.08))
            )
            
            // Alert Badges (Free trials converting soon & retention opportunities)
            let trialCount = pulse.subscriptionPulse.trialConversionsSoonCount
            let retentionCount = pulse.subscriptionPulse.retentionOpportunitiesCount
            
            if trialCount > 0 || retentionCount > 0 {
                VStack(spacing: 6) {
                    if trialCount > 0 {
                        let alertText = "\(trialCount) Trial Gratuit expiră în curând (≤ 7 zile)"
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(alertText)
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    }
                    
                    if retentionCount > 0 {
                        let retentionText = "\(retentionCount) Contract(e) în fereastră de renegociere retenție"
                        HStack(spacing: 6) {
                            Image(systemName: "phone.badge.checkmark")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(retentionText)
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                    }
                }
            }
            
            // Subscription Items List
            if pulse.subscriptionPulse.items.isEmpty {
                Text("Nu există abonamente active înregistrate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(pulse.subscriptionPulse.items.prefix(6)) { item in
                        subscriptionItemRow(item: item)
                        if item.id != pulse.subscriptionPulse.items.prefix(6).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    private func subscriptionItemRow(item: SubscriptionItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    if item.isFreeTrial {
                        Text("TRIAL")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.pink.opacity(0.15)))
                            .foregroundStyle(.pink)
                    }
                    
                    if item.isRetentionWindowActive {
                        Text("RENEGOCIERE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }
                
                HStack(spacing: 4) {
                    if let prov = item.providerName {
                        Text(prov)
                    }
                    Text("•")
                    Text(item.billingCycle)
                    if let last4 = item.paymentCardLast4 {
                        Text("•")
                        Text("•••• \(last4)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(String(format: "%.0f", item.monthlyNormalizedRON)) RON/l")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("\(String(format: "%.0f", item.annualCommitmentRON)) RON/an")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
    
    // MARK: - 6. Seasonal Utility Consumption Curves Section
    
    private var seasonalUtilityCurvesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Curbe Sezoniere de Consum")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Evoluție lunară pe ultimele 12 luni")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "bolt.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }
            
            // Utility Domain Picker
            Picker("Domeniu Utilități", selection: $selectedUtilityDomain) {
                ForEach(UtilityChartDomain.allCases) { domain in
                    Text(domain.rawValue).tag(domain)
                }
            }
            .pickerStyle(.segmented)
            
            let curves = pulse.utilityCurves
            let totalDomainConsumption = calculateTotalConsumption(for: curves)
            let avg = totalDomainConsumption / 12.0
            
            HStack {
                Text("Total 12 Luni:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.1f", totalDomainConsumption)) \(selectedUtilityDomain.unit)")
                    .font(.caption.bold())
                    .foregroundStyle(selectedUtilityDomain.tintColor)
                Spacer()
                Text("Medie: \(String(format: "%.1f", avg)) \(selectedUtilityDomain.unit)/lună")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            // Swift Charts Line & Area visualization
            Chart(curves) { curve in
                let val = valueForCurve(curve)
                
                AreaMark(
                    x: .value("Lună", curve.shortMonthLabel),
                    y: .value("Consum", val)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [selectedUtilityDomain.tintColor.opacity(0.35), selectedUtilityDomain.tintColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Lună", curve.shortMonthLabel),
                    y: .value("Consum", val)
                )
                .foregroundStyle(selectedUtilityDomain.tintColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.catmullRom)
                
                PointMark(
                    x: .value("Lună", curve.shortMonthLabel),
                    y: .value("Consum", val)
                )
                .foregroundStyle(selectedUtilityDomain.tintColor)
                .symbolSize(18)
            }
            .frame(height: 180)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    private func valueForCurve(_ curve: MonthlyUtilityCurve) -> Double {
        switch selectedUtilityDomain {
        case .electricity: return curve.electricityKWh
        case .gas: return curve.gasM3
        case .water: return curve.waterM3
        case .cost: return curve.estimatedCostRON
        }
    }
    
    private func calculateTotalConsumption(for curves: [MonthlyUtilityCurve]) -> Double {
        switch selectedUtilityDomain {
        case .electricity: return curves.reduce(0.0) { $0 + $1.electricityKWh }
        case .gas: return curves.reduce(0.0) { $0 + $1.gasM3 }
        case .water: return curves.reduce(0.0) { $0 + $1.waterM3 }
        case .cost: return curves.reduce(0.0) { $0 + $1.estimatedCostRON }
        }
    }
}
