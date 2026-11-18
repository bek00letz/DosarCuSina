import SwiftData
import SwiftUI

/// The words a row says in place of what a section behind Face ID holds, wherever it is named
/// from outside its own page: a person's documents, a home's subscriptions, a firm's sections,
/// a box's line, Agendă's last job, De verificat. One place, so every surface says the same.
enum LockedWording {
    /// A personal document whose category is locked: „Document protejat”, with no name, date or digits.
    static var document: String {
        String(localized: "Document protejat", comment: "A row in place of something behind Face ID that is a document (a person's ID card, something shared into De verificat); nothing about it shows until unlock.")
    }

    /// Any other section whose category is locked: „Secțiune protejată”.
    static var section: String {
        String(localized: "Secțiune protejată", comment: "A row in place of a section behind Face ID, on another section's page or a firm's; nothing about it shows until unlock.")
    }

    /// A job done in a section whose category is locked, on a firm's page and in Agendă.
    static var job: String {
        String(localized: "O lucrare într-o secțiune protejată", comment: "A job hidden behind a lock.")
    }

    /// Under the label of a person's next document to expire, when that document is locked.
    static var nextDocumentLabel: String {
        String(localized: "Următorul act care expiră", comment: "Hero of a person, when the next document to expire is behind Face ID: the label above „Document protejat”.")
    }

    /// The hint of a locked row: what tapping it asks.
    static func opensWith(_ biometryName: String) -> String {
        String(localized: "Se deschide cu \(biometryName).", comment: "VoiceOver hint of a row behind Face ID. The name is Face ID, Touch ID or the passcode.")
    }
}

/// What a row that names another section may show of it, by the one answer for its lock
/// (`BiometricVaultManager.isLocked(_:template:)`): everything while its category is open, else
/// only the locked words, by what it is (`LockedWording`). The row still opens the section's page,
/// whose route asks for Face ID (`RouteLock.section`).
enum SectionRowLock: Equatable {
    case open
    case locked(title: String)

    @MainActor
    static func of(_ section: Asset, template: CategoryTemplate?, vault: BiometricVaultManager) -> SectionRowLock {
        guard vault.isLocked(section, template: template) else { return .open }
        let role = (template?.definition ?? BuiltInTemplates.definition(for: section.templateKey))?.behavior.role
        return .locked(title: role == .personalDocument ? LockedWording.document : LockedWording.section)
    }

    var isLocked: Bool { self != .open }
}

/// A row for a section behind Face ID: the lock in place of its symbol, the locked words in place
/// of its name, nothing else (no date, no badge, no digits).
struct LockedRow: View {
    let title: String
    @Environment(BiometricVaultManager.self) private var vault

    var body: some View {
        DSListRow(title: Text(verbatim: title), systemImage: "lock.fill", tint: DS.Palette.secondaryLabel, showsChevron: true) { EmptyView() }
            .accessibilityHint(Text(verbatim: LockedWording.opensWith(vault.biometryName)))
    }
}

/// A row naming another section, drawn as itself while its category is open and as a `LockedRow`
/// while it is locked: reads the one answer for `section`'s lock with its own category's record.
struct SectionRowGate<Content: View, Locked: View>: View {
    let section: Asset
    @ViewBuilder var content: Content
    /// What shows while it is locked, given the locked words; a `LockedRow` unless the row says otherwise.
    var locked: (String) -> Locked
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var templates: [CategoryTemplate]

    init(section: Asset, @ViewBuilder content: () -> Content, @ViewBuilder locked: @escaping (String) -> Locked) {
        self.section = section
        self.content = content()
        self.locked = locked
        let key = section.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    var body: some View {
        switch SectionRowLock.of(section, template: templates.first, vault: vault) {
        case .open: content
        case .locked(let title): locked(title)
        }
    }
}

extension SectionRowGate where Locked == LockedRow {
    init(section: Asset, @ViewBuilder content: () -> Content) {
        self.init(section: section, content: content) { LockedRow(title: $0) }
    }
}
