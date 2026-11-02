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

/// The optional AI provider: which service, its key (kept only in this phone's Keychain,
/// one per provider), an optional model and, for a compatible service, its address.
/// Tested on request. Everything in the app works without it.
struct AISettings: View {
    private let settings = AIProviderSettings.standard

    @State private var provider = AIProviderSettings.standard.provider
    @State private var key = ""
    @State private var hasKey = false
    @State private var model = ""
    @State private var baseURL = ""
    @State private var status: AIKeyStatus?
    @State private var isTesting = false
    @State private var readsAutomatically = AIProviderSettings.standard.readsAutomaticallyWhenUnsure

    var body: some View {
        Section {
            Picker(selection: $provider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(verbatim: provider.pickerName).tag(provider)
                }
            } label: {
                Text("Serviciul", comment: "AI setting: which AI service reads documents.")
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)

            if hasKey {
                Label {
                    Text("Ai pus o cheie pentru \(provider.pickerName)", comment: "AI setting: a key is saved for the chosen service.")
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(DS.Palette.accent)
                }
                .frame(minHeight: 44)
                Button(role: .destructive) {
                    settings.deleteKey(for: provider)
                    reload()
                } label: {
                    Text("Șterge cheia", comment: "Removes the AI key.")
                        .frame(minHeight: 44)
                }
            } else {
                Text("Cu o cheie proprie, aplicația citește mai bine facturile și actele scanate. Fără ea, scanarea merge la fel, direct pe telefon.", comment: "Explains the optional AI key.")
                    .dsFont(.subheadline)
                    .padding(.vertical, DS.Space.xxs)
                if let url = provider.keyPageURL {
                    Link(destination: url) {
                        Text("Ia o cheie de la \(provider.pickerName)", comment: "Link to get a key from the chosen AI service.")
                            .frame(minHeight: 44)
                    }
                }
                DSSecureField(provider.requiresKey ? "Cheia ta" : "Cheia ta (dacă serviciul cere)", text: $key, prompt: "Lipește cheia aici")
                    .listRowSeparator(.hidden)
            }

            if provider == .openAICompatible {
                DSTextField("Adresa serviciului", text: $baseURL, kind: .url, prompt: "https://…/v1",
                            footnote: "Pe rețeaua de acasă merge și http://, de exemplu un server LM Studio.")
            }
            NavigationLink {
                AIModelPicker(provider: provider, model: $model)
            } label: {
                LabeledContent {
                    Text(verbatim: AIModelPicker.summary(model: model, provider: provider))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } label: {
                    Text("Model", comment: "AI setting: which model of the service reads documents.")
                }
                .frame(minHeight: 44)
            }

            if hasKey || !provider.requiresKey {
                Toggle(isOn: $readsAutomatically) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Citește automat când nu sunt sigur", comment: "AI setting: read with the AI provider by itself after a weak phone reading.")
                        Text("Dacă telefonul nu citește sigur un act, îl trimite singur la \(provider.name), cu cheia ta.", comment: "Explains the automatic AI reading. The argument is the provider.")
                            .dsFont(.footnote)
                    }
                }
                .frame(minHeight: 44)
                .onChange(of: readsAutomatically) { _, new in settings.readsAutomaticallyWhenUnsure = new }
            }

            Button(action: saveAndTest) {
                HStack {
                    Text(hasKey || key.isEmpty ? "Testează" : "Salvează și testează", comment: "Saves and tests the AI settings.")
                    Spacer()
                    if isTesting { DSDelayedProgress(label: "Verific…") }
                }
                .frame(minHeight: 44)
            }
            .disabled(isTesting || (provider.requiresKey && !hasKey && key.trimmingCharacters(in: .whitespaces).isEmpty))

            if let status, let message = AIKeyWording.message(status, provider: provider) {
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: status == .valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status == .valid ? DSStatus.done.color : DSStatus.soon.color)
                }
                .dsFont(.footnote)
                .transition(.opacity)
            }

            if let policy = provider.dataPolicyURL {
                Link(destination: policy) {
                    Text("Cum folosește \(provider.name) ce trimiți", comment: "Link to the AI provider's data-use terms.")
                        .frame(minHeight: 44)
                }
            } else {
                Text("Serviciul ales are regulile lui pentru ce trimiți. Citește-le înainte să trimiți acte.", comment: "Note for a custom AI service.")
                    .dsFont(.footnote)
            }
        } header: {
            Text("Inteligență artificială (opțional)", comment: "Settings section.")
        } footer: {
            Text("Cheile stau doar pe acest telefon. Un act ajunge la serviciul ales doar când apeși „Citește mai bine” pe el sau, dacă alegi mai sus, când telefonul nu e sigur ce a citit.", comment: "Footer of the AI section.")
        }
        .onAppear(perform: reload)
        .onChange(of: provider) { _, new in
            settings.provider = new
            reload()
        }
        .sensoryFeedback(trigger: status) { _, new in
            switch new {
            case .valid?: .success
            case nil: nil
            default: .warning
            }
        }
    }

    /// The chosen provider's saved state.
    private func reload() {
        key = ""
        status = nil
        hasKey = settings.key(for: provider) != nil
        model = settings.customModel(for: provider)
        baseURL = settings.baseURLText
    }

    private func saveAndTest() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard settings.saveKey(trimmed, for: provider) else {
                status = .failed(.badResponse)
                return
            }
            key = ""
            hasKey = true
        }
        settings.setCustomModel(model, for: provider)
        if provider == .openAICompatible { settings.baseURLText = baseURL }
        guard let config = settings.config(for: provider) else {
            status = .failed(.notConfigured)
            return
        }
        isTesting = true
        Task {
            status = await AIClient().testKey(config: config)
            isTesting = false
        }
    }
}

/// What the key test result means, and what to do next.
enum AIKeyWording {
    static func message(_ status: AIKeyStatus, provider: AIProvider) -> String? {
        switch status {
        case .valid:
            String(localized: "Cheia merge. Documentele scanate vor fi citite mai bine.", comment: "AI key test: valid.")
        case .empty:
            nil
        case .failed(.notConfigured) where provider == .openAICompatible:
            String(localized: "Scrie adresa serviciului (https://…) și numele modelului.", comment: "AI key test: the compatible service isn't set up.")
        case .failed(let error):
            error.message(provider: provider)
        }
    }
}
