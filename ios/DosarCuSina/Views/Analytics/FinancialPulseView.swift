import SwiftUI
import SwiftData
import Charts

public struct FinancialPulseView: View {
    @Query private var events: [LifecycleEvent]
    @Query private var assets: [Asset]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 30-Day Cash Flow Forecast Card
                    cashFlowForecastCard
                    
                    // Cost by Category (Swift Charts)
                    costByCategoryCard
                    
                    // Top Expense Assets
                    topExpenseAssetsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Finanțe & TCO")
        }
    }
    
    // MARK: - Cash Flow Forecast Card
    private var cashFlowForecastCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scadențe în Următoarele 30 de Zile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(String(format: "%.0f", projectedCostNext30Days)) RON")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
            }
            
            Text("Estimare bazată pe evenimentele active (RCA, revizii, facturi) programate în luna curentă.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    private var projectedCostNext30Days: Double {
        events
            .filter { !$0.isCompleted && $0.daysRemaining >= 0 && $0.daysRemaining <= 30 }
            .compactMap { $0.cost }
            .reduce(0, +)
    }
    
    // MARK: - Cost By Category Card
    private var costByCategoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cheltuieli pe Categorii (Anul Curent)")
                .font(.system(.headline, design: .rounded, weight: .bold))
            
            let data = categoryCostData
            if data.isEmpty {
                Text("Nu există cheltuieli înregistrate pentru anul curent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Categorie", item.category.title),
                        y: .value("Sumă", item.amount)
                    )
                    .foregroundStyle(item.category.defaultColor.gradient)
                    .cornerRadius(6)
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    private struct CategoryCostItem: Identifiable {
        let id = UUID()
        let category: AssetCategory
        let amount: Double
    }
    
    private var categoryCostData: [CategoryCostItem] {
        var grouped: [AssetCategory: Double] = [:]
        for ev in events {
            guard let cost = ev.cost, cost > 0, let cat = ev.asset?.category else { continue }
            grouped[cat, default: 0] += cost
        }
        return grouped.map { CategoryCostItem(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }
    
    // MARK: - Top Expense Assets
    private var topExpenseAssetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cost Total de Deținere (Per Activ)")
                .font(.system(.headline, design: .rounded, weight: .bold))
            
            let sortedAssets = assets.sorted { $0.totalCostThisYear > $1.totalCostThisYear }
            if sortedAssets.isEmpty {
                Text("Adaugă un activ pentru a urmări costurile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedAssets.prefix(5)) { asset in
                        HStack {
                            Image(systemName: asset.iconName)
                                .foregroundStyle(asset.accentColor)
                                .font(.subheadline)
                            Text(asset.name)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                            Spacer()
                            Text("\(String(format: "%.0f", asset.totalCostThisYear)) RON")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        if asset.id != sortedAssets.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
}
