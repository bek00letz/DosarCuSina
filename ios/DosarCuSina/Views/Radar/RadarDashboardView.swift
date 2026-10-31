import SwiftUI
import SwiftData

public struct RadarDashboardView: View {
    @Query(sort: \LifecycleEvent.dueDate, order: .forward) private var allEvents: [LifecycleEvent]
    @Query private var assets: [Asset]
    
    @State private var selectedCategory: AssetCategory? = nil
    @State private var showingScanner = false
    @State private var showingNewAssetSheet = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Health Card
                    healthSummaryCard
                    
                    // Category Filter Pills
                    categoryFilterRow
                    
                    // Main Feed
                    if urgentEvents.isEmpty && upcomingEvents.isEmpty && laterEvents.isEmpty {
                        emptyStateView
                    } else {
                        if !urgentEvents.isEmpty {
                            eventSection(title: "Urgente & Depășite", icon: "exclamationmark.triangle.fill", color: .red, events: urgentEvents)
                        }
                        
                        if !upcomingEvents.isEmpty {
                            eventSection(title: "În următoarele 30 de zile", icon: "clock.badge.exclamationmark", color: .orange, events: upcomingEvents)
                        }
                        
                        if !laterEvents.isEmpty {
                            eventSection(title: "Planificate Ulterior", icon: "calendar", color: .blue, events: laterEvents)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Radar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "doc.viewfinder.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingNewAssetSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView()
            }
            .sheet(isPresented: $showingNewAssetSheet) {
                NewAssetSheet()
            }
        }
    }
    
    // MARK: - Filtered Events
    private var filteredEvents: [LifecycleEvent] {
        allEvents.filter { event in
            guard let cat = selectedCategory else { return true }
            return event.asset?.category == cat
        }
    }
    
    private var urgentEvents: [LifecycleEvent] {
        filteredEvents.filter { !$0.isCompleted && ($0.isOverdue || $0.isUrgent) }
    }
    
    private var upcomingEvents: [LifecycleEvent] {
        filteredEvents.filter { !$0.isCompleted && !$0.isUrgent && !$0.isOverdue && $0.daysRemaining <= 30 }
    }
    
    private var laterEvents: [LifecycleEvent] {
        filteredEvents.filter { !$0.isCompleted && $0.daysRemaining > 30 }
    }
    
    // MARK: - Health Card
    private var healthSummaryCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    .frame(width: 58, height: 58)
                
                Circle()
                    .trim(from: 0.0, to: complianceRate)
                    .stroke(complianceColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(complianceRate * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(complianceTitle)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(complianceSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
    }
    
    private var complianceRate: Double {
        let total = filteredEvents.count
        guard total > 0 else { return 1.0 }
        let compliant = filteredEvents.filter { !$0.isOverdue }.count
        return Double(compliant) / Double(total)
    }
    
    private var complianceColor: Color {
        if urgentEvents.isEmpty { return .green }
        if urgentEvents.contains(where: { $0.isOverdue }) { return .red }
        return .orange
    }
    
    private var complianceTitle: String {
        if urgentEvents.isEmpty {
            return "Totul este la zi"
        } else if let firstOverdue = urgentEvents.first(where: { $0.isOverdue }) {
            return "\(firstOverdue.title) depășit!"
        } else {
            return "\(urgentEvents.count) scadențe apropiate"
        }
    }
    
    private var complianceSubtitle: String {
        if urgentEvents.isEmpty {
            return "Nicio grijă urgentă pentru următoarele 7 zile."
        } else {
            return "Verifică acțiunile recomandate de mai jos."
        }
    }
    
    // MARK: - Category Filters
    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(title: "Toate", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                
                ForEach(AssetCategory.allCases) { cat in
                    filterPill(title: cat.title, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.primary : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Event Section
    private func eventSection(title: String, icon: String, color: Color, events: [LifecycleEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(events.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(events) { event in
                    EventRowCard(event: event)
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)
                .padding(.top, 40)
            
            Text("Nicio obligație activă")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            
            Text("Apasă pe '+' pentru a adăuga un activ (casă, mașină, pet) sau scanează o factură.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                showingNewAssetSheet = true
            } label: {
                Text("Adaugă primul activ")
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
