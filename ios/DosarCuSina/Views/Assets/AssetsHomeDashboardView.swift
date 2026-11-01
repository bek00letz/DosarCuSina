import SwiftUI
import SwiftData

/// The primary landing screen of Dosar cu Șină:
/// Presents an Apple-grade modular dashboard grid of category squares (8 defaults + user custom categories),
/// dynamically ordered and filtered according to user preferences in Settings.
public struct AssetsHomeDashboardView: View {
    @Query(sort: \Asset.createdAt, order: .reverse) private var assets: [Asset]
    @Query(sort: \LifecycleEvent.dueDate, order: .forward) private var allEvents: [LifecycleEvent]
    @Environment(\.modelContext) private var modelContext
    
    @State private var displayManager = CategoryDisplayManager.shared
    @State private var showingNewAssetSheet = false
    @State private var showingCustomizationSheet = false
    @State private var showingAllSearch = false
    @State private var searchText = ""
    
    public init() {}
    
    private var urgentEventsCount: Int {
        allEvents.filter { !$0.isCompleted && ($0.isOverdue || $0.isUrgent) }.count
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Urgent Radar Summary Bar (if any deadlines need attention)
                    if urgentEventsCount > 0 {
                        radarAlertBanner
                    }
                    
                    // The Modular Category Squares Grid
                    categorySquaresGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Active")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AssetsVaultView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showingCustomizationSheet = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        
                        Button {
                            showingNewAssetSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCustomizationSheet) {
                NavigationStack {
                    CategoryCustomizationView()
                }
            }
            .sheet(isPresented: $showingNewAssetSheet) {
                NewAssetSheet()
            }
        }
    }
    
    // MARK: - Radar Alert Banner
    private var radarAlertBanner: some View {
        NavigationLink {
            RadarDashboardView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(urgentEventsCount) \(urgentEventsCount == 1 ? "obligație urgentă" : "obligații urgente")")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Apasă pentru a deschide calendarul Radar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Category Squares Grid
    private var categorySquaresGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(displayManager.enabledItems) { item in
                NavigationLink {
                    CategoryAssetsListView(categoryItem: item)
                } label: {
                    categoryTile(for: item)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        displayManager.toggleItem(item)
                    } label: {
                        Label("Ascunde din ecranul principal", systemImage: "eye.slash")
                    }
                }
            }
        }
    }
    
    // MARK: - Individual Category Square Tile
    private func categoryTile(for item: CategoryDisplayItem) -> some View {
        let matchingCount = assetsCount(for: item)
        let urgentCount = categoryUrgentEventsCount(for: item)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Top Row: Icon + Count Pill
            HStack(alignment: .top) {
                Image(systemName: item.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(item.tintColor)
                    .frame(width: 48, height: 48)
                    .background(item.tintColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                Spacer()
                
                Text("\(matchingCount)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(matchingCount > 0 ? Color.primary : Color.secondary.opacity(0.6))
                    .frame(minWidth: 26, minHeight: 26)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            Spacer(minLength: 16)
            
            // Bottom Info: Title + Status Snippet
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if urgentCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("\(urgentCount) scadențe")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                } else if matchingCount > 0 {
                    Text(matchingCount == 1 ? "1 activ" : "\(matchingCount) active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Niciun activ")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(urgentCount > 0 ? Color.red.opacity(0.25) : Color.primary.opacity(0.04), lineWidth: urgentCount > 0 ? 1.5 : 0.5)
        )
    }
    
    private func assetsCount(for item: CategoryDisplayItem) -> Int {
        if let cat = item.matchingAssetCategory {
            return assets.filter { $0.category == cat }.count
        } else if item.isCustom {
            return assets.filter {
                $0.category == .custom && ($0.notes?.contains(item.id) == true || $0.subtitle?.contains(item.title) == true || $0.name.contains(item.title))
            }.count
        }
        return 0
    }
    
    private func categoryUrgentEventsCount(for item: CategoryDisplayItem) -> Int {
        let categoryAssets: [Asset]
        if let cat = item.matchingAssetCategory {
            categoryAssets = assets.filter { $0.category == cat }
        } else {
            categoryAssets = assets.filter { $0.category == .custom }
        }
        
        return categoryAssets.reduce(0) { $0 + $1.urgentEventsCount }
    }
}
