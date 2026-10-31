import SwiftUI
import SwiftData

public struct AssetsVaultView: View {
    @Query(sort: \Asset.createdAt, order: .reverse) private var assets: [Asset]
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingNewAssetSheet = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                if assets.isEmpty {
                    emptyVaultState
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(assets) { asset in
                            NavigationLink {
                                AssetDetailView(asset: asset)
                            } label: {
                                assetCard(asset)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Active")
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
            .sheet(isPresented: $showingNewAssetSheet) {
                NewAssetSheet()
            }
        }
    }
    
    private func assetCard(_ asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Asset Icon Badge
                Image(systemName: asset.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(asset.accentColor)
                    .frame(width: 44, height: 44)
                    .background(asset.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if let sub = asset.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(asset.category.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Urgent badge or count pill
                if asset.urgentEventsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text("\(asset.urgentEventsCount) urgente")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    Text("\(asset.pendingEventsCount) active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            
            Divider()
                .opacity(0.5)
            
            // Next event & metric telemetry row
            HStack {
                if let next = asset.nextUpcomingEvent {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Următoarea scadență:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(next.title) • \(next.dueDate.formatted(.dateTime.day().month()))")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("Nicio scadență programată")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let metric = asset.currentMetricValue, let unit = asset.metricUnit {
                    Text("\(Int(metric)) \(unit)")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
    }
    
    private var emptyVaultState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.indigo.gradient)
                .padding(.top, 40)
            
            Text("Seiful de Active este gol")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            
            Text("Creează un spațiu pentru casa ta, mașină, animalul de companie sau un modul personalizat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                showingNewAssetSheet = true
            } label: {
                Text("Adaugă Activ")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}
