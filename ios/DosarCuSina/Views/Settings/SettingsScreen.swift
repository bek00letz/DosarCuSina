import SwiftUI
import SwiftData
import UserNotifications

/// Where Settings opens: the section a link asks for, kept at the top while the list lays
/// itself out (rows measuring themselves, a status read late), until the person scrolls.
/// Waits for the list, never for a guessed pause. Pure, so it is tested.
struct SettingsLanding: Equatable {
    /// The section to keep at the top; nil once the person has scrolled, or with no link.
    private(set) var section: SettingsSection?

    init(_ section: SettingsSection?) {
        self.section = section
    }

    /// The section to scroll to now that the list measures `height`; nil before it has any rows.
    func section(whenLaidOut height: CGFloat) -> SettingsSection? {
        height > 0 ? section : nil
    }

    /// The person moved the list: it stays where they put it.
    mutating func personScrolled() {
        section = nil
    }
}

/// Settings, in plain words. Opens at a section when a link asks for one.
struct SettingsScreen: View {
    let initialSection: SettingsSection?

    @Environment(\.dismiss) private var dismiss
    /// The section a link asked for, shown from the start.
    @State private var landing: SettingsLanding
    /// The repair list, open right away when a link or the repair prompt asks for it.
    @State private var showsRepairs: Bool
    /// Confirms a step taken here (a category of one's own changed or deleted, the examples
    /// removed), with its undo.
    @State private var toast: DSToast?

    init(initialSection: SettingsSection?) {
        self.initialSection = initialSection
        _showsRepairs = State(initialValue: initialSection == .repairs)
        _landing = State(initialValue: SettingsLanding(initialSection))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    NotificationSettings().id(SettingsSection.notifications)
                    LockSettings().id(SettingsSection.privacy)
                    SpotlightSettings()
                    SectionVisibilitySettings().id(SettingsSection.categories)
                    CustomCategorySettings(toast: $toast)
                    ExampleSettings(toast: $toast).id(SettingsSection.examples)
                    ICloudSyncSettings()
                    BackupSettings().id(SettingsSection.backup)
                    DataRepairSettings(isShowingList: $showsRepairs).id(SettingsSection.repairs)
                    StorageSettings()
                    AISettings()
                    AboutSettings().id(SettingsSection.about)
                }
                // The sheet opens already at the section, with no visible scroll: as soon as the list
                // has rows, and again whenever they change height, until the person scrolls.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    land(proxy, height: height)
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
                    land(proxy, height: height)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .tracking || phase == .interacting { landing.personScrolled() }
                }
            }
            .navigationDestination(isPresented: $showsRepairs) { DataRepairsScreen() }
            .dsToast($toast)
            .navigationTitle(Text("Setări", comment: "Toolbar button that opens settings."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Gata", comment: "Closes an editor and keeps what was typed.") }
                }
            }
        }
    }

    private func land(_ proxy: ScrollViewProxy, height: CGFloat) {
        guard let section = landing.section(whenLaidOut: height) else { return }
        proxy.scrollTo(section, anchor: .top)
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
                    Task {
                        await sideEffects?.askForPermission()
                        await ReminderPermission.shared.refresh()
                    }
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
            return Calendar.dosar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.dosar.dateComponents([.hour, .minute], from: date)
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
        let shown = templates.filter { used.contains($0.key) || $0.behavior.box == .wholeCategory || $0.isSensitive }
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
            Text("O secțiune protejată se deschide doar cu \(vault.biometryName), chiar dacă aplicația nu e blocată, și nu apare în căutarea iPhone-ului. Restul aplicației merge normal.", comment: "Footer of the section locks.")
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

// MARK: - Căutarea iPhone-ului

/// Whether sections, deadlines and documents appear in Spotlight. Off deletes the app's
/// whole index; the coordinator does it after the preference changes (`SpotlightIndexer`).
private struct SpotlightSettings: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(BiometricVaultManager.self) private var vault

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Toggle(isOn: $preferences.showsInSpotlight) {
                Text("Arată în căutarea iPhone-ului", comment: "Setting: show sections, deadlines and documents in Spotlight.")
            }
            .frame(minHeight: 44)
        } footer: {
            Text("Numele secțiunilor, termenele și titlurile actelor apar când cauți pe iPhone. Ce e protejat cu \(vault.biometryName), codurile, numerele de pe acte și exemplele nu apar niciodată. Cât timp toată aplicația e blocată, nu apare nimic.", comment: "Footer of the Spotlight setting: what appears, what never does, and that nothing appears while the whole app is locked.")
        }
    }
}

// MARK: - iCloud

/// "Sincronizează cu iCloud": on by default; off stops syncing and keeps everything on the phone.
/// Shown only where the build syncs (`PersistenceController.SyncState`).
private struct ICloudSyncSettings: View {
    @Environment(AppPreferences.self) private var preferences
    private let persistence = PersistenceController.shared

    var body: some View {
        if persistence.sync != .notInThisBuild {
            Section {
                Toggle(isOn: Binding(get: { preferences.syncsWithICloud }, set: set)) {
                    Text("Sincronizează cu iCloud", comment: "Setting: sync the binder with the person's own iCloud.")
                }
                .frame(minHeight: DS.Control.minimumHitTarget)
            } footer: {
                Text(SyncWording.footer(for: persistence.sync))
            }
        }
    }

    private func set(_ isOn: Bool) {
        preferences.syncsWithICloud = isOn
        persistence.applySyncChoice()
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
            ForEach(templates.filter { $0.behavior.box != .insideOther }) { template in
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

// MARK: - Categoriile tale

/// The person's own categories, each opening its name, symbol and switches
/// (`CategoryEditSheet`). Built-in categories behave as they always do, so they aren't here.
private struct CustomCategorySettings: View {
    @Binding var toast: DSToast?
    @Query(sort: [SortDescriptor(\CategoryTemplate.homeOrder)]) private var templates: [CategoryTemplate]
    @State private var editing: CategoryTemplate?

    var body: some View {
        let custom = templates.filter(\.isCustom)
        if !custom.isEmpty {
            Section {
                ForEach(custom) { template in
                    Button {
                        editing = template
                    } label: {
                        DSListRow(
                            title: Text(verbatim: template.name),
                            subtitle: Text(verbatim: CustomCategoryForm.summary(of: CategorySwitches(reading: template.definition))),
                            systemImage: template.symbol,
                            tint: template.tintColor,
                            showsChevron: true
                        ) { EmptyView() }
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityHint(Text("Schimbă ce ține minte categoria.", comment: "VoiceOver hint of a category of one's own in Settings."))
                }
            } header: {
                Text("Categoriile tale", comment: "Settings section: the person's own categories.")
            } footer: {
                Text("Alege ce ține minte fiecare. Categoriile incluse în aplicație rămân cum sunt.", comment: "Footer of the person's own categories in Settings.")
            }
            .sheet(item: $editing) { template in
                CategoryEditSheet(template: template) { done in toast = done }
            }
        }
    }
}

// MARK: - Exemple

private struct ExampleSettings: View {
    /// Settings' toast: removing the examples can be taken back from it.
    @Binding var toast: DSToast?
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
            try ExampleDataService.forLoading(from: context).loadExamples()
            doneCount += 1
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func remove() {
        do {
            let removed = try ExampleDataService(context: context).removeExamples()
            // The toast brings its own haptic, and "Anulează" brings every example back.
            toast = .undoDeletion(removed.value.isEmpty
                ? LocalizedStringResource("Am șters exemplele.", comment: "Toast after removing the examples.")
                : LocalizedStringResource("Am șters exemplele. Ce ai pus tu în ele a rămas al tău.",
                                          comment: "Toast after removing the examples, some kept because the person added to them."),
                receipt: removed.receipt)
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

/// What Despre promises, built from what the app really does.
enum AboutWording {
    /// No account, no tracking, and the internet only for the AI service the person
    /// chose. The services are named from `AIProvider`, so a new one is never left out.
    static var privacy: String {
        String(
            localized: "Fără cont, fără reclame, fără urmărire. Copia de siguranță o faci tu, când vrei. Internetul îl folosim doar dacă pui cheia ta de la un serviciu AI (\(AIProvider.everyServiceInASentence)). Atunci actele citite cu el ajung la acel serviciu.",
            comment: "About: privacy explanation. The argument lists the AI services, such as „Google Gemini, OpenAI, Anthropic Claude sau unul compatibil”."
        )
    }
}

private struct AboutSettings: View {
    @State private var isShowingGallery = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Datele tale stau pe telefonul tău", comment: "About: privacy headline.")
                    .dsFont(.headline)
                Text(verbatim: AboutWording.privacy)
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
            // Last, so it's easy to find: which build this phone runs, copyable.
            DSActionValueRow(title: Text("Versiunea", comment: "About: app version and build."), value: BuildInfo.current.summary, action: .copy)
        } header: {
            Text("Despre", comment: "Settings section.")
        }
    }
}
