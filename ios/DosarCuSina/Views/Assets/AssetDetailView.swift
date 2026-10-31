import SwiftUI
import SwiftData

/// Comprehensive detail view for an asset.
/// Displays category-tailored specifications (VIN, plate, boiler, microchip, meters),
/// telemetry meters, service item history link, editable events with line items,
/// and multi-source document ingestion.
public struct AssetDetailView: View {
    @Bindable public var asset: Asset
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingEditAssetSheet = false
    @State private var showingMultiSourceInput = false
    @State private var editingEvent: LifecycleEvent? = nil
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
                // 1. Header Hero Card
                headerCard
                
                // 2. Category-Specific Specifications Card
                specificationsCard
                
                // 3. Service & Components Timeline Navigation Card (if Vehicle or has components)
                if asset.category == .vehicle || !asset.serviceItems.isEmpty {
                    serviceHistoryCard
                }
                
                // 4. Telemetry & Metric Card
                if asset.metricUnit != nil {
                    telemetryCard
                }
                
                // 5. Events & Obligations Section
                eventsSection
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
                        showingEditAssetSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Button {
                        showingMultiSourceInput = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditAssetSheet) {
            EditAssetSheet(asset: asset)
        }
        .sheet(isPresented: $showingMultiSourceInput) {
            MultiSourceInputView(preselectedAsset: asset)
        }
        .sheet(item: $editingEvent) { event in
            EditEventSheet(event: event)
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
    
    // MARK: - 1. Header Card
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
    
    // MARK: - 2. Category Specifications Card
    private var specificationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Specificații & Identificare", systemImage: "info.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Button {
                    showingEditAssetSheet = true
                } label: {
                    Text("Editează")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            
            VStack(spacing: 8) {
                switch asset.category {
                case .vehicle:
                    vehicleSpecsGrid
                case .home:
                    homeSpecsGrid
                case .pet:
                    petSpecsGrid
                case .health:
                    healthSpecsGrid
                default:
                    genericSpecsGrid
                }
                
                // Dynamic fields if present
                if !asset.dynamicFields.isEmpty {
                    Divider().padding(.vertical, 4)
                    dynamicFieldsGrid
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
    
    // Vehicle Specs
    private var vehicleSpecsGrid: some View {
        VStack(spacing: 8) {
            if let plate = asset.licensePlate {
                specRow(label: "Număr Înmatriculare", value: plate, isMonospaced: true, isBold: true)
            }
            if let vin = asset.vinNumber {
                specRow(label: "Serie Șasiu (VIN)", value: vin, isMonospaced: true)
            }
            if let fuel = asset.fuelType {
                specRow(label: "Combustibil", value: fuel)
            }
            if let year = asset.manufactureYear {
                specRow(label: "An Fabricație", value: "\(year)")
            }
            if let disp = asset.engineDisplacementCm3, let pwr = asset.enginePowerHp {
                specRow(label: "Motorizare", value: "\(disp) cm³ • \(pwr) CP")
            } else if let disp = asset.engineDisplacementCm3 {
                specRow(label: "Cilindree", value: "\(disp) cm³")
            } else if let pwr = asset.enginePowerHp {
                specRow(label: "Putere", value: "\(pwr) CP")
            }
        }
    }
    
    // Home Specs
    private var homeSpecsGrid: some View {
        VStack(spacing: 8) {
            if let addr = asset.fullAddress {
                specRow(label: "Adresă", value: addr)
            }
            if let area = asset.surfaceAreaM2 {
                specRow(label: "Suprafață Utilă", value: "\(Int(area)) m²")
            }
            if let cy = asset.constructionYear {
                specRow(label: "An Construcție", value: "\(cy)")
            }
            if let boiler = asset.heatingBoilerModel {
                specRow(label: "Centrală Termică", value: boiler)
            }
            if let boilerSerial = asset.heatingBoilerSerial {
                specRow(label: "Serie Centrală", value: boilerSerial, isMonospaced: true)
            }
            if let gas = asset.gasMeterSerial {
                specRow(label: "Contor Gaze", value: gas, isMonospaced: true)
            }
            if let elec = asset.electricityMeterSerial {
                specRow(label: "Contor Curent", value: elec, isMonospaced: true)
            }
            if let water = asset.waterMeterSerial {
                specRow(label: "Contor Apă", value: water, isMonospaced: true)
            }
        }
    }
    
    // Pet Specs
    private var petSpecsGrid: some View {
        VStack(spacing: 8) {
            if let sp = asset.petSpecies {
                specRow(label: "Specie", value: sp)
            }
            if let br = asset.petBreed {
                specRow(label: "Rasă", value: br)
            }
            if let chip = asset.petMicrochipNumber {
                specRow(label: "Microchip ISO", value: chip, isMonospaced: true)
            }
            if let bdate = asset.petBirthDate {
                specRow(label: "Data Nașterii", value: formattedDate(bdate))
            }
            if let vet = asset.veterinarianClinic {
                specRow(label: "Clinică Veterinară", value: vet)
            }
            if let phone = asset.veterinarianPhone {
                specRow(label: "Telefon Veterinar", value: phone)
            }
        }
    }
    
    // Health Specs
    private var healthSpecsGrid: some View {
        VStack(spacing: 8) {
            if let bt = asset.bloodType {
                specRow(label: "Grupă Sanguină", value: bt, isBold: true)
            }
            if let doc = asset.familyDoctorName {
                specRow(label: "Medic de Familie", value: doc)
            }
            if let phone = asset.familyDoctorPhone {
                specRow(label: "Telefon Medic", value: phone)
            }
            if let ice = asset.emergencyContactName {
                specRow(label: "Contact Urgență", value: ice)
            }
            if let iceP = asset.emergencyContactPhone {
                specRow(label: "Telefon Urgență", value: iceP)
            }
            if let alg = asset.allergiesNotes {
                specRow(label: "Alergii", value: alg)
            }
        }
    }
    
    private var genericSpecsGrid: some View {
        VStack(spacing: 8) {
            if asset.subtitle != nil {
                specRow(label: "Detalii", value: asset.subtitle ?? "")
            }
            specRow(label: "Creat la", value: formattedDate(asset.createdAt))
        }
    }
    
    private var dynamicFieldsGrid: some View {
        VStack(spacing: 6) {
            ForEach(asset.dynamicFields) { f in
                specRow(label: f.label, value: f.displayValue, isMonospaced: f.fieldType == .number)
            }
        }
    }
    
    private func specRow(label: String, value: String, isMonospaced: Bool = false, isBold: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: isMonospaced ? .monospaced : .rounded, weight: isBold ? .bold : .regular))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    // MARK: - 3. Service & Maintenance Navigation Card
    private var serviceHistoryCard: some View {
        NavigationLink {
            ComponentHistoryView(asset: asset)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Istoric Piese & Mentenanță Service")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("\(asset.serviceItems.count) componente monitorizate (plăcuțe, filtre, ulei)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 4. Telemetry Card
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
    
    // MARK: - 5. Events Section
    private var eventsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Obligații & Facturi")
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
            
            if displayedEvents.isEmpty {
                VStack(spacing: 8) {
                    Text(showCompletedEvents ? "Niciun eveniment finalizat" : "Nicio obligație în așteptare")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(displayedEvents) { event in
                        Button {
                            editingEvent = event
                        } label: {
                            EventRowCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var displayedEvents: [LifecycleEvent] {
        asset.events
            .filter { showCompletedEvents ? $0.isCompleted : !$0.isCompleted }
            .sorted { $0.dueDate < $1.dueDate }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
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
