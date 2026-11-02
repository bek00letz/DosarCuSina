import SwiftUI
import SwiftData
import UserNotifications

/// Settings, in plain words. Opens scrolled to a section when a link asks for one.
struct SettingsScreen: View {
    let initialSection: SettingsSection?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    NotificationSettings().id(SettingsSection.notifications)
                    LockSettings().id(SettingsSection.privacy)
                    SectionVisibilitySettings().id(SettingsSection.categories)
                    ExampleSettings().id(SettingsSection.examples)
                    BackupSettings().id(SettingsSection.backup)
                    StorageSettings()
                    AISettings()
                    AboutSettings().id(SettingsSection.about)
                }
                .task {
                    guard let initialSection else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(DS.Motion.standard) { proxy.scrollTo(initialSection, anchor: .top) }
                }
            }
            .navigationTitle(Text("Setări", comment: "Toolbar button that opens settings."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Gata", comment: "Closes an editor and keeps what was typed.") }
                }
            }
        }
    }
}

// MARK: - Notificări

private struct NotificationSettings: View {
    @Environment(\.sideEffects) private var sideEffects
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            switch sideEffects?.reminderAuthorization ?? .notDetermined {
            case .authorized:
                Label {
                    Text("Notificările sunt pornite", comment: "Notification status.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DSStatus.done.color)
                }
            case .denied:
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Label {
                        Text("Notificările sunt oprite", comment: "Notification status.")
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DSStatus.overdue.color)
                    }
                    Text("Fără ele nu îți putem aminti de ITP, RCA sau acte. Le pornești din Setările telefonului.", comment: "Explains why notifications matter.")
                        .dsFont(.footnote)
                }
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Text("Deschide Setările telefonului", comment: "Opens the system notification settings.")
                        .frame(minHeight: 44)
                }
            case .notDetermined:
                Text("Nu ai ales încă dacă primești amintiri.", comment: "Notification status.")
                Button {
                    sideEffects?.setNeedsReconcile(allowPermissionPrompt: true)
                } label: {
                    Text("Pornește notificările", comment: "Asks for notification permission.")
                        .frame(minHeight: 44)
                }
            }
            DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                Text("Ora amintirilor", comment: "Setting: default reminder time.")
            }
            .frame(minHeight: 44)
        } header: {
            Text("Notificări", comment: "Settings section.")
        } footer: {
            Text("Amintirile vin la ora asta, dacă un termen nu are ora lui.", comment: "Footer of the reminder time setting.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sideEffects?.setNeedsReconcile(allowPermissionPrompt: false) }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            let minutes = preferences.reminderMinuteOfDay
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            preferences.reminderMinuteOfDay = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        }
    }
}

// MARK: - Face ID

/// The app lock and the section locks are independent: either can be on alone.
/// Turning a lock off asks for Face ID first, so nobody else can switch it off.
private struct LockSettings: View {
    @Environment(\.modelContext) private var context
    @Environment(BiometricVaultManager.self) private var vault
    @Environment(AppPreferences.self) private var preferences
    @Query(sort: [SortDescriptor(\CategoryTemplate.homeOrder)]) private var templates: [CategoryTemplate]
    @Query private var assets: [Asset]
    @State private var error: UserFacingError?

    var body: some View {
        let used = Set(assets.map(\.templateKey))
        let shown = templates.filter { used.contains($0.key) || BinderLayout.categoryBoxKeys.contains($0.key) || $0.isSensitive }
        Section {
            Toggle(isOn: Binding(get: { preferences.appLockEnabled }, set: setAppLock)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blochează aplicația", comment: "Setting: lock the whole app.")
                    Text("Ceri \(vault.biometryName) la fiecare deschidere.", comment: "Explains the app lock.")
                        .dsFont(.footnote)
                }
            }
            .frame(minHeight: 44)
        } header: {
            Text(verbatim: vault.biometryName)
        }
        Section {
            ForEach(shown) { template in
                Toggle(isOn: Binding(get: { template.isSensitive }, set: { setLock(template, $0) })) {
                    Label { Text(verbatim: template.name) } icon: { Image(systemName: template.symbol).foregroundStyle(template.tintColor) }
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("Secțiuni protejate", comment: "Settings section: per-section locks.")
        } footer: {
            Text("O secțiune protejată se deschide doar cu \(vault.biometryName), chiar dacă aplicația nu e blocată. Restul aplicației merge normal.", comment: "Footer of the section locks.")
        }
        .userErrorAlert($error)
    }

    private func setAppLock(_ isOn: Bool) {
        Task {
            // Only the person who can open the phone changes a lock.
            guard await vault.unlock(reason: String(localized: "Confirmă că ești tu.", comment: "Face ID reason when changing a lock.")) == .success else { return }
            preferences.appLockEnabled = isOn
        }
    }

    private func setLock(_ template: CategoryTemplate, _ isOn: Bool) {
        Task {
            if !isOn, await vault.unlock(reason: String(localized: "Confirmă că ești tu.", comment: "Face ID reason when changing a lock.")) != .success { return }
            do {
                try TemplateStore(context: context).setSensitive(template, isOn)
            } catch {
                self.error = UserFacingError(error)
            }
        }
    }
}

// MARK: - Secțiuni

private struct SectionVisibilitySettings: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\CategoryTemplate.homeOrder)]) private var templates: [CategoryTemplate]
    @State private var layout = BinderLayoutStore.shared
    @State private var error: UserFacingError?

    var body: some View {
        Section {
            ForEach(templates.filter { !BinderLayout.nestedKeys.contains($0.key) }) { template in
                Toggle(isOn: Binding(get: { template.isOnHome }, set: { setOnHome(template, $0) })) {
                    Label { Text(verbatim: template.name) } icon: { Image(systemName: template.symbol).foregroundStyle(template.tintColor) }
                }
                .frame(minHeight: 44)
            }
            Button {
                layout.reset()
            } label: {
                Text("Pune casetele în ordinea de la început", comment: "Resets the order of the home boxes.")
                    .frame(minHeight: 44)
            }
            .disabled(layout.saved.isEmpty)
        } header: {
            Text("Pe ecranul Dosar", comment: "Settings section: which categories show on home.")
        } footer: {
            Text("Ce ascunzi de aici nu se șterge; îl găsești în Caută.", comment: "Footer of the home visibility settings.")
        }
        .userErrorAlert($error)
    }

    private func setOnHome(_ template: CategoryTemplate, _ isOn: Bool) {
        do {
            try TemplateStore(context: context).setOnHome(template, isOn)
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

// MARK: - Exemple

private struct ExampleSettings: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Asset> { $0.isExample }) private var examples: [Asset]
    @State private var isConfirmingRemoval = false
    @State private var error: UserFacingError?
    @State private var doneCount = 0

    var body: some View {
        Section {
            if examples.isEmpty {
                Button(action: load) {
                    Label { Text("Încarcă exemple", comment: "Loads example data.") } icon: { Image(systemName: "sparkles") }
                        .frame(minHeight: 44)
                }
            } else {
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label { Text("Șterge exemplele", comment: "Removes example data.") } icon: { Image(systemName: "trash") }
                        .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Exemple", comment: "Settings section.")
        } footer: {
            Text("Exemplele arată cum arată un dosar plin. Sunt marcate „Exemplu”, nu trimit amintiri și pleacă dintr-o atingere. Ce ai adăugat tu rămâne.", comment: "Footer of the examples setting.")
        }
        .confirmationDialog(Text("Ștergi exemplele?", comment: "Confirmation title."), isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button(role: .destructive, action: remove) { Text("Șterge exemplele", comment: "Removes example data.") }
            Button(role: .cancel) {} label: { Text("Păstrează", comment: "Cancel a delete.") }
        } message: {
            Text("Pleacă doar ce e marcat „Exemplu”.", comment: "Confirmation message when removing examples.")
        }
        .sensoryFeedback(.success, trigger: doneCount)
        .userErrorAlert($error)
    }

    private func load() {
        do {
            try ExampleDataService(context: context).loadExamples()
            doneCount += 1
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func remove() {
        do {
            try ExampleDataService(context: context).removeExamples()
            doneCount += 1
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

// MARK: - Spațiu ocupat

private struct StorageSettings: View {
    @Environment(\.modelContext) private var context
    @State private var report: StorageReport?
    @State private var isConfirmingCompaction = false
    @State private var freedBytes: Int?
    @State private var error: UserFacingError?

    var body: some View {
        Section {
            if let report {
                LabeledContent {
                    Text(verbatim: ByteCountFormatStyle(style: .file, locale: .dosarDefault).format(Int64(report.total.bytes)))
                        .monospacedDigit()
                } label: {
                    Text("Documente", comment: "Storage row: all documents.")
                    Text(verbatim: StorageWording.documents(report.total.documents)).dsFont(.footnote)
                }
                .frame(minHeight: 44)
                if report.archived.documents > 0 {
                    LabeledContent {
                        Text(verbatim: ByteCountFormatStyle(style: .file, locale: .dosarDefault).format(Int64(report.archived.bytes)))
                            .monospacedDigit()
                    } label: {
                        Text("Din care arhivate", comment: "Storage row: archived documents.")
                    }
                    .frame(minHeight: 44)
                }
                if !report.compactionCandidates.isEmpty {
                    Button {
                        isConfirmingCompaction = true
                    } label: {
                        Text("Micșorează pozele mai vechi de un an", comment: "Shrinks old scanned pages.")
                            .frame(minHeight: 44)
                    }
                }
                if let freedBytes {
                    Text("Am eliberat \(ByteCountFormatStyle(style: .file, locale: .dosarDefault).format(Int64(freedBytes))).", comment: "After shrinking old scans.")
                        .dsFont(.footnote)
                }
            } else {
                DSDelayedProgress()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        } header: {
            Text("Spațiu ocupat", comment: "Settings section.")
        } footer: {
            Text("PDF-urile rămân neatinse. Pozele vechi se păstrează, doar puțin mai mici.", comment: "Footer of the storage section.")
        }
        .task { refresh() }
        .confirmationDialog(Text("Micșorezi pozele vechi?", comment: "Confirmation title."), isPresented: $isConfirmingCompaction, titleVisibility: .visible) {
            Button(action: compact) { Text("Micșorează", comment: "Confirms shrinking old scans.") }
            Button(role: .cancel) {} label: { Text("Nu acum", comment: "Cancels an optional action.") }
        } message: {
            Text("Paginile scanate de peste un an devin mai mici. Se citesc la fel de bine.", comment: "Explains shrinking old scans.")
        }
        .userErrorAlert($error)
    }

    private func refresh() {
        report = try? DocumentStorage(context: context).report()
    }

    private func compact() {
        do {
            freedBytes = try DocumentStorage(context: context).compact()
            refresh()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

enum StorageWording {
    static func documents(_ count: Int) -> String {
        String(localized: "\(count) documente", comment: "A number of documents, with Romanian plural forms.")
    }
}

// MARK: - Despre

private struct AboutSettings: View {
    @State private var isShowingGallery = false

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: Bundle.main.shortVersion).monospacedDigit()
            } label: {
                Text("Versiunea", comment: "About: app version.")
            }
            .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Datele tale stau pe telefonul tău", comment: "About: privacy headline.")
                    .dsFont(.headline)
                Text("Fără cont, fără reclame, fără urmărire. Copia de siguranță o faci tu, când vrei. Internetul îl folosim doar dacă pui o cheie Google, pentru citirea documentelor.", comment: "About: privacy explanation.")
                    .dsFont(.footnote)
            }
            .padding(.vertical, DS.Space.xs)
            #if DEBUG
            Button {
                isShowingGallery = true
            } label: {
                Text(verbatim: "Galerie design (doar în versiunea de test)")
                    .frame(minHeight: 44)
            }
            .sheet(isPresented: $isShowingGallery) { DesignSystemGallery() }
            #endif
        } header: {
            Text("Despre", comment: "Settings section.")
        }
    }
}
