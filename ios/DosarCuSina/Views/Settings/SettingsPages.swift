import SwiftData
import SwiftUI

/// Settings, in plain words: a short list of rows, each saying in a few words how it stands
/// ("Pornite, la 09:00", "Face ID pentru 2 categorii", "Totul e sincronizat") and opening its
/// page. A link lands on its page (`SettingsPage.path(for:)`).
///
/// The earlier long list (`SettingsListScreen`) is kept, switched off, as the way back until the
/// owner has used the pages. Both show the same sections, so neither drifts.
struct SettingsScreen: View {
    let initialSection: SettingsSection?

    /// The short list of pages; false brings back the earlier long list.
    static let usesPages = true

    var body: some View {
        if Self.usesPages {
            SettingsPagesScreen(initialSection: initialSection)
        } else {
            SettingsListScreen(initialSection: initialSection)
        }
    }
}

/// The pages of Settings, in the order the list shows them.
enum SettingsPage: String, Hashable, CaseIterable, Sendable {
    case notifications
    case protection
    case dosarScreen
    case iCloudAndBackups
    case ai
    case repairs
    case examples
    case about

    /// The page a link's section is on.
    init(_ section: SettingsSection) {
        switch section {
        case .notifications: self = .notifications
        case .privacy: self = .protection
        case .categories: self = .dosarScreen
        case .backup: self = .iCloudAndBackups
        case .ai: self = .ai
        case .repairs: self = .repairs
        case .examples: self = .examples
        case .about: self = .about
        }
    }

    /// Where Settings opens for a link: its page, over the list; the list alone without one.
    static func path(for section: SettingsSection?) -> [SettingsPage] {
        section.map { [SettingsPage($0)] } ?? []
    }

    /// The pages the list shows: Exemple only while examples are in the binder.
    static func listed(hasExamples: Bool) -> [SettingsPage] {
        allCases.filter { $0 != .examples || hasExamples }
    }

    /// The list's groups, a hairline apart: what reminds and protects, where things are kept,
    /// reading, what waits, and the app.
    static func groups(hasExamples: Bool) -> [[SettingsPage]] {
        let listed = Set(listed(hasExamples: hasExamples))
        return [[.notifications, .protection], [.dosarScreen, .iCloudAndBackups], [.ai], [.repairs, .examples], [.about]]
            .map { $0.filter(listed.contains) }
            .filter { !$0.isEmpty }
    }

    var title: String {
        switch self {
        case .notifications: String(localized: "Notificări", comment: "Settings section.")
        case .protection: String(localized: "Protecție", comment: "Settings page: Face ID for the app and for categories, and the iPhone's search.")
        case .dosarScreen: String(localized: "Ecranul Dosar", comment: "Settings page: which categories show on the binder and how their boxes are arranged.")
        case .iCloudAndBackups: String(localized: "iCloud și copii", comment: "Settings page: iCloud sync, backups and storage.")
        case .ai: String(localized: "Citire cu AI", comment: "Settings page: the optional AI service that reads documents better.")
        case .repairs: String(localized: "Date de verificat", comment: "Settings row that opens the repair list.")
        case .examples: String(localized: "Exemple", comment: "Settings section.")
        case .about: String(localized: "Despre", comment: "Settings section.")
        }
    }

    var systemImage: String {
        switch self {
        case .notifications: "bell.badge"
        case .protection: "faceid"
        case .dosarScreen: "square.grid.2x2"
        case .iCloudAndBackups: "icloud"
        case .ai: "text.viewfinder"
        case .repairs: "wrench.and.screwdriver"
        case .examples: "sparkles"
        case .about: "info.circle"
        }
    }
}

/// What each row of Settings says about its page, in a few plain words. Pure, so it is tested.
enum SettingsStatus {
    /// "Pornite, la 09:00", "Oprite", "Nu ai ales încă".
    static func notifications(_ authorization: ReminderAuthorization, minuteOfDay: Int) -> String {
        switch authorization {
        case .authorized:
            String(localized: "Pornite, la \(DosarFormat.time(minuteOfDay: minuteOfDay))", comment: "Settings row: notifications are on, and the usual reminder time.")
        case .denied:
            String(localized: "Oprite din Setările telefonului", comment: "Settings row: notifications are off in the phone's settings.")
        case .notDetermined:
            String(localized: "Nu ai ales încă", comment: "Settings row: the person hasn't chosen whether to get notifications.")
        }
    }

    /// "Toată aplicația cere Face ID", "Face ID pentru 2 categorii", "Oprită"; while this phone's
    /// locks couldn't be read, that every category asks until the locks are chosen again.
    static func protection(appLock: Bool, lockedCategories: Int, biometryName: String, needsChoosingAgain: Bool) -> String {
        if needsChoosingAgain {
            return String(localized: "Totul cere \(biometryName) până alegi din nou", comment: "Settings row: this phone's locks couldn't be read; every category asks for Face ID until the person keeps them again.")
        }
        if appLock {
            return String(localized: "Toată aplicația cere \(biometryName)", comment: "Settings row: the whole app asks for Face ID.")
        }
        guard lockedCategories > 0 else {
            return String(localized: "Oprită", comment: "Settings row: no lock is on.")
        }
        let categories = String(localized: "\(lockedCategories) categorii", comment: "A number of categories, with Romanian plural forms (o categorie).")
        return String(localized: "\(biometryName) pentru \(categories)", comment: "Settings row: Face ID for some categories, e.g. 'Face ID pentru 2 categorii'.")
    }

    /// "Toate categoriile se văd", "O categorie ascunsă", "3 categorii ascunse".
    static func dosarScreen(hiddenCategories: Int) -> String {
        guard hiddenCategories > 0 else {
            return String(localized: "Toate categoriile se văd", comment: "Settings row: every category shows on the binder.")
        }
        return String(localized: "\(hiddenCategories) categorii ascunse", comment: "Settings row: how many categories are hidden from the binder, with Romanian plural forms (o categorie ascunsă).")
    }

    /// How sync is going in its own words ("Totul e sincronizat"), else where the binder is kept.
    static func iCloud(sync: PersistenceController.SyncState, health: SyncHealth?, isStopping: Bool) -> String {
        if let status = SyncWording.status(sync: sync, health: health, isStopping: isStopping) { return status.title }
        switch sync {
        case .waitingForExamples:
            return String(localized: "Pe telefon, cât sunt exemple", comment: "Settings row: the binder doesn't sync while examples are in it.")
        default:
            return String(localized: "Doar pe telefon", comment: "Settings row: the binder is kept on the phone only; backups are made by hand.")
        }
    }

    /// The service that reads when one is ready ("Google Gemini"), else that it's off.
    static func ai(readyWith provider: AIProvider?) -> String {
        guard let provider else {
            return String(localized: "Oprită, citesc pe telefon", comment: "Settings row: no AI service is set up; documents are read on the phone.")
        }
        return provider.name
    }

    /// "Nimic de verificat", "Un lucru de verificat", "3 lucruri de verificat".
    static func repairs(_ count: Int) -> String {
        guard count > 0 else {
            return String(localized: "Nimic de verificat", comment: "Settings row: the repair list is empty.")
        }
        return String(localized: "\(count) lucruri de verificat", comment: "Settings row: how many things wait in the repair list, with Romanian plural forms (un lucru de verificat).")
    }

    static var examples: String {
        String(localized: "Sunt în dosar", comment: "Settings row: examples are in the binder.")
    }

    /// "Versiunea 1.0 (build 180)".
    static func about(_ build: BuildInfo) -> String {
        String(localized: "Versiunea \(build.version) (build \(build.build))", comment: "Settings row: the app's version and build.")
    }
}

/// The short list and the pages it opens.
private struct SettingsPagesScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsPage]

    init(initialSection: SettingsSection?) {
        _path = State(initialValue: SettingsPage.path(for: initialSection))
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsRoot()
                .navigationDestination(for: SettingsPage.self) { page in
                    SettingsPageView(page: page)
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

/// The rows, each with how its page stands. The statuses read what the pages change, so they
/// follow as soon as the person comes back.
private struct SettingsRoot: View {
    @Environment(\.modelContext) private var context
    @Environment(\.sideEffects) private var sideEffects
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppPreferences.self) private var preferences
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var templates: [CategoryTemplate]
    @Query(filter: #Predicate<Asset> { $0.isExample }) private var examples: [Asset]
    @State private var repairs = DataRepairCenter.shared
    /// The AI service isn't observed (its key lives in the Keychain): read when the list shows.
    @State private var aiProvider: AIProvider?
    private let persistence = PersistenceController.shared

    var body: some View {
        List {
            ForEach(SettingsPage.groups(hasExamples: !examples.isEmpty), id: \.self) { group in
                Section {
                    ForEach(group, id: \.self) { page in
                        NavigationLink(value: page) {
                            DSListRow(
                                title: Text(verbatim: page.title),
                                subtitle: Text(verbatim: status(of: page)),
                                systemImage: page.systemImage,
                                trailing: { EmptyView() }
                            )
                        }
                    }
                }
            }
        }
        .onAppear(perform: readAI)
        .onChange(of: scenePhase) { _, phase in if phase == .active { readAI() } }
    }

    private func readAI() {
        let settings = AIProviderSettings.standard
        aiProvider = settings.isReady ? settings.provider : nil
    }

    private func status(of page: SettingsPage) -> String {
        switch page {
        case .notifications:
            return SettingsStatus.notifications(sideEffects?.reminderAuthorization ?? .notDetermined, minuteOfDay: preferences.reminderMinuteOfDay)
        case .protection:
            return SettingsStatus.protection(
                appLock: preferences.appLockEnabled,
                lockedCategories: templates.filter(\.isSensitive).count,
                biometryName: vault.biometryName,
                needsChoosingAgain: SectionLocks.of(context.container).needsChoosingAgain
            )
        case .dosarScreen:
            return SettingsStatus.dosarScreen(hiddenCategories: templates.filter { $0.behavior.box != .insideOther && !$0.isOnHome }.count)
        case .iCloudAndBackups:
            return SettingsStatus.iCloud(sync: persistence.sync, health: persistence.health, isStopping: persistence.isStoppingSync)
        case .ai:
            return SettingsStatus.ai(readyWith: aiProvider)
        case .repairs:
            return SettingsStatus.repairs(repairs.pending.count)
        case .examples:
            return SettingsStatus.examples
        case .about:
            return SettingsStatus.about(.current)
        }
    }
}

/// One page of Settings: the same sections the earlier list stacked, a few to a page.
private struct SettingsPageView: View {
    let page: SettingsPage

    /// Confirms a step taken here (a category of one's own changed or deleted, the examples
    /// removed), with its undo.
    @State private var toast: DSToast?

    var body: some View {
        content
            .dsToast($toast)
            .navigationTitle(Text(verbatim: page.title))
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .notifications:
            List { NotificationSettings() }
        case .protection:
            List {
                LockSettings()
                SpotlightSettings()
            }
        case .dosarScreen:
            List {
                SectionVisibilitySettings()
                CustomCategorySettings(toast: $toast)
            }
        case .iCloudAndBackups:
            List {
                ICloudSyncSettings()
                BackupSettings()
                StorageSettings()
            }
        case .ai:
            List { AISettings() }
        case .repairs:
            DataRepairsScreen()
        case .examples:
            List { ExampleSettings(toast: $toast) }
        case .about:
            List { AboutSettings() }
        }
    }
}
