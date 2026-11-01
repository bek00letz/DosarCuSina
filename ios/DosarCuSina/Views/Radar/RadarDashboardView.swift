import SwiftUI
import SwiftData

public enum RadarHorizon: Int, CaseIterable, Identifiable {
    case focus = 0
    case all = 1
    case completed = 2
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .focus: return "Focalizare (14z)"
        case .all: return "Toate"
        case .completed: return "Rezolvate"
        }
    }
}

public struct RadarDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifecycleEvent.dueDate, order: .forward) private var allEvents: [LifecycleEvent]
    @Query private var assets: [Asset]
    
    @State private var selectedHorizon: RadarHorizon = .focus
    @State private var selectedCategory: AssetCategory? = nil
    @State private var showingMultiSourceInput = false
    @State private var showingNewAssetSheet = false
    @State private var editingEvent: LifecycleEvent? = nil
    
    // Undo Snackbar State
    @State private var lastCompletedEvent: LifecycleEvent? = nil
    @State private var showUndoToast: Bool = false
    @State private var undoDismissTask: Task<Void, Never>? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Health Card
                        healthSummaryCard
                        
                        // Horizon Picker (Focalizare / Toate / Rezolvate)
                        horizonPicker
                        
                        // Category Filter Pills
                        categoryFilterRow
                        
                        // Dynamic Content by Horizon
                        switch selectedHorizon {
                        case .focus:
                            focusContent
                        case .all:
                            allContent
                        case .completed:
                            completedContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 80) // Leave breathing room for undo toast
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                
                // Floating Undo Toast
                if showUndoToast, let event = lastCompletedEvent {
                    undoToastView(for: event)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Radar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingMultiSourceInput = true
                    } label: {
                        Image(systemName: "doc.viewfinder.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Scanează document sau factură")
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingNewAssetSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Adaugă activ nou")
                }
            }
            .sheet(isPresented: $showingMultiSourceInput) {
                MultiSourceInputView()
            }
            .sheet(isPresented: $showingNewAssetSheet) {
                NewAssetSheet()
            }
            .sheet(item: $editingEvent) { event in
                EditEventSheet(event: event)
            }
        }
    }
    
    // MARK: - Horizon Picker
    private var horizonPicker: some View {
        Picker("Orizont Radar", selection: $selectedHorizon) {
            ForEach(RadarHorizon.allCases) { horizon in
                Text(horizon.title).tag(horizon)
            }
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Filtered Events
    private var filteredEvents: [LifecycleEvent] {
        allEvents.filter { event in
            guard let cat = selectedCategory else { return true }
            return event.asset?.category == cat
        }
    }
    
    private var activeEvents: [LifecycleEvent] {
        filteredEvents.filter { !$0.isCompleted }
    }
    
    private var completedEvents: [LifecycleEvent] {
        filteredEvents.filter { $0.isCompleted }
    }
    
    private var urgentEvents: [LifecycleEvent] {
        activeEvents.filter { $0.isOverdue || $0.isUrgent }
    }
    
    private var next14DaysEvents: [LifecycleEvent] {
        activeEvents.filter { !$0.isUrgent && !$0.isOverdue && $0.daysRemaining <= 14 }
    }
    
    private var upcoming30DaysEvents: [LifecycleEvent] {
        activeEvents.filter { !$0.isUrgent && !$0.isOverdue && $0.daysRemaining <= 30 }
    }
    
    private var laterEvents: [LifecycleEvent] {
        activeEvents.filter { $0.daysRemaining > 30 }
    }
    
    // MARK: - Horizon Views
    @ViewBuilder
    private var focusContent: some View {
        if urgentEvents.isEmpty && next14DaysEvents.isEmpty {
            focusEmptyStateView
        } else {
            if !urgentEvents.isEmpty {
                eventSection(title: "Urgente & Depășite", icon: "exclamationmark.triangle.fill", color: .red, events: urgentEvents)
            }
            
            if !next14DaysEvents.isEmpty {
                eventSection(title: "În următoarele 14 zile", icon: "clock.badge.exclamationmark", color: .orange, events: next14DaysEvents)
            }
        }
    }
    
    @ViewBuilder
    private var allContent: some View {
        if urgentEvents.isEmpty && upcoming30DaysEvents.isEmpty && laterEvents.isEmpty {
            emptyStateView
        } else {
            if !urgentEvents.isEmpty {
                eventSection(title: "Urgente & Depășite", icon: "exclamationmark.triangle.fill", color: .red, events: urgentEvents)
            }
            
            if !upcoming30DaysEvents.isEmpty {
                eventSection(title: "În următoarele 30 de zile", icon: "clock.badge.exclamationmark", color: .orange, events: upcoming30DaysEvents)
            }
            
            if !laterEvents.isEmpty {
                eventSection(title: "Planificate Ulterior", icon: "calendar", color: .blue, events: laterEvents)
            }
        }
    }
    
    @ViewBuilder
    private var completedContent: some View {
        if completedEvents.isEmpty {
            completedEmptyStateView
        } else {
            eventSection(title: "Obligații Rezolvate", icon: "checkmark.seal.fill", color: .green, events: completedEvents, isHistory: true)
        }
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
        let active = activeEvents
        guard !active.isEmpty else { return 1.0 }
        let compliant = active.filter { !$0.isOverdue }.count
        return Double(compliant) / Double(active.count)
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
            return "Nicio grijă urgentă pentru următoarele 14 zile."
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
    private func eventSection(title: String, icon: String, color: Color, events: [LifecycleEvent], isHistory: Bool = false) -> some View {
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
                    Button {
                        editingEvent = event
                    } label: {
                        EventRowCard(event: event) {
                            handleToggleCompletion(for: event)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Toggle & Undo Handling
    private func handleToggleCompletion(for event: LifecycleEvent) {
        WidgetDataSyncService.shared.sync(context: modelContext)
        
        if event.isCompleted {
            lastCompletedEvent = event
            undoDismissTask?.cancel()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showUndoToast = true
            }
            
            undoDismissTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showUndoToast = false
                    }
                }
            }
        } else {
            if lastCompletedEvent?.id == event.id {
                undoDismissTask?.cancel()
                withAnimation(.easeInOut(duration: 0.25)) {
                    showUndoToast = false
                }
            }
        }
    }
    
    private func undoLastCompletion() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        
        undoDismissTask?.cancel()
        guard let event = lastCompletedEvent else { return }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            event.isCompleted = false
            event.completedDate = nil
            showUndoToast = false
            lastCompletedEvent = nil
        }
        
        Task {
            _ = try? await NotificationScheduler.shared.scheduleReminders(for: event)
        }
        WidgetDataSyncService.shared.sync(context: modelContext)
    }
    
    // MARK: - Undo Toast View
    private func undoToastView(for event: LifecycleEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text("Marcat ca rezolvat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 8)
            
            Button {
                undoLastCompletion()
            } label: {
                Text("Anulează")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            Button {
                undoDismissTask?.cancel()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showUndoToast = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    // MARK: - Empty States
    private var focusEmptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow.gradient)
                .padding(.top, 30)
            
            Text("Focalizare curată")
                .font(.system(.title3, design: .rounded, weight: .bold))
            
            Text("Nicio obligație urgentă în următoarele 14 zile.\nPoți comuta pe «Toate» pentru planificările pe termen mai lung.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    private var completedEmptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .padding(.top, 30)
            
            Text("Nicio obligație rezolvată")
                .font(.system(.title3, design: .rounded, weight: .bold))
            
            Text("Facturile plătite, ITP-urile sau vaccinurile bifate vor rămâne arhivate aici pentru referință și istoric.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
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
