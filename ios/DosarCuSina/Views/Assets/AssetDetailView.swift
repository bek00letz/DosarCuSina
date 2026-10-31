import SwiftUI
import SwiftData

public struct AssetDetailView: View {
    @Bindable public var asset: Asset
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAddEventSheet = false
    @State private var showingEditTelemetry = false
    @State private var newTelemetryValue: String = ""
    @State private var showCompletedEvents = false
    @State private var exportedPDFURL: URL? = nil
    @State private var isGeneratingPDF = false
    @State private var showingShareSheet = false
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Card
                headerCard
                
                // Telemetry & Quick Metrics Card
                if asset.metricUnit != nil {
                    telemetryCard
                }
                
                // Events Header & Filter
                eventsSectionHeader
                
                // Events List
                if displayedEvents.isEmpty {
                    emptyEventsState
                } else {
                    VStack(spacing: 10) {
                        ForEach(displayedEvents) { event in
                            EventRowCard(event: event)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
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
                    
                    Button {
                        showingAddEventSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddEventSheet) {
            addEventSheet
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedPDFURL {
                #if canImport(UIKit)
                ActivityView(activityItems: [url])
                #endif
            }
        }
        .alert("Actualizare Contor", isPresented: $showingEditTelemetry) {
            TextField("Valoare nouă", text: $newTelemetryValue)
                .keyboardType(.numberPad)
            Button("Anulează", role: .cancel) {}
            Button("Actualizează") {
                if let val = Double(newTelemetryValue.replacingOccurrences(of: ",", with: ".")) {
                    asset.currentMetricValue = val
                    asset.updatedAt = Date()
                }
            }
        } message: {
            Text("Introdu valoarea curentă în \(asset.metricUnit ?? "unități").")
        }
    }
    
    private var displayedEvents: [LifecycleEvent] {
        asset.events
            .filter { showCompletedEvents ? $0.isCompleted : !$0.isCompleted }
            .sorted { $0.dueDate < $1.dueDate }
    }
    
    // MARK: - Header
    private var headerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: asset.iconName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(asset.accentColor)
                .frame(width: 60, height: 60)
                .background(asset.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                
                if let sub = asset.subtitle {
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
    
    // MARK: - Telemetry
    private var telemetryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Contor Curent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(asset.currentMetricValue ?? 0)) \(asset.metricUnit ?? "")")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            
            Spacer()
            
            Button {
                newTelemetryValue = "\(Int(asset.currentMetricValue ?? 0))"
                showingEditTelemetry = true
            } label: {
                Text("Actualizează")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Events Header
    private var eventsSectionHeader: some View {
        HStack {
            Text("Evenimente & Obligații")
                .font(.system(.headline, design: .rounded, weight: .bold))
            
            Spacer()
            
            Picker("Filtru", selection: $showCompletedEvents) {
                Text("Active").tag(false)
                Text("Istoric").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .padding(.horizontal, 4)
    }
    
    private var emptyEventsState: some View {
        VStack(spacing: 8) {
            Text(showCompletedEvents ? "Niciun eveniment finalizat" : "Nicio obligație în așteptare")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Add Event Sheet
    @State private var newEventTitle = ""
    @State private var newEventDueDate = Date()
    @State private var newEventCost = ""
    @State private var newEventCadence = 365
    
    private var addEventSheet: some View {
        NavigationStack {
            Form {
                Section("Detalii Eveniment") {
                    TextField("Denumire (ex: Revizie, RCA, Vaccin)", text: $newEventTitle)
                    DatePicker("Dată Scadență", selection: $newEventDueDate, displayedComponents: .date)
                    TextField("Cost estimat (RON)", text: $newEventCost)
                        .keyboardType(.decimalPad)
                }
                
                Section("Recurență") {
                    Picker("Se repetă la fiecare", selection: $newEventCadence) {
                        Text("3 luni").tag(90)
                        Text("6 luni").tag(180)
                        Text("1 an").tag(365)
                        Text("2 ani").tag(730)
                        Text("Fără recurență").tag(0)
                    }
                }
            }
            .navigationTitle("Adaugă Eveniment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        showingAddEventSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adaugă") {
                        let costVal = Double(newEventCost.replacingOccurrences(of: ",", with: "."))
                        let ev = LifecycleEvent(
                            title: newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                            dueDate: newEventDueDate,
                            cost: costVal,
                            cadenceDays: newEventCadence > 0 ? newEventCadence : nil
                        )
                        ev.asset = asset
                        modelContext.insert(ev)
                        Task {
                            _ = try? await NotificationScheduler.shared.scheduleReminders(for: ev)
                        }
                        showingAddEventSheet = false
                        newEventTitle = ""
                        newEventCost = ""
                    }
                    .disabled(newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
