import SwiftUI
import SwiftData

/// Focused list of assets for a selected category with search, direct addition, and full deletion capabilities.
public struct CategoryAssetsListView: View {
    public let categoryItem: CategoryDisplayItem
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.createdAt, order: .reverse) private var allAssets: [Asset]
    
    @State private var searchText = ""
    @State private var showingNewAssetSheet = false
    @State private var assetToDelete: Asset? = nil
    @State private var showingDeleteAlert = false
    
    public init(categoryItem: CategoryDisplayItem) {
        self.categoryItem = categoryItem
    }
    
    private var matchingAssets: [Asset] {
        let categoryAssets: [Asset]
        if let cat = categoryItem.matchingAssetCategory {
            categoryAssets = allAssets.filter { $0.category == cat }
        } else if categoryItem.isCustom {
            // Match custom categories or custom domain tags
            categoryAssets = allAssets.filter {
                $0.category == .custom && ($0.notes?.contains(categoryItem.id) == true || $0.subtitle?.contains(categoryItem.title) == true || $0.name.contains(categoryItem.title))
            }
        } else {
            categoryAssets = []
        }
        
        let query = RomanianUtilityParser.stripDiacritics(searchText.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
        if query.isEmpty {
            return categoryAssets
        }
        
        return categoryAssets.filter { asset in
            let name = RomanianUtilityParser.stripDiacritics(asset.name).lowercased()
            let sub = RomanianUtilityParser.stripDiacritics(asset.subtitle ?? "").lowercased()
            let plate = (asset.licensePlate ?? "").lowercased()
            let vin = (asset.vin ?? "").lowercased()
            return name.contains(query) || sub.contains(query) || plate.contains(query) || vin.contains(query)
        }
    }
    
    public var body: some View {
        List {
            if matchingAssets.isEmpty {
                emptySection
            } else {
                ForEach(matchingAssets) { asset in
                    NavigationLink {
                        AssetDetailView(asset: asset)
                    } label: {
                        assetRow(asset)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            assetToDelete = asset
                            showingDeleteAlert = true
                        } label: {
                            Label("Șterge", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        NavigationLink {
                            AssetDetailView(asset: asset)
                        } label: {
                            Label("Deschide Dosar", systemImage: "folder.fill")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            assetToDelete = asset
                            showingDeleteAlert = true
                        } label: {
                            Label("Șterge Activul", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(categoryItem.title)
        .searchable(text: $searchText, prompt: "Caută în \(categoryItem.title)...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewAssetSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .confirmationDialog(
            "Ștergi acest activ?",
            isPresented: $showingDeleteAlert,
            titleVisibility: .visible,
            presenting: assetToDelete
        ) { asset in
            Button("Șterge definitiv „\(asset.name)”", role: .destructive) {
                deleteAsset(asset)
            }
            Button("Anulează", role: .cancel) {
                assetToDelete = nil
            }
        } message: { asset in
            Text("Toate obligațiile, intervențiile tehnice și fișierele asociate dosarului „\(asset.name)” vor fi eliminate.")
        }
        .sheet(isPresented: $showingNewAssetSheet) {
            NewAssetSheet(initialCategory: categoryItem.matchingAssetCategory ?? .vehicle)
        }
    }
    
    // MARK: - Asset Row
    private func assetRow(_ asset: Asset) -> some View {
        HStack(spacing: 12) {
            Image(systemName: asset.iconName)
                .font(.system(size: 20))
                .foregroundStyle(categoryItem.tintColor)
                .frame(width: 40, height: 40)
                .background(categoryItem.tintColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                
                if let sub = asset.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if asset.urgentEventsCount > 0 {
                Text("\(asset.urgentEventsCount) scadențe")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .clipShape(Capsule())
            } else if let next = asset.nextUpcomingEvent {
                Text(next.dueDate.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Empty Section
    private var emptySection: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: categoryItem.iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(categoryItem.tintColor.opacity(0.8))
                    .padding(.top, 24)
                
                Text("Niciun activ în \(categoryItem.title)")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                
                Text("Apasă pe butonul de mai jos pentru a adăuga primul dosar în această categorie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Button {
                    showingNewAssetSheet = true
                } label: {
                    Label("Adaugă Activ", systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(categoryItem.tintColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func deleteAsset(_ asset: Asset) {
        withAnimation {
            modelContext.delete(asset)
            try? modelContext.save()
            WidgetDataSyncService.shared.sync(context: modelContext)
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        assetToDelete = nil
    }
}
