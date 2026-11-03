import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Copie de siguranță

/// Export to a `.dosar` file through the share sheet (the temporary file is
/// removed once sharing ends), with or without a password, and import one back,
/// asking before anything is replaced. What happens is decided in `BackupFlow`.
struct BackupSettings: View {
    @Environment(\.modelContext) private var context
    @Environment(BiometricVaultManager.self) private var vault

    static let dossierType = UTType(exportedAs: "com.ar.dosarcusina.dossier", conformingTo: .zip)

    var body: some View {
        BackupSection(container: context.container, vault: vault)
    }
}

private struct BackupSection: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(BiometricVaultManager.self) private var vault

    @State private var flow: BackupFlow
    @State private var isChoosingPassword = false
    /// What the password sheet chose; the export starts once the sheet has gone.
    @State private var exportChoice: ExportChoice?
    @State private var isPickingFile = false
    /// What is typed in the prompt for a backup's password.
    @State private var password = ""

    private enum ExportChoice {
        case plain
        case protected(String)
    }

    init(container: ModelContainer, vault: BiometricVaultManager) {
        _flow = State(initialValue: BackupFlow(container: container, vault: vault))
    }

    var body: some View {
        Section {
            Button {
                isChoosingPassword = true
            } label: {
                HStack {
                    Label { Text("Fă o copie de siguranță", comment: "Exports a backup.") } icon: { Image(systemName: "square.and.arrow.up") }
                    Spacer()
                    if flow.work == .exporting { DSDelayedProgress(label: "Se pregătește…") }
                }
                .frame(minHeight: 44)
            }
            .disabled(flow.work != nil)
            Button {
                isPickingFile = true
            } label: {
                HStack {
                    Label { Text("Pune înapoi o copie", comment: "Imports a backup.") } icon: { Image(systemName: "square.and.arrow.down") }
                    Spacer()
                    if flow.work == .reading { DSDelayedProgress(label: "Se citește…") }
                    if flow.work == .importing { DSDelayedProgress(label: "Se pune înapoi…") }
                }
                .frame(minHeight: 44)
            }
            .disabled(flow.work != nil)
            if let resultText = flow.resultText {
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
            Text("Copia e un singur fișier cu tot dosarul, inclusiv documentele. Păstreaz-o în Fișiere, pe iCloud Drive sau trimite-o pe alt telefon. Codurile PIN și rândurile secrete nu intră în copie: rămân doar pe acest telefon.", comment: "Footer of the backup section.")
        }
        .sheet(isPresented: $isChoosingPassword, onDismiss: startChosenExport) {
            BackupPasswordSheet { password in
                exportChoice = password.map(ExportChoice.protected) ?? .plain
                isChoosingPassword = false
            }
        }
        .sheet(item: Binding(get: { flow.exportURL.map(ShareItem.init) }, set: { if $0 == nil { flow.finishSharing() } })) { item in
            ShareSheet(url: item.url) { flow.finishSharing() }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [BackupSettings.dossierType, .zip, .data]) { result in
            switch result {
            case .success(let url): Task { await flow.open(url) }
            case .failure(let failure): flow.error = UserFacingError(failure)
            }
        }
        .alert(
            Text("Copia are parolă", comment: "Title of the prompt for a backup's password."),
            isPresented: Binding(get: { flow.lockedFile != nil }, set: { if !$0 { flow.lockedFile = nil } }),
            presenting: flow.lockedFile
        ) { file in
            SecureField(text: $password) { Text("Parola copiei", comment: "Placeholder of a backup's password.") }
                .textContentType(.password)
            Button {
                let typed = password
                password = ""
                Task { await flow.unlock(file, with: typed) }
            } label: {
                Text("Deschide", comment: "Opens a password-protected backup.")
            }
            Button(role: .cancel) {
                password = ""
                flow.discard(file.url)
            } label: {
                Text("Nu acum", comment: "Cancels an optional action.")
            }
        } message: { file in
            if file.wasWrong {
                Text("Parola nu deschide copia. Verifică literele mari și mici și încearcă din nou.", comment: "A backup's password was wrong.")
            } else {
                Text("Scrie parola pe care ai ales-o când ai făcut copia.", comment: "Asks for a backup's password.")
            }
        }
        .confirmationDialog(Text("Pui înapoi copia?", comment: "Import confirmation title."), isPresented: Binding(get: { flow.pending != nil }, set: { if !$0 { flow.pending = nil } }), titleVisibility: .visible, presenting: flow.pending) { pending in
            Button { Task { await flow.runImport(pending, mode: .merge) } } label: {
                Text("Adaug-o la ce am acum", comment: "Import mode: merge.")
            }
            Button(role: .destructive) { Task { await flow.runImport(pending, mode: .replace) } } label: {
                Text("Înlocuiește tot ce e aici", comment: "Import mode: replace.")
            }
            Button(role: .cancel) { flow.discard(pending.url) } label: { Text("Nu acum", comment: "Cancels an optional action.") }
        } message: { pending in
            Text(verbatim: BackupWording.summary(pending.summary) + " " + String(localized: "Dacă alegi „Înlocuiește”, ce ai acum pe telefon se șterge și rămâne doar ce e în copie. Codurile PIN de pe acest telefon rămân.", comment: "Warning before replacing everything with a backup."))
        }
        .task { consumeOpenedFile() }
        .onChange(of: navigator.pendingArchiveURL) { _, _ in consumeOpenedFile() }
        .onChange(of: vault.isAppLocked) { _, _ in consumeOpenedFile() }
        .sensoryFeedback(.success, trigger: flow.doneCount)
        .userErrorAlert(Binding(get: { flow.error }, set: { flow.error = $0 }))
    }

    private func startChosenExport() {
        guard let choice = exportChoice else { return }
        exportChoice = nil
        switch choice {
        case .plain: Task { await flow.export(password: nil) }
        case .protected(let password): Task { await flow.export(password: password) }
        }
    }

    private func consumeOpenedFile() {
        guard let url = navigator.consumeArchiveURL() else { return }
        Task { await flow.open(url) }
    }
}

/// Before a backup: an optional password. With one, the copy can't be opened
/// without it; without one, it is an ordinary file to keep somewhere safe.
private struct BackupPasswordSheet: View {
    let onExport: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""

    private var rule: BackupPasswordRule { BackupPasswordRule(password: password, repeated: repeated) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    Label {
                        Text("Copia conține tot dosarul, inclusiv actele de identitate și pozele lor. Codurile PIN și codurile secrete nu intră în ea.", comment: "What a backup contains, said before every backup.")
                    } icon: {
                        Image(systemName: "doc.on.doc.fill").foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    .dsFont(.body)
                    Text("Cu o parolă, copia nu se poate deschide fără ea, nici dacă fișierul ajunge la altcineva.", comment: "Explains a backup password.")
                        .dsFont(.body)
                    VStack(spacing: DS.Space.s) {
                        DSSecureField("Parolă", text: $password, contentType: .newPassword, validation: rule.passwordValidation)
                        DSSecureField("Scrie parola din nou", text: $repeated, contentType: .newPassword, validation: rule.repeatValidation)
                    }
                    Label {
                        Text("Dacă uiți parola, copia nu mai poate fi deschisă de nimeni. Pune-o undeva sigur, de exemplu în Parole.", comment: "Warning: a forgotten backup password can't be recovered.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DSStatus.soon.color)
                    }
                    .dsFont(.footnote)
                    VStack(spacing: DS.Space.s) {
                        DSPrimaryButton("Fă copia cu parolă", systemImage: "lock.fill") { onExport(password) }
                            .disabled(!rule.isReady)
                        DSSecondaryButton("Fă copia fără parolă") { onExport(nil) }
                    }
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.background)
            .navigationTitle(Text("Copie de siguranță", comment: "Settings section."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Anulează", comment: "Cancels.") }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// When a backup password can be used: long enough, and typed the same twice.
struct BackupPasswordRule {
    var password: String
    var repeated: String

    var isReady: Bool {
        password.count >= ArchiveEncryption.minimumPasswordLength && password == repeated
    }

    var passwordValidation: DSValidation {
        guard !password.isEmpty, password.count < ArchiveEncryption.minimumPasswordLength else { return .valid }
        return .invalid(LocalizedStringResource("Parola are cel puțin \(ArchiveEncryption.minimumPasswordLength) caractere.", comment: "A backup password is too short."))
    }

    var repeatValidation: DSValidation {
        guard !repeated.isEmpty, repeated != password else { return .valid }
        return .invalid(LocalizedStringResource("Parolele nu se potrivesc.", comment: "The two backup passwords differ."))
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
        let done = String(localized: "Copia e pusă înapoi. Noi: \(result.inserted). Actualizate: \(result.updated).", comment: "After importing a backup.")
        guard result.movedToTop > 0 else { return done }
        return done + " " + String(localized: "\(result.movedToTop) secțiuni nu și-au găsit locul din copie și sunt acum direct în dosar.", comment: "After importing a backup: sections whose parent couldn't be used, with Romanian plural forms.")
    }
}

/// The temporary export file is removed as soon as the share sheet closes.
enum BackupFiles {
    @discardableResult
    static func remove(_ url: URL) -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }

    /// Whether a file sits inside a folder (the app's Inbox, say).
    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let file = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parent = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return file.count > parent.count && Array(file.prefix(parent.count)) == parent
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
