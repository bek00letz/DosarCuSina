import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Copie de siguranță

/// Export to a `.dosar` file through the share sheet (the temporary file is
/// removed once sharing ends) and import one back, asking before anything is replaced.
struct BackupSettings: View {
    @Environment(\.modelContext) private var context
    @Environment(AppNavigator.self) private var navigator

    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isPickingFile = false
    @State private var pending: PendingImport?
    @State private var resultText: String?
    @State private var error: UserFacingError?
    @State private var doneCount = 0

    struct PendingImport: Identifiable {
        let id = UUID()
        let data: Data
        let summary: ArchiveSummary
    }

    static let dossierType = UTType(exportedAs: "com.ar.dosarcusina.dossier", conformingTo: .zip)

    var body: some View {
        Section {
            Button(action: export) {
                HStack {
                    Label { Text("Fă o copie de siguranță", comment: "Exports a backup.") } icon: { Image(systemName: "square.and.arrow.up") }
                    Spacer()
                    if isExporting { DSDelayedProgress(label: "Se pregătește…") }
                }
                .frame(minHeight: 44)
            }
            .disabled(isExporting)
            Button {
                isPickingFile = true
            } label: {
                Label { Text("Pune înapoi o copie", comment: "Imports a backup.") } icon: { Image(systemName: "square.and.arrow.down") }
                    .frame(minHeight: 44)
            }
            if let resultText {
                Label {
                    Text(verbatim: resultText)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DSStatus.done.color)
                }
                .dsFont(.footnote)
            }
        } header: {
            Text("Copie de siguranță", comment: "Settings section.")
        } footer: {
            Text("Copia e un singur fișier cu tot dosarul, inclusiv documentele. Păstreaz-o în Fișiere, pe iCloud Drive sau trimite-o pe alt telefon. Codurile PIN nu intră în copie: rămân doar pe acest telefon.", comment: "Footer of the backup section.")
        }
        .sheet(item: Binding(get: { exportURL.map(ShareItem.init) }, set: { if $0 == nil { exportURL = nil } })) { item in
            ShareSheet(url: item.url) {
                BackupFiles.remove(item.url)
                exportURL = nil
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [Self.dossierType, .zip, .data]) { result in
            switch result {
            case .success(let url): prepareImport(from: url, isSecurityScoped: true)
            case .failure(let failure): error = UserFacingError(failure)
            }
        }
        .confirmationDialog(Text("Pui înapoi copia?", comment: "Import confirmation title."), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { pending in
            Button { runImport(pending, mode: .merge) } label: {
                Text("Adaug-o la ce am acum", comment: "Import mode: merge.")
            }
            Button(role: .destructive) { runImport(pending, mode: .replace) } label: {
                Text("Înlocuiește tot ce e aici", comment: "Import mode: replace.")
            }
            Button(role: .cancel) {} label: { Text("Nu acum", comment: "Cancels an optional action.") }
        } message: { pending in
            Text(verbatim: BackupWording.summary(pending.summary) + " " + String(localized: "Dacă alegi „Înlocuiește”, ce ai acum pe telefon se șterge și rămâne doar ce e în copie.", comment: "Warning before replacing everything with a backup."))
        }
        .task { consumeOpenedFile() }
        .onChange(of: navigator.pendingArchiveURL) { _, _ in consumeOpenedFile() }
        .sensoryFeedback(.success, trigger: doneCount)
        .userErrorAlert($error)
    }

    private func export() {
        isExporting = true
        Task {
            // Let the button show it is working before the export takes the main thread.
            try? await Task.sleep(for: .milliseconds(50))
            defer { isExporting = false }
            do {
                exportURL = try DossierArchiveService(container: context.container).export()
            } catch {
                self.error = UserFacingError(error, doing: String(localized: "Copia nu s-a făcut", comment: "Title of an export error."))
            }
        }
    }

    private func consumeOpenedFile() {
        if let url = navigator.consumeArchiveURL() {
            prepareImport(from: url, isSecurityScoped: false)
        }
    }

    private func prepareImport(from url: URL, isSecurityScoped: Bool) {
        let accessing = isSecurityScoped && url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let summary = try DossierArchiveService(container: context.container).inspect(data)
            pending = PendingImport(data: data, summary: summary)
        } catch {
            self.error = UserFacingError(error, doing: String(localized: "Copia nu se deschide", comment: "Title of an import error."))
        }
    }

    private func runImport(_ pending: PendingImport, mode: ArchiveImportMode) {
        do {
            let result = try DossierArchiveService(container: context.container).importArchive(pending.data, mode: mode)
            resultText = BackupWording.result(result)
            doneCount += 1
        } catch {
            self.error = UserFacingError(error, doing: String(localized: "Copia nu s-a pus înapoi", comment: "Title of an import error."))
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Plain-language lines for the backup screen.
enum BackupWording {
    static func summary(_ summary: ArchiveSummary, locale: Locale = .dosarDefault) -> String {
        let counts = [
            String(localized: "\(summary.counts.assets) secțiuni", comment: "A number of sections, with Romanian plural forms."),
            String(localized: "\(summary.counts.obligations) termene", comment: "A number of obligations, with Romanian plural forms."),
            StorageWording.documents(summary.counts.attachments),
        ].formatted(.list(type: .and).locale(locale))
        return String(localized: "Copia e din \(DosarFormat.day(summary.exportedAt, locale: locale)) și are \(counts).", comment: "Backup summary before importing.")
    }

    static func result(_ result: ArchiveImportResult) -> String {
        String(localized: "Copia e pusă înapoi. Noi: \(result.inserted). Actualizate: \(result.updated).", comment: "After importing a backup.")
    }
}

/// The temporary export file is removed as soon as the share sheet closes.
enum BackupFiles {
    @discardableResult
    static func remove(_ url: URL) -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}

/// The system share sheet for one file, reporting when it closes.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: @MainActor () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onFinish() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Inteligență artificială

/// The optional Gemini key: pasted here, kept only in this phone's Keychain,
/// tested on request. Everything in the app works without it.
struct AISettings: View {
    @State private var key = ""
    @State private var hasKey = KeychainManager.hasConfiguredAPIKey
    @State private var status: GeminiKeyStatus?
    @State private var isTesting = false

    var body: some View {
        Section {
            if hasKey {
                Label {
                    Text("Ai pus o cheie Google", comment: "AI setting: a key is saved.")
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(DS.Palette.accent)
                }
                .frame(minHeight: 44)
                Button(action: testSaved) {
                    HStack {
                        Text("Verifică cheia", comment: "Tests the saved Gemini key.")
                        Spacer()
                        if isTesting { DSDelayedProgress(label: "Verific…") }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isTesting)
                Button(role: .destructive) {
                    KeychainManager.deleteGeminiAPIKey()
                    hasKey = KeychainManager.hasConfiguredAPIKey
                    status = nil
                } label: {
                    Text("Șterge cheia", comment: "Removes the Gemini key.")
                        .frame(minHeight: 44)
                }
            } else {
                Text("Cu o cheie Google gratuită, aplicația citește mai bine facturile și actele scanate. Fără ea, scanarea merge la fel, direct pe telefon.", comment: "Explains the optional Gemini key.")
                    .dsFont(.subheadline)
                    .padding(.vertical, DS.Space.xxs)
                if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                    Link(destination: url) {
                        Text("Ia o cheie de la Google", comment: "Link to get a Gemini key.")
                            .frame(minHeight: 44)
                    }
                }
                DSSecureField("Cheia ta Google", text: $key, prompt: "Lipește cheia aici")
                    .listRowSeparator(.hidden)
                Button(action: saveAndTest) {
                    HStack {
                        Text("Salvează și verifică", comment: "Saves and tests a Gemini key.")
                        Spacer()
                        if isTesting { DSDelayedProgress(label: "Verific…") }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)
            }
            if let status, let message = AIKeyWording.message(status) {
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: status == .valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status == .valid ? DSStatus.done.color : DSStatus.soon.color)
                }
                .dsFont(.footnote)
                .transition(.opacity)
            }
        } header: {
            Text("Inteligență artificială (opțional)", comment: "Settings section.")
        } footer: {
            Text("Cheia stă doar pe acest telefon. Documentele trimise spre citire ajung la Google doar când folosești cheia.", comment: "Footer of the AI section.")
        }
        .sensoryFeedback(trigger: status) { _, new in
            switch new {
            case .valid?: .success
            case nil: nil
            default: .warning
            }
        }
    }

    private func saveAndTest() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard KeychainManager.saveGeminiAPIKey(trimmed) else {
            status = .unavailable
            return
        }
        key = ""
        hasKey = true
        testSaved()
    }

    private func testSaved() {
        guard let saved = KeychainManager.getGeminiAPIKey() else { hasKey = false; return }
        isTesting = true
        Task {
            status = await GeminiService.shared.checkAPIKey(saved)
            isTesting = false
        }
    }
}

/// What the key test result means, and what to do next.
enum AIKeyWording {
    static func message(_ status: GeminiKeyStatus) -> String? {
        switch status {
        case .valid:
            String(localized: "Cheia merge. Documentele scanate vor fi citite mai bine.", comment: "Gemini key test: valid.")
        case .empty:
            nil
        case .invalidKey:
            String(localized: "Google nu a acceptat cheia. Verifică dacă ai copiat-o întreagă.", comment: "Gemini key test: rejected.")
        case .offline:
            String(localized: "Nu ești conectat la internet. Cheia e salvată; o verificăm când revine conexiunea. Scanarea locală merge în continuare.", comment: "Gemini key test: offline.")
        case .rateLimited:
            String(localized: "Google e ocupat sau cheia și-a terminat cererile gratuite pe azi. Încearcă mai târziu.", comment: "Gemini key test: rate limited.")
        case .unavailable:
            String(localized: "Google nu a răspuns cum trebuie. Încearcă din nou peste câteva minute.", comment: "Gemini key test: unexpected answer.")
        }
    }
}
