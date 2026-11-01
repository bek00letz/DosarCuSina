import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Gemini BYOK State
    @State private var apiKeyInput: String = ""
    @State private var isKeySaved: Bool = false
    @State private var isValidatingKey: Bool = false
    @State private var validationSuccess: Bool? = nil
    @State private var showingSaveAlert: Bool = false
    @State private var showingDeleteAlert: Bool = false
    
    // Archive (.dosar) Export & Import State
    @State private var isExportingArchive: Bool = false
    @State private var exportedArchiveURL: URL? = nil
    @State private var exportErrorMessage: String? = nil
    @State private var isShowingFileImporter: Bool = false
    @State private var inspectionSummary: ArchiveInspectionSummary? = nil
    @State private var selectedImportMode: ArchiveImportMode = .merge
    @State private var isImporting: Bool = false
    @State private var importResult: ArchiveImportResult? = nil
    @State private var importErrorMessage: String? = nil
    @State private var showingCleanRestoreConfirmAlert: Bool = false
    
    // Demo Data Management State
    @AppStorage("didSeedInitialDemoData") private var didSeedInitialDemoData: Bool = false
    @State private var showingResetDemoConfirmAlert: Bool = false
    @State private var isResettingDemoData: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section: Status Banner
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: isKeySaved ? "sparkles" : "bolt.shield.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isKeySaved ? .purple : .blue)
                            .frame(width: 48, height: 48)
                            .background((isKeySaved ? Color.purple : Color.blue).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isKeySaved ? "Modul Inteligent AI Activ" : "Modul Standard (On-Device)")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                            
                            Text(isKeySaved ? "Extragere automată avansată cu Gemini 2.0 Flash." : "Scanare 100% locală prin Apple Vision. Fără internet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Section: Gemini AI API Key (BYOK)
                Section {
                    SecureField(isKeySaved ? "Cheie configurată (••••••••)" : "Introdu cheia API Gemini", text: $apiKeyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    if let success = validationSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(success ? .green : .red)
                            Text(success ? "Cheia este validă și funcțională!" : "Cheia nu a putut fi verificată. Verifică caracterele.")
                                .font(.caption)
                                .foregroundStyle(success ? .green : .red)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            Task { await validateAndSaveKey() }
                        } label: {
                            HStack(spacing: 6) {
                                if isValidatingKey {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text("Salvează & Verifică")
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
                        
                        Spacer()
                        
                        if isKeySaved {
                            Button("Șterge", role: .destructive) {
                                deleteKey()
                            }
                            .font(.subheadline)
                        }
                    }
                    
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        HStack {
                            Text("Obține o cheie gratuită pe Google AI Studio")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(.purple)
                    }
                } header: {
                    Text("Configurare Cheie Gemini API (BYOK)")
                } footer: {
                    Text("Aplicația este 100% gratuită. Nu plătești nimic dezvoltatorului. Cheia ta este stocată exclusiv pe telefonul tău în iOS Keychain și apelurile merg direct către Google fără servere intermediare.")
                }
                
                // Section: Arhivă & Portabilitate Date (.dosar)
                Section {
                    // Export Sub-row
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                                .frame(width: 32, height: 32)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exportă Dosar Complet (.dosar)")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                Text("Include opis.pdf, JSON-uri și atașamente.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if isExportingArchive {
                                ProgressView()
                                    .controlSize(.small)
                            } else if let exportURL = exportedArchiveURL {
                                ShareLink(item: exportURL) {
                                    Label("Partajează", systemImage: "square.and.arrow.up")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button("Generează") {
                                    Task { await generateArchive() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        if let error = exportErrorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Import Sub-row
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                            .frame(width: 32, height: 32)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Importă Arhivă (.dosar)")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Text("Restaurează sau îmbină date de pe iOS/Android.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Alege Fișier") {
                            isShowingFileImporter = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Arhivă & Portabilitate Date (.dosar)")
                } footer: {
                    Text("Formatul deschis .dosar permite backup-ul complet și transferul facil al tuturor bunurilor, scanărilor și termenelor între iOS și Android, garantând integritate criptografică SHA-256.")
                }
                
                // Section: Gestiune Date Demonstrative
                Section {
                    Button(role: .destructive) {
                        showingResetDemoConfirmAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.orange)
                                .frame(width: 32, height: 32)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reîncarcă Date Demonstrative")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Resetează cele 8 active demonstrative românești.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if isResettingDemoData {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isResettingDemoData)
                } header: {
                    Text("Gestiune Date Demonstrative")
                } footer: {
                    Text("Înlocuiește baza de date cu exemple curate și conforme pentru toate cele 8 domenii (Casă, Auto, Sănătate, Pet, Documente, Garanții, Abonamente, Chiriaș).")
                }
                
                // Section: Comparativ Funcționalități
                Section("Ce oferă fiecare mod") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .font(.caption.weight(.bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scanare Standard (Gratuită, Fără Cheie)")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                Text("Decupare unghiuri cameră, OCR local, detectare date și sume de bază.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                                .font(.caption.weight(.bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scanare Pro AI (Cu Cheia Ta Gemini)")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                Text("Identificare automată furnizor, scadență, sumă exactă, rezumat servicii și alocare automată pe activ.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Section: Sincronizare & Securitate
                Section("Confidențialitate & Stocare") {
                    HStack {
                        Label("Sincronizare iCloud", systemImage: "icloud.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Text("CloudKit Privat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Stocare Date", systemImage: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("100% Pe Dispozitiv")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Section: Despre Aplicație
                Section("Despre") {
                    HStack {
                        Text("Aplicație")
                        Spacer()
                        Text("Dosar cu Șină")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Format Arhivă")
                        Spacer()
                        Text("Open Package (.dosar / v2)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Model de Distribuție")
                        Spacer()
                        Text("Free & Open Source")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Versiune")
                        Spacer()
                        Text("2.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Setări")
            .onAppear {
                checkKeyStatus()
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: allowedArchiveTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImportSelection(result)
            }
            .sheet(item: Binding<ArchiveInspectionSummary?>(
                get: { inspectionSummary },
                set: { inspectionSummary = $0 }
            )) { summary in
                archiveConfirmationSheet(summary: summary)
            }
            .alert("Cheie Salvată", isPresented: $showingSaveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Cheia Gemini API este activă și securizată în Keychain.")
            }
            .alert("Cheie Eliminată", isPresented: $showingDeleteAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Aplicația a revenit la modul de scanare exclusiv local (Apple Vision).")
            }
            .alert("Import Finalizat cu Succes", isPresented: Binding<Bool>(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            )) {
                Button("Excelent", role: .cancel) {}
            } message: {
                if let res = importResult {
                    Text("Datele au fost restaurate cu succes!\n\n• Bunuri: \(res.assetsImported) adăugate, \(res.assetsUpdated) actualizate\n• Evenimente: \(res.eventsImported) adăugate, \(res.eventsUpdated) actualizate\n• Intervenții Service: \(res.serviceItemsImported)\n• Măsurători: \(res.measurementsImported)\n• Atașamente / Scanări: \(res.attachmentsImported)")
                }
            }
            .alert("Eroare la Import", isPresented: Binding<Bool>(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("Închide", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "A apărut o eroare necunoscută.")
            }
            .alert("Confirmare Resetare Date Demo", isPresented: $showingResetDemoConfirmAlert) {
                Button("Anulează", role: .cancel) {}
                Button("Resetează & Reîncarcă", role: .destructive) {
                    isResettingDemoData = true
                    Task { @MainActor in
                        try? DemoDataSeeder.resetAndReseed(context: modelContext)
                        didSeedInitialDemoData = true
                        isResettingDemoData = false
                        #if canImport(UIKit)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif
                    }
                }
            } message: {
                Text("Ești sigur că vrei să resetezi datele? Toate activele și jurnalele curente vor fi înlocuite cu exemplele demonstrative.")
            }
        }
    }
    
    private var allowedArchiveTypes: [UTType] {
        var types: [UTType] = [.zip]
        if let dosarType = UTType(filenameExtension: "dosar") {
            types.append(dosarType)
        }
        return types
    }
    
    // MARK: - Archive Confirmation Sheet
    
    @ViewBuilder
    private func archiveConfirmationSheet(summary: ArchiveInspectionSummary) -> some View {
        NavigationStack {
            Form {
                Section("Detalii Arhivă (.dosar)") {
                    HStack {
                        Text("Data Exportului")
                        Spacer()
                        Text(DateFormatter.localizedString(from: summary.manifest.exportDate, dateStyle: .medium, timeStyle: .short))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Platformă Sursă")
                        Spacer()
                        Text(summary.manifest.platform)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Bunuri / Active")
                        Spacer()
                        Text("\(summary.manifest.entityCounts.assets)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Obligații & Termene")
                        Spacer()
                        Text("\(summary.manifest.entityCounts.events)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Documente & Scanări")
                        Spacer()
                        Text("\(summary.manifest.entityCounts.attachments)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Verificare Integritate SHA-256")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: summary.isValidIntegrity ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(summary.isValidIntegrity ? .green : .red)
                            Text(summary.isValidIntegrity ? "Autentic & Valid" : "Corupt sau modificat")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(summary.isValidIntegrity ? .green : .red)
                        }
                    }
                }
                
                Section("Selectează Modul de Import") {
                    Picker("Mod de Import", selection: $selectedImportMode) {
                        ForEach(ArchiveImportMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if selectedImportMode == .merge {
                        Text("Modul Îmbinare (Merge) adaugă elementele noi și le actualizează pe cele existente doar dacă arhiva conține date mai recente. Datele tale locale sunt păstrate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Atenție: Restaurarea Curată (Clean Restore) va șterge toate datele locale existente și va aduce baza de date exact în starea din arhivă.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                Section {
                    Button {
                        if selectedImportMode == .cleanRestore {
                            showingCleanRestoreConfirmAlert = true
                        } else {
                            executeImport(summary: summary)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isImporting {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(selectedImportMode == .cleanRestore ? "Restaurează Curat (Șterge & Înlocuiește)" : "Îmbină cu Datele Existente")
                                .fontWeight(.semibold)
                                .foregroundStyle(selectedImportMode == .cleanRestore ? .red : .blue)
                            Spacer()
                        }
                    }
                    .disabled(isImporting || !summary.isValidIntegrity)
                }
            }
            .navigationTitle("Confirmare Import Arhivă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        inspectionSummary = nil
                    }
                }
            }
            .alert("Confirmare Restaurare Curată", isPresented: $showingCleanRestoreConfirmAlert) {
                Button("Anulează", role: .cancel) {}
                Button("Șterge & Restaurează", role: .destructive) {
                    executeImport(summary: summary)
                }
            } message: {
                Text("Ești sigur că vrei să ștergi toate înregistrările locale actuale și să restaurezi baza de date din arhivă?")
            }
        }
    }
    
    // MARK: - Actions
    
    private func generateArchive() async {
        isExportingArchive = true
        exportErrorMessage = nil
        exportedArchiveURL = nil
        
        do {
            let url = try DossierArchiveService.shared.exportHouseholdArchive(context: modelContext)
            exportedArchiveURL = url
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } catch {
            exportErrorMessage = error.localizedDescription
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
        isExportingArchive = false
    }
    
    private func handleFileImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            let shouldStopAccessing = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let summary = try DossierArchiveService.shared.inspectArchive(at: selectedURL)
                self.inspectionSummary = summary
            } catch {
                self.importErrorMessage = "Fișierul selectat nu este o arhivă .dosar validă: \(error.localizedDescription)"
            }
            
        case .failure(let error):
            self.importErrorMessage = "Eroare la selectarea fișierului: \(error.localizedDescription)"
        }
    }
    
    private func executeImport(summary: ArchiveInspectionSummary) {
        isImporting = true
        let mode = selectedImportMode
        let fileURL = summary.fileURL
        
        Task { @MainActor in
            do {
                let result = try DossierArchiveService.shared.importArchive(
                    at: fileURL,
                    mode: mode,
                    context: modelContext
                )
                self.inspectionSummary = nil
                self.importResult = result
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            } catch {
                self.importErrorMessage = error.localizedDescription
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                #endif
            }
            self.isImporting = false
        }
    }
    
    private func checkKeyStatus() {
        if let key = KeychainManager.getGeminiAPIKey(), !key.isEmpty {
            isKeySaved = true
            apiKeyInput = ""
        } else {
            isKeySaved = false
            apiKeyInput = ""
        }
    }
    
    private func validateAndSaveKey() async {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isValidatingKey = true
        validationSuccess = nil
        
        let isValid = await GeminiService.shared.validateAPIKey(trimmed)
        isValidatingKey = false
        validationSuccess = isValid
        
        if isValid {
            if KeychainManager.saveGeminiAPIKey(trimmed) {
                isKeySaved = true
                apiKeyInput = ""
                showingSaveAlert = true
            }
        }
    }
    
    private func deleteKey() {
        if KeychainManager.deleteGeminiAPIKey() {
            isKeySaved = false
            apiKeyInput = ""
            validationSuccess = nil
            showingDeleteAlert = true
        }
    }
}

// Conform ArchiveInspectionSummary to Identifiable for .sheet(item:)
extension ArchiveInspectionSummary: Identifiable {
    public var id: String { manifest.deviceId + "\(manifest.exportDate.timeIntervalSince1970)" }
}
