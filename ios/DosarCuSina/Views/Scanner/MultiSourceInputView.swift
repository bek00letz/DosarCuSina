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
    
    // Extracted / Target Event State
    @State private var selectedAssetId: UUID? = nil
    @State private var eventTitle: String = ""
    @State private var provider: String = ""
    @State private var policyOrInvoiceNumber: String = ""
    @State private var eventDueDate: Date = Date()
    @State private var eventCost: String = ""
    @State private var cadenceDays: Int = 0
    @State private var notes: String = ""
    
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
    
    public init(preselectedAsset: Asset? = nil) {
        self.preselectedAsset = preselectedAsset
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Intake Mode Segmented Picker
                    intakeModeSelector
                    
                    // Mode-Specific Input Card
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
                        saveEventToVault()
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .disabled(eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    
    // MARK: - 3. Standardized Event Form Section
    private var eventDetailsFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Date Obligație / Factură")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                // Asset Selector
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
        
        extractionSuccessMessage = "Date extrase cu succes din fișierul PDF digital!"
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private func processImageLocally(_ image: UIImage) async {
        do {
            let scanResult = try await LocalOCRService.shared.scanReceipt(image: image)
            await MainActor.run {
                if let title = scanResult.suggestedTitle {
                    self.eventTitle = title
                }
                if let prov = scanResult.provider {
                    self.provider = prov
                }
                if let due = scanResult.dueDate {
                    self.eventDueDate = due
                }
                if let cost = scanResult.amount {
                    self.eventCost = String(format: "%.2f", cost)
                }
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
        let parsed = RomanianUtilityParser.shared.parse(rawText: text)
        
        if let prov = parsed.provider {
            provider = prov
            eventTitle = "Factură \(prov)"
        } else {
            eventTitle = "Factură / Notificare E-mail"
        }
        
        if let num = parsed.invoiceNumber {
            policyOrInvoiceNumber = num
        }
        
        if let due = parsed.dueDate {
            eventDueDate = due
        }
        
        if let cost = parsed.amount {
            eventCost = String(format: "%.2f", cost)
        }
        
        extractionSuccessMessage = "Date extrase din textul copiat!"
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private func saveEventToVault() {
        let trimmedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let costVal = Double(eventCost.replacingOccurrences(of: ",", with: "."))
        
        let newEvent = LifecycleEvent(
            title: trimmedTitle,
            dueDate: eventDueDate,
            cost: costVal,
            cadenceDays: cadenceDays > 0 ? cadenceDays : nil,
            notes: notes.isEmpty ? nil : notes,
            provider: provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : provider.trimmingCharacters(in: .whitespacesAndNewlines),
            policyOrContractNumber: policyOrInvoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : policyOrInvoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        // Attach Document if present
        if let pdfData = selectedPDFData {
            let doc = DocumentAttachment(
                fileName: selectedPDFName ?? "document.pdf",
                fileData: pdfData,
                mimeType: "application/pdf"
            )
            doc.event = newEvent
            newEvent.attachments.append(doc)
            modelContext.insert(doc)
        } else if let img = selectedPhotoImage, let imgData = img.jpegData(compressionQuality: 0.8) {
            let doc = DocumentAttachment(
                fileName: "scan_\(UUID().uuidString.prefix(6)).jpg",
                fileData: imgData,
                mimeType: "image/jpeg"
            )
            doc.event = newEvent
            newEvent.attachments.append(doc)
            modelContext.insert(doc)
        }
        
        // Link to selected asset
        if let targetAsset = assets.first(where: { $0.id == selectedAssetId }) {
            newEvent.asset = targetAsset
        } else if let preselected = preselectedAsset {
            newEvent.asset = preselected
        }
        
        modelContext.insert(newEvent)
        
        Task {
            _ = try? await NotificationScheduler.shared.scheduleReminders(for: newEvent)
        }
        
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}
