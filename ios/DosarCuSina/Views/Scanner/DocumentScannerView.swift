import SwiftUI
import PhotosUI
import SwiftData

public struct DocumentScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var assets: [Asset]
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isProcessingLocalOCR = false
    @State private var isProcessingGeminiAI = false
    @State private var localOCRResult: LocalOCRScanResult? = nil
    @State private var geminiResult: InvoiceOCRResponse? = nil
    @State private var errorMessage: String? = nil
    @State private var showingKeyPromptSheet: Bool = false
    
    // Extracted Fields for Saving
    @State private var eventTitle: String = ""
    @State private var eventDueDate: Date = Date()
    @State private var eventCost: String = ""
    @State private var selectedAssetId: UUID? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image Picker / Preview Area
                    imagePreviewSection
                    
                    if isProcessingLocalOCR || isProcessingGeminiAI {
                        loadingStateView
                    } else if let gemini = geminiResult {
                        geminiResultSection(gemini)
                    } else if let local = localOCRResult {
                        localOCRResultSection(local)
                    }
                    
                    if selectedImage != nil {
                        saveEventSection
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Scanare Factură")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Închide") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingKeyPromptSheet) {
                NavigationStack {
                    SettingsView()
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await processLoadedImage(image)
                    }
                }
            }
        }
    }
    
    // MARK: - Image Preview Section
    private var imagePreviewSection: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                
                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Schimbă poza", systemImage: "photo.badge.arrow.down")
                            .font(.subheadline.weight(.medium))
                    }
                    
                    Spacer()
                    
                    Button {
                        if KeychainManager.hasConfiguredAPIKey {
                            Task { await runGeminiSweep(image: image) }
                        } else {
                            showingKeyPromptSheet = true
                        }
                    } label: {
                        Label(KeychainManager.hasConfiguredAPIKey ? "Analiză AI (Gemini)" : "Activează AI (Gratuit)", systemImage: "sparkles")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .disabled(isProcessingGeminiAI)
                }
            } else {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 42))
                            .foregroundStyle(.blue)
                        
                        Text("Alege o factură sau chitanță")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Vom extrage automat scadența, furnizorul și suma de plată.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(Color.blue.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Loading State
    private var loadingStateView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(isProcessingGeminiAI ? "Gemini analizează structura facturii..." : "Procesare locală on-device...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Gemini Result
    private func geminiResultSection(_ result: InvoiceOCRResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Extragere Reușită (Gemini)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                labeledInfoRow(label: "Furnizor / Emitent", value: result.merchant)
                if let due = result.dueDate {
                    labeledInfoRow(label: "Dată Scadență", value: due)
                }
                labeledInfoRow(label: "Total de plată", value: "\(String(format: "%.2f", result.totalAmount)) \(result.currency)")
                if let sum = result.summary {
                    labeledInfoRow(label: "Rezumat", value: sum)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.purple.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Local OCR Result
    private func localOCRResultSection(_ result: LocalOCRScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
                Text("Scanare Locală (On-Device Vision)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Spacer()
            }
            
            if let due = result.candidateDueDate {
                labeledInfoRow(label: "Scadență estimată", value: due.formatted(.dateTime.day().month().year()))
            }
            if let tot = result.candidateTotal {
                labeledInfoRow(label: "Sumă detectată", value: "\(String(format: "%.2f", tot)) RON")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
    
    private func labeledInfoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
    }
    
    // MARK: - Save Event Section
    private var saveEventSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirmă Detaliile pentru Salvare")
                .font(.system(.headline, design: .rounded, weight: .bold))
            
            VStack(spacing: 12) {
                TextField("Titlu eveniment / Notă", text: $eventTitle)
                    .textFieldStyle(.roundedBorder)
                
                DatePicker("Dată Scadență", selection: $eventDueDate, displayedComponents: .date)
                
                TextField("Sumă de plată (RON)", text: $eventCost)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Asociază cu un Activ", selection: $selectedAssetId) {
                    Text("Selectează activ...").tag(nil as UUID?)
                    ForEach(assets) { asset in
                        Text(asset.name).tag(asset.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            
            Button {
                saveExtractedEvent()
            } label: {
                Text("Salvează în Dosar")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(eventTitle.isEmpty || selectedAssetId == nil)
        }
    }
    
    // MARK: - Actions
    private func processLoadedImage(_ image: UIImage) async {
        selectedImage = image
        isProcessingLocalOCR = true
        do {
            let res = try await LocalOCRService.shared.scanImage(image)
            await MainActor.run {
                localOCRResult = res
                if let due = res.candidateDueDate {
                    eventDueDate = due
                }
                if let tot = res.candidateTotal {
                    eventCost = String(format: "%.2f", tot)
                }
                eventTitle = "Factură scanată"
                isProcessingLocalOCR = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isProcessingLocalOCR = false
            }
        }
    }
    
    private func runGeminiSweep(image: UIImage) async {
        isProcessingGeminiAI = true
        do {
            let response = try await GeminiService.shared.analyzeDocument(image: image)
            await MainActor.run {
                geminiResult = response
                eventTitle = "\(response.merchant) - \(response.summary ?? "Factură")"
                eventCost = String(format: "%.2f", response.totalAmount)
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                if let dueStr = response.dueDate, let d = formatter.date(from: dueStr) {
                    eventDueDate = d
                }
                
                // Auto-match category if possible
                if let matched = assets.first(where: { $0.categoryRaw == response.categorySuggestion }) {
                    selectedAssetId = matched.id
                }
                isProcessingGeminiAI = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isProcessingGeminiAI = false
            }
        }
    }
    
    private func saveExtractedEvent() {
        guard let assetId = selectedAssetId,
              let matchedAsset = assets.first(where: { $0.id == assetId }) else { return }
        
        let costVal = Double(eventCost.replacingOccurrences(of: ",", with: "."))
        let newEvent = LifecycleEvent(
            title: eventTitle,
            dueDate: eventDueDate,
            cost: costVal
        )
        newEvent.asset = matchedAsset
        
        if let img = selectedImage, let data = img.jpegData(compressionQuality: 0.7) {
            let attachment = DocumentAttachment(
                fileName: "scan_\(Int(Date().timeIntervalSince1970)).jpg",
                fileExtension: "jpg",
                fileData: data,
                extractedText: localOCRResult?.rawText
            )
            attachment.event = newEvent
            attachment.asset = matchedAsset
            modelContext.insert(attachment)
        }
        
        modelContext.insert(newEvent)
        dismiss()
    }
}
