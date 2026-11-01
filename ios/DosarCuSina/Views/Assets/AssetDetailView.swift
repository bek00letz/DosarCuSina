import SwiftUI
import SwiftData
import EventKit

/// 4 domain-adapted navigation tabs for `AssetDetailView`.
public enum AssetDetailTab: String, CaseIterable, Identifiable {
    case obligations = "Obligații"
    case history = "Jurnal"
    case specifications = "Specificații"
    case documents = "Documente"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .obligations: return "Obligații & Scadențe"
        case .history: return "Jurnal & Istoric"
        case .specifications: return "Specificații & Contacte"
        case .documents: return "Dosar Documente"
        }
    }
    
    public var iconName: String {
        switch self {
        case .obligations: return "calendar.badge.clock"
        case .history: return "clock.arrow.circlepath"
        case .specifications: return "info.circle.fill"
        case .documents: return "doc.on.doc.fill"
        }
    }
}

/// Comprehensive, 4-tab detail view for an asset across all 8 household domains.
/// Conforms to the Apple Craftsmanship & Polish Standard with continuous squircle cards,
/// 1-tap Calendar/Reminders export, dual historical ledgers, and structured document vault.
public struct AssetDetailView: View {
    @Bindable public var asset: Asset
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: AssetDetailTab = .obligations
    @State private var historySubTab: Int = 0 // 0 = Intervenții, 1 = Contoare
    
    // Sheets State
    @State private var showingEditAssetSheet: Bool = false
    @State private var showingMultiSourceInput: Bool = false
    @State private var showingAddEventSheet: Bool = false
    @State private var showingAddServiceItemSheet: Bool = false
    @State private var editingEvent: LifecycleEvent? = nil
    @State private var previewAttachment: DocumentAttachment? = nil
    @State private var showCompletedEvents: Bool = false
    
    // PDF Dossier Export State
    @State private var exportedPDFURL: URL? = nil
    @State private var isGeneratingPDF: Bool = false
    @State private var showingShareSheet: Bool = false
    
    // Toast Status Feedback
    @State private var toastMessage: String? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Hero Card
                headerHeroCard
                
                // 4-Tab Segmented Navigation Bar
                tabSelectorBar
                
                // Active Tab Content
                switch selectedTab {
                case .obligations:
                    tab1ObligationsView
                case .history:
                    tab2HistoryView
                case .specifications:
                    tab3SpecificationsView
                case .documents:
                    tab4DocumentsView
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Export Dossier Button
                    Button {
                        generateAndShareDossier()
                    } label: {
                        if isGeneratingPDF {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .disabled(isGeneratingPDF)
                    
                    // Edit Asset Button
                    Button {
                        showingEditAssetSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    // Multi-Source Intake Button
                    Button {
                        showingMultiSourceInput = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                toastView(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showingEditAssetSheet) {
            EditAssetSheet(asset: asset)
        }
        .sheet(isPresented: $showingMultiSourceInput) {
            MultiSourceInputView(preselectedAsset: asset)
        }
        .sheet(isPresented: $showingAddEventSheet) {
            AddObligationSheet(asset: asset)
        }
        .sheet(isPresented: $showingAddServiceItemSheet) {
            AddServiceItemSheet(asset: asset)
        }
        .sheet(item: $editingEvent) { event in
            EditEventSheet(event: event)
        }
        .sheet(item: $previewAttachment) { att in
            AttachmentPreviewSheet(attachment: att)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedPDFURL {
                #if canImport(UIKit)
                ActivityView(activityItems: [url])
                #endif
            }
        }
    }
    
    // MARK: - Header Hero Card
    private var headerHeroCard: some View {
        HStack(spacing: 16) {
            Image(systemName: asset.iconName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(asset.accentColor)
                .frame(width: 58, height: 58)
                .background(asset.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                
                if let sub = asset.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    Text(asset.category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(asset.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(asset.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                    
                    if asset.totalCostThisYear > 0 {
                        Text("\(Int(asset.totalCostThisYear)) RON în \(Calendar.current.component(.year, from: Date()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - 4-Tab Selector Bar
    private var tabSelectorBar: some View {
        HStack(spacing: 4) {
            ForEach(AssetDetailTab.allCases) { tab in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14, weight: selectedTab == tab ? .bold : .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: selectedTab == tab ? .bold : .medium, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? Color(uiColor: .secondarySystemGroupedBackground)
                            : Color.clear
                    )
                    .foregroundStyle(selectedTab == tab ? Color.blue : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: selectedTab == tab ? .black.opacity(0.04) : .clear, radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
    
    // MARK: - TAB 1: Obligații & Scadențe
    private var tab1ObligationsView: some View {
        VStack(spacing: 14) {
            // Section Header & Controls
            HStack {
                Text("Obligații & Termene")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                
                Spacer()
                
                Button {
                    showingAddEventSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Adaugă")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            
            // Active vs Completed Segment Picker
            Picker("Filtru", selection: $showCompletedEvents) {
                Text("Active (\(activeEvents.count))").tag(false)
                Text("Istoric (\(completedEvents.count))").tag(true)
            }
            .pickerStyle(.segmented)
            
            // Events List
            let events = showCompletedEvents ? completedEvents : activeEvents
            if events.isEmpty {
                emptyObligationsCard
            } else {
                VStack(spacing: 10) {
                    ForEach(events) { event in
                        obligationCard(event)
                    }
                }
            }
        }
    }
    
    private func obligationCard(_ event: LifecycleEvent) -> some View {
        VStack(spacing: 8) {
            Button {
                editingEvent = event
            } label: {
                EventRowCard(event: event)
            }
            .buttonStyle(.plain)
            
            // 1-Tap Calendar & Reminders Export Actions
            HStack(spacing: 8) {
                Button {
                    exportToAppleCalendar(event)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 11))
                        Text(event.calendarEventIdentifier != nil ? "Actualizează Calendar" : "Adaugă în Calendar")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button {
                    exportToAppleReminders(event)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.badge.plus")
                            .font(.system(size: 11))
                        Text(event.reminderItemIdentifier != nil ? "În Mementouri" : "Mementouri")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.08))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.leading, 38)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.02), radius: 6, x: 0, y: 2)
        )
    }
    
    private var emptyObligationsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: showCompletedEvents ? "checkmark.circle" : "calendar")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            
            Text(showCompletedEvents ? "Nicio obligație finalizată" : "Nicio obligație activă")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            
            Text(showCompletedEvents ? "Obligațiile rezolvate vor fi arhivate aici." : "Adaugă RCA, ITP, ISCIR, revizii sau alte scadențe cu un singur tap.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - TAB 2: Jurnal & Istoric
    private var tab2HistoryView: some View {
        VStack(spacing: 14) {
            // Sub-Segment Control: Intervenții Service vs. Contoare Telemetrie
            Picker("Tip Jurnal", selection: $historySubTab) {
                Text("Intervenții (\(asset.serviceItems.count))").tag(0)
                Text("Contoare & Măsurători (\(asset.measurements.count))").tag(1)
            }
            .pickerStyle(.segmented)
            
            if historySubTab == 0 {
                // Interventions & Repairs List
                interventionsListView
            } else {
                // Quantitative Telemetry & Lab Biomarker Ledger
                MeasurementLedgerView(asset: asset)
            }
        }
    }
    
    private var interventionsListView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Istoric Intervenții & Piese")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("\(asset.serviceItems.count) piese / intervenții înregistrate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingAddServiceItemSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Intervenție")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            
            // Navigation link to Component History
            NavigationLink {
                ComponentHistoryView(asset: asset)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Panou Detaliat Uzură & Istoric Piese")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Vezi calculul Δ km, Δ timp și bara de uzură pe fiecare componentă")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            
            if asset.serviceItems.isEmpty {
                VStack(spacing: 8) {
                    Text("Nicio intervenție service înregistrată")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(asset.serviceItems.sorted { $0.serviceDate > $1.serviceDate }) { item in
                        serviceItemRowCard(item)
                    }
                }
            }
        }
    }
    
    private func serviceItemRowCard(_ item: ServiceItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(formattedDate(item.serviceDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(item.totalEffectiveCost)) RON")
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            HStack(spacing: 8) {
                if let km = item.mileageAtService {
                    Text("\(km) km")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let shop = item.shopName, !shop.isEmpty {
                    Text("• \(shop)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let specialist = item.specialistOrDoctorName, !specialist.isEmpty {
                    Text("• \(specialist)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let rmaDays = item.daysInService, rmaDays > 0 {
                    Text("+\(rmaDays)d în service")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - TAB 3: Specificații & Contacte
    private var tab3SpecificationsView: some View {
        VStack(spacing: 14) {
            // 1. Domain Section View based on asset category
            switch asset.category {
            case .home:
                HomeDomainSectionView(asset: asset)
            case .health:
                HealthDomainSectionView(asset: asset)
            case .pet:
                PetDomainSectionView(asset: asset)
            case .documents:
                DocumentDomainSectionView(asset: asset)
            case .warranties:
                WarrantyDomainSectionView(asset: asset)
            case .subscriptions:
                SubscriptionDomainSectionView(asset: asset)
            case .vehicle:
                VehicleDomainSectionView(asset: asset)
            case .custom:
                CustomDomainSectionView(asset: asset)
            }
            
            // 2. Associated Specialist / Contact Card
            associatedContactSection
            
            // 3. Unlimited Dynamic Fields
            DynamicFieldEditorView(asset: asset)
        }
    }
    
    private var associatedContactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Specialist & Contact Asociat", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            
            if let name = asset.primaryContactName, !name.isEmpty {
                ContactActionBar(
                    contactName: name,
                    contactPhone: asset.primaryContactPhone,
                    contactEmail: asset.primaryContactEmail,
                    contactRole: asset.primaryContactRole,
                    onEdit: {
                        showingEditAssetSheet = true
                    }
                )
            } else {
                HStack {
                    ContactPickerButton(
                        title: "Asociază din Agendă",
                        iconName: "person.badge.plus"
                    ) { contact in
                        asset.primaryContactName = contact.name
                        asset.primaryContactPhone = contact.phone
                        asset.primaryContactEmail = contact.email
                        asset.primaryContactRole = contact.organization
                        asset.updatedAt = Date()
                        showToast("Contact asociat: \(contact.name)")
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }
    
    // MARK: - TAB 4: Dosar Documente
    private var tab4DocumentsView: some View {
        VStack(spacing: 14) {
            // Header with Actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Documente Atașate")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("\(allAttachments.count) fișiere în dosarul complet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingMultiSourceInput = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.badge.ellipsis")
                        Text("Adaugă Scan")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            
            // Export Full PDF Dossier Card
            Button {
                generateAndShareDossier()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exportă Dosar Complet PDF")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Generează dosarul complet cu sumar, scadențe și anexe scanate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isGeneratingPDF {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPDF)
            
            // Attachments Grid
            if allAttachments.isEmpty {
                emptyDocumentsCard
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(allAttachments) { att in
                        attachmentGridCard(att)
                    }
                }
            }
        }
    }
    
    private func attachmentGridCard(_ att: DocumentAttachment) -> some View {
        Button {
            previewAttachment = att
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: iconForExtension(att.fileExtension))
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(att.fileExtension.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Text(att.fileName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text(formattedDate(att.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var emptyDocumentsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            
            Text("Niciun document scanat încă")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            
            Text("Folosește camera, importă PDF-uri sau imagini din galerie pentru a păstra facturile, polițele și actele la un loc.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Computed Properties
    private var activeEvents: [LifecycleEvent] {
        asset.events.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
    }
    
    private var completedEvents: [LifecycleEvent] {
        asset.events.filter { $0.isCompleted }.sorted { $0.dueDate > $1.dueDate }
    }
    
    private var allAttachments: [DocumentAttachment] {
        var result: [DocumentAttachment] = []
        var seen = Set<UUID>()
        
        for a in asset.attachments where !seen.contains(a.id) {
            seen.insert(a.id)
            result.append(a)
        }
        for e in asset.events {
            for a in e.attachments where !seen.contains(a.id) {
                seen.insert(a.id)
                result.append(a)
            }
        }
        for s in asset.serviceItems {
            for a in s.attachments where !seen.contains(a.id) {
                seen.insert(a.id)
                result.append(a)
            }
        }
        return result
    }
    
    // MARK: - Calendar & Reminders Export Logic
    private func exportToAppleCalendar(_ event: LifecycleEvent) {
        Task {
            do {
                _ = try await CalendarSyncService.shared.syncToCalendar(event: event)
                await MainActor.run {
                    showToast("Sincronizat în Apple Calendar!")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    showToast("Eroare la sincronizarea calendarului.")
                }
            }
        }
    }
    
    private func exportToAppleReminders(_ event: LifecycleEvent) {
        Task {
            do {
                _ = try await CalendarSyncService.shared.syncToReminders(event: event)
                await MainActor.run {
                    showToast("Adăugat în Mementouri!")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    showToast("Eroare la adăugarea în Mementouri.")
                }
            }
        }
    }
    
    private func generateAndShareDossier() {
        isGeneratingPDF = true
        Task {
            let url = try? PDFDossierGenerator.shared.generateDossierFile(for: asset)
            await MainActor.run {
                self.exportedPDFURL = url
                self.isGeneratingPDF = false
                if url != nil {
                    self.showingShareSheet = true
                }
            }
        }
    }
    
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toastMessage == text {
                    toastMessage = nil
                }
            }
        }
    }
    
    private func toastView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .shadow(radius: 6)
    }
    
    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        default: return "doc.fill"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
    }
}

// MARK: - Add Obligation Sheet
private struct AddObligationSheet: View {
    let asset: Asset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var title: String = ""
    @State private var dueDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var costText: String = ""
    @State private var provider: String = ""
    @State private var policyNumber: String = ""
    @State private var cadenceMonths: Int = 12
    
    init(asset: Asset) {
        self.asset = asset
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Detalii Obligație") {
                    TextField("Denumire (ex: Asigurare RCA, Verificare ISCIR)", text: $title)
                    DatePicker("Dată Scadență", selection: $dueDate, displayedComponents: .date)
                    
                    TextField("Furnizor / Asigurător", text: $provider)
                    TextField("Serie / Număr Poliță / Contract", text: $policyNumber)
                    
                    HStack {
                        Text("Cost Estimat (RON)")
                        Spacer()
                        TextField("0", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                
                Section("Periodicitate / Cadență") {
                    Picker("Recurență", selection: $cadenceMonths) {
                        Text("Fără recurență (Unică)").tag(0)
                        Text("Lunar (1 lună)").tag(1)
                        Text("La 3 luni").tag(3)
                        Text("La 6 luni").tag(6)
                        Text("Anual (12 luni)").tag(12)
                        Text("La 2 ani (24 luni)").tag(24)
                        Text("La 10 ani (120 luni)").tag(120)
                    }
                }
            }
            .navigationTitle("Obligație Nouă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        saveObligation()
                    }
                    .font(.body.weight(.bold))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveObligation() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let costVal = Double(costText.replacingOccurrences(of: ",", with: "."))
        let cadenceDays = cadenceMonths > 0 ? cadenceMonths * 30 : nil
        
        let event = LifecycleEvent(
            title: trimmed,
            dueDate: dueDate,
            cost: costVal,
            provider: provider.isEmpty ? nil : provider,
            policyOrContractNumber: policyNumber.isEmpty ? nil : policyNumber,
            cadenceDays: cadenceDays
        )
        event.asset = asset
        modelContext.insert(event)
        asset.updatedAt = Date()
        
        Task {
            _ = try? await NotificationScheduler.shared.scheduleReminders(for: event)
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}


#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
