import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Unified intake interface supporting multi-media sources:
/// 1. Digital PDF Documents (e-invoices, policies from Mail/Files)
/// 2. Photo Library & Screenshots (PhotosPicker)
/// 3. Live Paper Camera Scanner (VisionKit Document Scanner)
/// 4. Copied Email / SMS Text (Direct text parsing)
/// 5. Direct Manual Entry Form
public struct MultiSourceInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.createdAt, order: .reverse) private var assets: [Asset]
    
    // Optional preselected asset if opened from AssetDetailView
    public var preselectedAsset: Asset?
    
    @State private var intakeMode: IntakeMode = .pdfFile
    
    // Routing & Target State
    @State private var routingDestination: RoutingDestination = .event
    @State private var autoMatchedReason: String? = nil
    @State private var selectedAssetId: UUID? = nil
    
    // Event State
    @State private var eventTitle: String = ""
    @State private var provider: String = ""
    @State private var policyOrInvoiceNumber: String = ""
    @State private var eventDueDate: Date = Date()
    @State private var eventCost: String = ""
    @State private var cadenceDays: Int = 0
    @State private var notes: String = ""
    
    // ServiceItem State
    @State private var serviceItemName: String = ""
    @State private var serviceCategory: String = "Întreținere"
    @State private var specialistOrDoctorName: String = ""
    @State private var partsCost: String = ""
    @State private var laborCost: String = ""
    @State private var serialOrBatchNumber: String = ""
    @State private var locationOrToothNumber: String = ""
    @State private var mileageAtService: String = ""
    @State private var daysInService: String = ""
    @State private var serviceWarrantyMonths: Int = 0
    
    // MeasurementLog State
    @State private var measurementDomain: MeasurementDomain = .electricityMeter
    @State private var measurementMetricName: String = "Index Contor Zi"
    @State private var measurementValue: String = ""
    @State private var measurementPreviousValue: String = ""
    @State private var measurementSecondaryValue: String = ""
    @State private var measurementUnit: String = "kWh"
    @State private var measurementUnitPrice: String = "0.68"
    @State private var measurementIsSelfRead: Bool = true
    @State private var measurementLabOrProvider: String = ""
    
    // PDF State
    @State private var isShowingPDFPicker = false
    @State private var selectedPDFName: String? = nil
    @State private var selectedPDFData: Data? = nil
    @State private var isExtractingPDF = false
    
    // Photo State
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoImage: UIImage? = nil
    
    // Live Camera State
    @State private var isShowingLiveCamera = false
    
    // Text / Email Paste State
    @State private var pastedEmailText: String = ""
    @State private var isAnalyzingText = false
    
    // AI & OCR Feedback
    @State private var isProcessingAI = false
    @State private var extractionSuccessMessage: String? = nil
    @State private var extractionWarning: String? = nil
    @State private var showingKeyPromptSheet = false
    
    public enum IntakeMode: String, CaseIterable, Identifiable {
        case pdfFile = "Fișier PDF"
        case photo = "Poze / Screenshot"
        case camera = "Cameră Hârtie"
        case pastedText = "Text E-mail"
        case manual = "Manual"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .pdfFile: return "doc.text.fill"
            case .photo: return "photo.on.rectangle.angled"
            case .camera: return "doc.viewfinder"
            case .pastedText: return "envelope.open.fill"
            case .manual: return "square.and.pencil"
            }
        }
    }
    
    public enum RoutingDestination: String, CaseIterable, Identifiable, Sendable {
        case event = "Obligație / Scadență"
        case serviceItem = "Intervenție / Service"
        case measurement = "Index / Parametru"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .event: return "calendar.badge.clock"
            case .serviceItem: return "wrench.and.screwdriver.fill"
            case .measurement: return "gauge.with.dots.needle.bottom.50percent"
            }
        }
    }
    
    public init(preselectedAsset: Asset? = nil) {
        self.preselectedAsset = preselectedAsset
    }
    
    @ViewBuilder
    private var modeSpecificCard: some View {
        switch intakeMode {
        case .pdfFile:
            pdfSourceCard
        case .photo:
            photoSourceCard
        case .camera:
            cameraSourceCard
        case .pastedText:
            pastedTextSourceCard
        case .manual:
            manualIntroCard
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Intake Mode Segmented Picker
                    intakeModeSelector
                    
                    // Mode-Specific Input Card
                    modeSpecificCard
                    
                    // Extraction Feedback Banner
                    if let success = extractionSuccessMessage {
                        successFeedbackBanner(success)
                    }
                    if let warning = extractionWarning {
                        warningFeedbackBanner(warning)
                    }
                    
                    // Standardized Event Editor Section
                    eventDetailsFormSection
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Intrare Document / Factură")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Închide") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează în Dosar") {
                        saveToVault()
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .disabled(!isFormValid)
                }
            }
            .fileImporter(
                isPresented: $isShowingPDFPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePDFSelected(result)
            }
            .sheet(isPresented: $isShowingLiveCamera) {
                LiveDocumentScannerView { scannedImages in
                    if let first = scannedImages.first {
                        self.selectedPhotoImage = first
                        self.intakeMode = .photo
                        Task {
                            await processImageLocally(first)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingKeyPromptSheet) {
                NavigationStack {
                    SettingsView()
                }
            }
            .onAppear {
                if let preselected = preselectedAsset {
                    selectedAssetId = preselected.id
                } else if let first = assets.first {
                    selectedAssetId = first.id
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            self.selectedPhotoImage = img
                        }
                        await processImageLocally(img)
                    }
                }
            }
        }
    }
    
    // MARK: - 1. Intake Mode Selector
    private var intakeModeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IntakeMode.allCases) { mode in
                    let isSelected = intakeMode == mode
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            intakeMode = mode
                        }
                        #if canImport(UIKit)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(.subheadline, design: .rounded, weight: isSelected ? .bold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                        .shadow(color: isSelected ? Color.blue.opacity(0.25) : .clear, radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - 2. Source Cards
    
    // PDF Source
    private var pdfSourceCard: some View {
        VStack(spacing: 12) {
            if let name = selectedPDFName {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                        Text("PDF Digital • Text nativ extras")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Schimbă") {
                        isShowingPDFPicker = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Button {
                    isShowingPDFPicker = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)
                        
                        Text("Selectează Factură sau Contract PDF")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Importă direct din Mail, WhatsApp sau Fișiere. Se extrag automat furnizorul, scadența și suma.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(Color.blue.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // Photo / Screenshot Source
    private var photoSourceCard: some View {
        VStack(spacing: 12) {
            if let img = selectedPhotoImage {
                HStack(spacing: 12) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Imagine selectată")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("Scanată on-device cu Vision OCR")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text("Schimbă")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(.purple)
                        
                        Text("Alege din Galerie sau Screenshot")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Capturi de ecran din Homebank, plăți online sau fotografii primite.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(Color.purple.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // Camera Live Scanner Source
    private var cameraSourceCard: some View {
        Button {
            isShowingLiveCamera = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                
                Text("Deschide Scanner Cameră Hârtie")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("Recunoaște automat marginile paginii, elimină reflexiile și îndreaptă perspectiva.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(Color.blue.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
    
    // Pasted Email / SMS Text Source
    private var pastedTextSourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lipește textul e-mailului sau al notificării:")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            
            TextEditor(text: $pastedEmailText)
                .frame(height: 110)
                .font(.system(.body, design: .rounded))
                .padding(8)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            HStack {
                Button {
                    #if canImport(UIKit)
                    if let str = UIPasteboard.general.string {
                        pastedEmailText = str
                        parsePastedText(str)
                    }
                    #endif
                } label: {
                    Label("Lipește din Clipboard", systemImage: "doc.on.clipboard.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Analizează Textul") {
                    parsePastedText(pastedEmailText)
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .disabled(pastedEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    // Manual Introduction Card
    private var manualIntroCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Introducere Directă Manuală")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text("Completează datele facturii sau poliței în formularul de mai jos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Feedback Banners
    private func successFeedbackBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func warningFeedbackBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    // MARK: - 3. Interactive Verification & Routing Card
    private var eventDetailsFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Verificare & Rutare în Dosar")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                if let reason = autoMatchedReason {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text(reason)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 4)
            
            // 3-way Destination Picker
            routingDestinationPicker
            
            VStack(spacing: 12) {
                // Target Asset Picker
                if !assets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Asociază Activului:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Picker("Activ", selection: $selectedAssetId) {
                            ForEach(assets) { asset in
                                Text(asset.name).tag(Optional(asset.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                
                // Dynamic Destination Form Fields
                switch routingDestination {
                case .event:
                    eventFields
                case .serviceItem:
                    serviceItemFields
                case .measurement:
                    measurementFields
                }
                
                // Universal Notes Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Observații / Mențiuni:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Opțional...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(.subheadline, design: .rounded))
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
    
    // MARK: - 3-way Routing Destination Picker
    private var routingDestinationPicker: some View {
        HStack(spacing: 8) {
            ForEach(RoutingDestination.allCases) { dest in
                let isSelected = routingDestination == dest
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        routingDestination = dest
                    }
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: dest.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(dest.rawValue)
                            .font(.system(.caption2, design: .rounded, weight: isSelected ? .bold : .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: isSelected ? Color.blue.opacity(0.25) : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Event Destination Form Fields
    @ViewBuilder
    private var eventFields: some View {
        // Event Title
        VStack(alignment: .leading, spacing: 4) {
            Text("Titlu Eveniment / Obligație:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField("ex: Factură Energie Electrică, Asigurare RCA", text: $eventTitle)
                .font(.system(.body, design: .rounded))
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        
        // Provider & Number
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Furnizor / Asigurător:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: Hidroelectrica", text: $provider)
                    .font(.system(.subheadline, design: .rounded))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Nr. Factură / Poliță:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: 1029384", text: $policyOrInvoiceNumber)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        // Due Date & Cost
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dată Scadență:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DatePicker("", selection: $eventDueDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Sumă de plată (RON):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("0.00", text: $eventCost)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        // Recurrence
        VStack(alignment: .leading, spacing: 4) {
            Text("Recurență Plată:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Picker("Recurență", selection: $cadenceDays) {
                Text("Fără recurență (Factură unică)").tag(0)
                Text("Lunar (30 zile)").tag(30)
                Text("Trimestrial (90 zile)").tag(90)
                Text("Semestrial (180 zile)").tag(180)
                Text("Anual (365 zile)").tag(365)
                Text("La 2 ani (730 zile)").tag(730)
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    // MARK: - Service Item Form Fields
    @ViewBuilder
    private var serviceItemFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Denumire Intervenție / Piesă:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField("ex: Schimb plăcuțe frână, Revizie centrală", text: $serviceItemName)
                .font(.system(.body, design: .rounded))
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Categorie:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Categorie", selection: $serviceCategory) {
                    Text("Întreținere").tag("Întreținere")
                    Text("Reparație").tag("Reparație")
                    Text("Revizie").tag("Revizie")
                    Text("Tratament").tag("Tratament")
                    Text("Garanție RMA").tag("Garanție RMA")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Specialist / Medic / Service:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: Dr. Popescu, AutoSoft", text: $specialistOrDoctorName)
                    .font(.system(.subheadline, design: .rounded))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cost Piese (RON):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("0.00", text: $partsCost)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Cost Manoperă (RON):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("0.00", text: $laborCost)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dată Intervenție:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DatePicker("", selection: $eventDueDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Kilometraj la Service:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: 145000", text: $mileageAtService)
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Serie / Lot / Tichet:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: Lot #94820", text: $serialOrBatchNumber)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Locație / Dinte FDI:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: Punte spate, #36", text: $locationOrToothNumber)
                    .font(.system(.subheadline, design: .rounded))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Zile Imobilizare RMA:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("0", text: $daysInService)
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Garanție Manoperă:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Luni", selection: $serviceWarrantyMonths) {
                    Text("Fără garanție").tag(0)
                    Text("3 luni").tag(3)
                    Text("6 luni").tag(6)
                    Text("12 luni").tag(12)
                    Text("24 luni").tag(24)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    // MARK: - Measurement Form Fields
    @ViewBuilder
    private var measurementFields: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Domeniu:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Domeniu", selection: $measurementDomain) {
                    ForEach(MeasurementDomain.allCases, id: \.self) { dom in
                        Text(dom.rawValue).tag(dom)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: measurementDomain) { _, newDom in
                    measurementUnit = newDom.defaultUnit
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Nume Parametru:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: Index Zi, Glicemie", text: $measurementMetricName)
                    .font(.system(.subheadline, design: .rounded))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Index / Valoare Nouă:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: 12480", text: $measurementValue)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Index Anterior:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("ex: 12100", text: $measurementPreviousValue)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Unitate:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("kWh", text: $measurementUnit)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preț Unitar (RON):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("0.68", text: $measurementUnitPrice)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Dată Citire:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DatePicker("", selection: $eventDueDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        
        HStack(spacing: 10) {
            Toggle("Index Autocitit", isOn: $measurementIsSelfRead)
                .font(.caption.weight(.medium))
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            TextField("Furnizor / Laborator", text: $measurementLabOrProvider)
                .font(.system(.subheadline, design: .rounded))
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    // MARK: - Validation
    private var isFormValid: Bool {
        switch routingDestination {
        case .event:
            return !eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .serviceItem:
            let title = serviceItemName.isEmpty ? eventTitle : serviceItemName
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .measurement:
            return !measurementValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    // MARK: - Asset Auto-Matching
    public struct ScoredAssetMatch {
        public let asset: Asset
        public let reason: String
        public let score: Int
        
        public init(asset: Asset, reason: String, score: Int) {
            self.asset = asset
            self.reason = reason
            self.score = score
        }
    }
    
    public static func matchAsset(for extractedText: String, in assets: [Asset]) -> ScoredAssetMatch? {
        guard !extractedText.isEmpty else { return nil }
        let normalized = RomanianUtilityParser.normalizeDiacritics(extractedText).uppercased()
        var matches: [ScoredAssetMatch] = []
        
        for candidate in assets {
            // 1. Vehicle 17-char VIN (Score: 100) — Normalize hyphens and spaces
            if let vin = candidate.vin, !vin.isEmpty {
                let cleanVin = vin.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").uppercased()
                if cleanVin.count >= 8 {
                    let vinRegexPattern = cleanVin.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"[\s\-]*"#)
                    let fullPattern = #"(?i)(?:\b|[^A-Z0-9])"# + vinRegexPattern + #"(?:\b|[^A-Z0-9])"#
                    if let regex = try? NSRegularExpression(pattern: fullPattern) {
                        let ns = normalized as NSString
                        if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) != nil {
                            matches.append(ScoredAssetMatch(asset: candidate, reason: "Serie Șasiu / VIN (\(vin))", score: 100))
                            continue
                        }
                    }
                    let docNoSpaces = normalized.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
                    if docNoSpaces.contains(cleanVin) {
                        matches.append(ScoredAssetMatch(asset: candidate, reason: "Serie Șasiu / VIN (\(vin))", score: 100))
                        continue
                    }
                    if cleanVin.count == 17 {
                        let last8 = String(cleanVin.suffix(8))
                        let partialPattern = #"(?i)(?:serie\s*(?:de\s*)?[sș]asiu|vin)[:\s]+[\s\-]*"# + NSRegularExpression.escapedPattern(for: last8) + #"(?:\b|[^A-Z0-9])"#
                        if let regex = try? NSRegularExpression(pattern: partialPattern) {
                            let ns = normalized as NSString
                            if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) != nil {
                                matches.append(ScoredAssetMatch(asset: candidate, reason: "Serie Șasiu / VIN (\(vin))", score: 100))
                                continue
                            }
                        }
                    }
                }
            }
            
            // 2. Utility POD Code (Score: 90)
            if let pod = candidate.podCode, !pod.isEmpty, normalized.contains(pod.uppercased()) {
                matches.append(ScoredAssetMatch(asset: candidate, reason: "Cod POD Energie (\(pod))", score: 90))
                continue
            }
            
            // 3. Utility CLC Code (Score: 90)
            if let clc = candidate.clcCode, !clc.isEmpty, normalized.contains(clc.uppercased()) {
                matches.append(ScoredAssetMatch(asset: candidate, reason: "Cod CLC Gaze (\(clc))", score: 90))
                continue
            }
            
            // 4. Water Client Code (Score: 90)
            if let water = candidate.waterClientCode, !water.isEmpty, normalized.contains(water.uppercased()) {
                matches.append(ScoredAssetMatch(asset: candidate, reason: "Cod Client Apă (\(water))", score: 90))
                continue
            }
            
            // 5. Pet Microchip (Score: 85)
            if let chip = candidate.microchipNumber, !chip.isEmpty, normalized.contains(chip) {
                matches.append(ScoredAssetMatch(asset: candidate, reason: "Microcip (\(chip))", score: 85))
                continue
            }
            
            // 6. Vehicle License Plate (Score: 80) — Enforce word/token boundary to avoid substring collisions
            if let plate = candidate.licensePlate, !plate.isEmpty {
                let cleanPlate = plate.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").uppercased()
                if cleanPlate.count >= 5 {
                    if let tokenRegex = try? NSRegularExpression(pattern: #"([A-Z]+|[0-9]+)"#) {
                        let nsPlate = cleanPlate as NSString
                        let tokenMatches = tokenRegex.matches(in: cleanPlate, range: NSRange(location: 0, length: nsPlate.length))
                        let tokens = tokenMatches.map { nsPlate.substring(with: $0.range) }
                        let plateRegexPattern = tokens.joined(separator: #"[\s\-]*"#)
                        let fullPattern = #"(?i)(?:\b|[^A-Z0-9])"# + plateRegexPattern + #"(?:\b|[^A-Z0-9])"#
                        if let regex = try? NSRegularExpression(pattern: fullPattern) {
                            let nsDoc = normalized as NSString
                            if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: nsDoc.length)) != nil {
                                matches.append(ScoredAssetMatch(asset: candidate, reason: "Număr Auto (\(plate))", score: 80))
                                continue
                            }
                        }
                    }
                }
            }
            
            // 7. Person Name (Health) (Score: 60)
            if let pName = candidate.personName, !pName.isEmpty {
                let cleanName = pName.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanName.isEmpty && normalized.contains(cleanName) {
                    matches.append(ScoredAssetMatch(asset: candidate, reason: "Dosar Medical: \(pName)", score: 60))
                    continue
                }
            }
            
            // 8. Serial / IMEI (Warranties) (Score: 50)
            if let sn = candidate.serialOrImei, !sn.isEmpty {
                let cleanSn = sn.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanSn.isEmpty && normalized.contains(cleanSn) {
                    matches.append(ScoredAssetMatch(asset: candidate, reason: "Serie / IMEI (\(sn))", score: 50))
                    continue
                }
            }
        }
        
        // 7. Multi-identifier conflict resolution: Score matches by identifier entropy/specificity
        return matches.sorted(by: { $0.score > $1.score }).first
    }
    
    private func attemptAutoMatch(extractedText: String) {
        guard let bestMatch = Self.matchAsset(for: extractedText, in: assets) else { return }
        applyAutoMatch(bestMatch.asset, reason: bestMatch.reason)
    }
    
    private func applyAutoMatch(_ asset: Asset, reason: String) {
        selectedAssetId = asset.id
        autoMatchedReason = reason
        
        let lower = pastedEmailText.lowercased()
        if lower.contains("index nou") || lower.contains("autocitit") || lower.contains("1.8.0") {
            routingDestination = .measurement
            if asset.category == .home {
                measurementDomain = .electricityMeter
                measurementMetricName = "Index Contor Energie"
                measurementUnit = "kWh"
            }
        } else if lower.contains("service") || lower.contains("manopera") || lower.contains("piese") || lower.contains("reparatie") || lower.contains("revizie") {
            routingDestination = .serviceItem
            serviceCategory = "Revizie"
        }
    }
    
    // MARK: - Logic & Handlers
    private func handlePDFSelected(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                extractionWarning = "Nu s-a putut obține permisiunea de acces la fișierul PDF."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            selectedPDFName = url.lastPathComponent
            
            if let data = try? Data(contentsOf: url) {
                selectedPDFData = data
                processPDFDirectly(data: data, fileName: url.lastPathComponent)
            }
            
        case .failure(let error):
            extractionWarning = "Eroare la deschiderea PDF-ului: \(error.localizedDescription)"
        }
    }
    
    private func processPDFDirectly(data: Data, fileName: String) {
        isExtractingPDF = true
        let parsed = PDFExtractorService.shared.extractAndParse(pdfData: data)
        self.pastedEmailText = parsed.extractedText
        
        isExtractingPDF = false
        if let title = parsed.title {
            eventTitle = title
        } else {
            eventTitle = fileName.replacingOccurrences(of: ".pdf", with: "")
        }
        
        if let prov = parsed.provider {
            provider = prov
        }
        
        if let invNum = parsed.invoiceNumber {
            policyOrInvoiceNumber = invNum
        }
        
        if let due = parsed.dueDate {
            eventDueDate = due
        }
        
        if let cost = parsed.amount {
            eventCost = String(format: "%.2f", cost)
        }
        
        let utilityData = RomanianUtilityParser.shared.parseUtilityBill(text: parsed.extractedText)
        if let index = utilityData.indexReading {
            measurementValue = String(format: "%.0f", index)
        }
        if let prev = utilityData.previousIndexReading {
            measurementPreviousValue = String(format: "%.0f", prev)
        }
        
        attemptAutoMatch(extractedText: parsed.extractedText)
        
        extractionSuccessMessage = "Date extrase cu succes din fișierul PDF digital!"
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private func processImageLocally(_ image: UIImage) async {
        do {
            let scanResult = try await LocalOCRService.shared.scanImage(image)
            let utilityData = RomanianUtilityParser.shared.parseUtilityBill(text: scanResult.rawText)
            
            await MainActor.run {
                self.pastedEmailText = scanResult.rawText
                if utilityData.provider != .general {
                    self.provider = utilityData.provider.displayName
                    self.eventTitle = "Factură \(utilityData.provider.displayName)"
                } else if self.eventTitle.isEmpty {
                    self.eventTitle = "Document Scanat"
                }
                
                if let num = utilityData.invoiceNumber {
                    self.policyOrInvoiceNumber = num
                }
                
                if let due = scanResult.candidateDueDate ?? utilityData.dueDate {
                    self.eventDueDate = due
                }
                if let cost = scanResult.candidateTotal ?? utilityData.totalAmount {
                    self.eventCost = String(format: "%.2f", cost)
                }
                if let index = utilityData.indexReading {
                    self.measurementValue = String(format: "%.0f", index)
                }
                if let prev = utilityData.previousIndexReading {
                    self.measurementPreviousValue = String(format: "%.0f", prev)
                }
                
                self.attemptAutoMatch(extractedText: scanResult.rawText)
                
                self.extractionSuccessMessage = "Factură scanată cu succes prin Vision OCR!"
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
        } catch {
            await MainActor.run {
                self.extractionWarning = "OCR-ul local nu a identificat toate datele. Poți completa manual detaliile."
            }
        }
    }
    
    private func parsePastedText(_ text: String) {
        pastedEmailText = text
        let parsed = RomanianUtilityParser.shared.parseUtilityBill(text: text)
        
        if parsed.provider != .general {
            provider = parsed.provider.displayName
            eventTitle = "Factură \(parsed.provider.displayName)"
        } else {
            eventTitle = "Factură / Notificare E-mail"
        }
        
        if let num = parsed.invoiceNumber {
            policyOrInvoiceNumber = num
        }
        
        if let due = parsed.dueDate {
            eventDueDate = due
        }
        
        if let cost = parsed.totalAmount {
            eventCost = String(format: "%.2f", cost)
        }
        if let index = parsed.indexReading {
            measurementValue = String(format: "%.0f", index)
        }
        if let prev = parsed.previousIndexReading {
            measurementPreviousValue = String(format: "%.0f", prev)
        }
        
        attemptAutoMatch(extractedText: text)
        
        extractionSuccessMessage = "Date extrase din textul copiat!"
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private func saveToVault() {
        guard let targetAsset = assets.first(where: { $0.id == selectedAssetId }) ?? preselectedAsset ?? assets.first else { return }
        
        // Common attachment creation helper
        let attachment: DocumentAttachment? = {
            if let pdfData = selectedPDFData {
                return DocumentAttachment(
                    fileName: selectedPDFName ?? "document.pdf",
                    fileExtension: "pdf",
                    fileData: pdfData,
                    extractedText: pastedEmailText.isEmpty ? nil : pastedEmailText
                )
            } else if let img = selectedPhotoImage, let imgData = img.jpegData(compressionQuality: 0.85) {
                return DocumentAttachment(
                    fileName: "scan_\(UUID().uuidString.prefix(6)).jpg",
                    fileExtension: "jpg",
                    fileData: imgData,
                    extractedText: pastedEmailText.isEmpty ? nil : pastedEmailText
                )
            }
            return nil
        }()
        
        switch routingDestination {
        case .event:
            let trimmedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return }
            let costVal = RomanianUtilityParser.parseRomanianAmount(eventCost)
            
            let newEvent = LifecycleEvent(
                title: trimmedTitle,
                eventDescription: notes.isEmpty ? nil : notes,
                dueDate: eventDueDate,
                cost: costVal,
                provider: provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : provider.trimmingCharacters(in: .whitespacesAndNewlines),
                policyOrContractNumber: policyOrInvoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : policyOrInvoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                cadenceDays: cadenceDays > 0 ? cadenceDays : nil
            )
            newEvent.asset = targetAsset
            if let att = attachment {
                att.event = newEvent
                newEvent.attachments.append(att)
                modelContext.insert(att)
            }
            modelContext.insert(newEvent)
            targetAsset.updatedAt = Date()
            
            Task {
                _ = try? await NotificationScheduler.shared.scheduleReminders(for: newEvent)
            }
            
        case .serviceItem:
            let trimmedName = serviceItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? eventTitle : serviceItemName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }
            
            let parts = RomanianUtilityParser.parseRomanianAmount(partsCost)
            let labor = RomanianUtilityParser.parseRomanianAmount(laborCost)
            let totalCost = RomanianUtilityParser.parseRomanianAmount(eventCost) ?? ((parts ?? 0) + (labor ?? 0))
            let mileage = Double(mileageAtService.replacingOccurrences(of: " ", with: ""))
            let daysInSvc = Int(daysInService)
            
            let newService = ServiceItem(
                name: trimmedName,
                category: serviceCategory,
                partBrand: provider.isEmpty ? nil : provider,
                cost: totalCost > 0 ? totalCost : nil,
                laborCost: labor,
                partsCost: parts,
                serviceDate: eventDueDate,
                mileageAtService: mileage,
                specialistOrDoctorName: specialistOrDoctorName.isEmpty ? nil : specialistOrDoctorName,
                serialOrBatchNumber: serialOrBatchNumber.isEmpty ? nil : serialOrBatchNumber,
                locationOrToothNumber: locationOrToothNumber.isEmpty ? nil : locationOrToothNumber,
                daysInService: daysInSvc,
                warrantyMonths: serviceWarrantyMonths > 0 ? serviceWarrantyMonths : nil,
                notes: notes.isEmpty ? nil : notes
            )
            newService.asset = targetAsset
            modelContext.insert(newService)
            if let att = attachment {
                att.asset = targetAsset
                targetAsset.attachments.append(att)
                modelContext.insert(att)
                newService.attachments.append(att)
            }
            
            // Update vehicle odometer if provided
            if let km = mileage, targetAsset.category == .vehicle {
                if targetAsset.currentMetricValue == nil || km > (targetAsset.currentMetricValue ?? 0) {
                    targetAsset.currentMetricValue = km
                }
            }
            
            // Statutory RMA Warranty Extension (OUG 140/2021)
            if let days = daysInSvc, days > 0, targetAsset.category == .warranties {
                if let warrantyEvent = targetAsset.events.first(where: { $0.title.localizedCaseInsensitiveContains("Garanție") }) {
                    warrantyEvent.dueDate = Calendar.current.date(byAdding: .day, value: days, to: warrantyEvent.dueDate) ?? warrantyEvent.dueDate
                }
            }
            targetAsset.updatedAt = Date()
            
        case .measurement:
            guard let val = Double(measurementValue.replacingOccurrences(of: ",", with: ".")) else { return }
            let prevVal = Double(measurementPreviousValue.replacingOccurrences(of: ",", with: "."))
            let secVal = Double(measurementSecondaryValue.replacingOccurrences(of: ",", with: "."))
            let uPrice = RomanianUtilityParser.parseRomanianAmount(measurementUnitPrice)
            
            let newMeasurement = MeasurementLog(
                domain: measurementDomain,
                metricName: measurementMetricName,
                value: val,
                secondaryValue: secVal,
                unit: measurementUnit,
                recordedAt: eventDueDate,
                previousValue: prevVal,
                unitPrice: uPrice,
                isSelfRead: measurementIsSelfRead,
                labOrProviderName: measurementLabOrProvider.isEmpty ? (provider.isEmpty ? nil : provider) : measurementLabOrProvider,
                notes: notes.isEmpty ? nil : notes
            )
            newMeasurement.asset = targetAsset
            if let att = attachment {
                att.asset = targetAsset
                targetAsset.attachments.append(att)
                newMeasurement.attachments.append(att)
                modelContext.insert(att)
            }
            modelContext.insert(newMeasurement)
            
            // Update asset currentMetricValue for odometer or vehicle
            if measurementDomain == .odometer || targetAsset.category == .vehicle {
                targetAsset.currentMetricValue = val
            }
            targetAsset.updatedAt = Date()
        }
        
        WidgetDataSyncService.shared.sync(context: modelContext)
        
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}
