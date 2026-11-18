import Foundation
import Observation
import SwiftData

/// Which categories this device keeps behind Face ID: the one source of truth for a section's
/// lock (`CategoryTemplate.isSensitive` reads it, `CategoryTemplate.setLock` writes it).
///
/// Each phone or iPad decides for itself. The choice lives on the device, beside the store, never
/// in it: iCloud never carries it, and a lock turned off on one device can't open a section on
/// another. A category this device hasn't decided on is locked as the catalog says (Acte and
/// Sănătate), or as it was made here; a category of one's own made on another device starts open
/// here until it is locked here.
///
/// The choices are kept in a small file next to the store (`file(forStoreAt:)`), readable once the
/// phone was unlocked after it started (so reminders and widgets planned in the background follow
/// it), and a store kept in memory (tests, previews) has its own, gone with it. The file belongs to
/// the device, not to the binder: "Începe din nou" leaves it where it is.
///
/// Locks stay on when they can't be read (`needsChoosingAgain`). A file that is there but can't be
/// read, or none where an older build's "Începe din nou" moved it aside, means every category is
/// locked, whatever it was before and whatever is chosen meanwhile, until the person keeps the locks
/// in Settings (`chooseAgain`, after Face ID); then they open what they want, one by one. What
/// couldn't be read is never written over: the first change reads the file again, and if it still
/// can't, sets it aside and starts a new one that remembers the wait. A choice that can't be
/// written throws, so the screen says so and nothing shows as locked that isn't.
///
/// A backup carries the locks of the device that made it, as that device's settings; bringing one
/// in may lock a category here, never open one (`DossierImporter`).
final class SectionLocks: Observable, @unchecked Sendable {
    /// Posted after a choice changes, so what follows the locks (Spotlight, widgets, notifications,
    /// Caută) is worked out again.
    static let didChange = Notification.Name("SectionLocks.didChange")

    /// The built-in categories locked until this device decides otherwise.
    static let lockedByDefault: Set<String> = Set(BuiltInTemplates.all.filter(\.isSensitiveByDefault).map(\.key))

    /// Kept among the choices in the file while the locks wait to be chosen again. An older build
    /// reads it as the choice for a category that doesn't exist, and leaves it.
    static let waitKey = "#untilChosenAgain"

    private let file: URL?
    private let mutex = NSLock()
    private var choices: [String: Bool]
    /// Every category stays locked until the person keeps the locks (`chooseAgain`).
    private var untilChosenAgain: Bool
    /// The file is there and couldn't be read: it is read again before anything is written, and
    /// never written over.
    private var fileUnread: Bool
    private let registrar = ObservationRegistrar()
    /// Goes up with every change, for screens that show a lock.
    private(set) var generation = 0

    init(file: URL?) {
        self.file = file
        let loaded = file.map(SectionLocks.load) ?? Loaded(choices: [:], untilChosenAgain: false, fileUnread: false)
        choices = loaded.choices
        untilChosenAgain = loaded.untilChosenAgain
        fileUnread = loaded.fileUnread
    }

    /// Whether `key` is locked on this device: its choice here, else `byDefault`. While the locks
    /// wait to be chosen again, every category is locked.
    func isLocked(_ key: String, byDefault: Bool) -> Bool {
        registrar.access(self, keyPath: \.generation)
        return mutex.withLock {
            untilChosenAgain || (choices[key] ?? byDefault)
        }
    }

    /// Whether this device's locks couldn't be read and wait for the person to keep them as they
    /// are now (Settings says so).
    var needsChoosingAgain: Bool {
        registrar.access(self, keyPath: \.generation)
        return mutex.withLock { untilChosenAgain }
    }

    /// Every choice this device made.
    var all: [String: Bool] { mutex.withLock { choices } }

    /// Locks or opens `key` on this device. Throws when the choice can't be kept; then nothing
    /// changes.
    func set(_ locked: Bool, for key: String) throws {
        try update { $0[key] = locked }
    }

    /// Takes `values` as this device's choices for the keys it hasn't decided on: an upgrade's
    /// locks, as the store had them (`LockMigration`).
    func adopt(_ values: [String: Bool]) throws {
        try update { choices in
            for (key, locked) in values where key != Self.waitKey && choices[key] == nil { choices[key] = locked }
        }
    }

    /// Ends the wait after the locks couldn't be read: `locks` (every category's lock as it shows
    /// now: on) become this device's choices, and a category of one's own from another device starts
    /// open again. Only after Face ID (`TemplateStore.keepLocksAsTheyAre`).
    func chooseAgain(_ locks: [String: Bool]) throws {
        try update(endingTheWait: true) { choices in
            for (key, locked) in locks where key != Self.waitKey { choices[key] = locked }
        }
    }

    /// Reads the file again if it couldn't be read before: the store opened again.
    func readAgainIfUnread() {
        guard let file else { return }
        let read: Bool = mutex.withLock {
            guard fileUnread else { return false }
            let again = Self.load(file)
            guard !again.fileUnread else { return false }
            choices = again.choices
            untilChosenAgain = again.untilChosenAgain
            fileUnread = false
            return true
        }
        if read { told() }
    }

    private func update(endingTheWait: Bool = false, _ change: (inout [String: Bool]) -> Void) throws {
        let changed: Bool = try mutex.withLock {
            if fileUnread, let file {
                // It may read now; then the change goes over what it says.
                let again = Self.load(file)
                if !again.fileUnread {
                    choices = again.choices
                    untilChosenAgain = again.untilChosenAgain
                    fileUnread = false
                }
            }
            var next = choices
            change(&next)
            let waits = untilChosenAgain && !endingTheWait
            guard next != choices || waits != untilChosenAgain else { return false }
            if let file {
                if fileUnread { try Self.setAside(file) }
                var stored = next
                if waits { stored[Self.waitKey] = true }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(stored).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                fileUnread = false
            }
            choices = next
            untilChosenAgain = waits
            return true
        }
        if changed { told() }
    }

    private func told() {
        registrar.withMutation(of: self, keyPath: \.generation) { generation += 1 }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: The file

    struct Loaded: Equatable {
        var choices: [String: Bool]
        var untilChosenAgain: Bool
        var fileUnread: Bool
    }

    /// What `file` says. A file that is there and can't be read keeps every category locked. With
    /// none where an older build's "Începe din nou" moved it aside, every category is locked too,
    /// until the person chooses again.
    static func load(_ file: URL) -> Loaded {
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            guard let data = try? Data(contentsOf: file), var stored = try? JSONDecoder().decode([String: Bool].self, from: data) else {
                return Loaded(choices: [:], untilChosenAgain: true, fileUnread: true)
            }
            let waits = stored.removeValue(forKey: waitKey) ?? false
            return Loaded(choices: stored, untilChosenAgain: waits, fileUnread: false)
        }
        return Loaded(choices: [:], untilChosenAgain: wasMovedAside(file), fileUnread: false)
    }

    /// Whether an older build's "Începe din nou" moved this device's locks aside with the store
    /// ("unreadable-<when>-<file>").
    private static func wasMovedAside(_ file: URL) -> Bool {
        let suffix = "-" + file.lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path(percentEncoded: false))) ?? []
        return names.contains { $0.hasPrefix("unreadable-") && $0.hasSuffix(suffix) }
    }

    /// Keeps a file that couldn't be read beside the new one, never under it.
    private static func setAside(_ file: URL) throws {
        let target = file.deletingLastPathComponent().appending(path: file.lastPathComponent + ".unread-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: file, to: target)
    }

    // MARK: One per store

    private static let registryMutex = NSLock()
    nonisolated(unsafe) private static var byFile: [String: SectionLocks] = [:]
    /// A store in memory has locks of its own, gone with its container.
    nonisolated(unsafe) private static let inMemory = NSMapTable<ModelContainer, SectionLocks>.weakToStrongObjects()

    /// The locks of the store `container` opens: by its file, so every container on the same store
    /// shares them; a store in memory has its own.
    static func of(_ container: ModelContainer) -> SectionLocks {
        let configuration = container.configurations.first
        return registryMutex.withLock {
            guard let configuration, !configuration.isStoredInMemoryOnly else {
                if let existing = inMemory.object(forKey: container) { return existing }
                let locks = SectionLocks(file: nil)
                inMemory.setObject(locks, forKey: container)
                return locks
            }
            let path = configuration.url.standardizedFileURL.path(percentEncoded: false)
            if let existing = byFile[path] { return existing }
            let locks = SectionLocks(file: file(forStoreAt: configuration.url))
            byFile[path] = locks
            return locks
        }
    }

    /// Where a store's locks are kept on this device: beside it, never in it.
    static func file(forStoreAt url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".section-locks.json")
    }
}

// MARK: - The one answer

extension SectionLocks {
    /// Whether a category this device has no record of yet is locked here, until its record
    /// arrives (iCloud bringing it, an import): a built-in as the catalog says (Acte and Sănătate),
    /// any other locked, since it can't be told whether it was. Locks fail closed.
    static func lockedWhileUnknown(_ key: String) -> Bool {
        BuiltInTemplates.definition(for: key)?.isSensitiveByDefault ?? true
    }
}

extension CategoryTemplate {
    /// Whether the sections of the category `key` are behind Face ID on this device: the one
    /// answer for every screen and every surface, whether or not the category's record is here.
    /// With its record (`template`), the record's lock (`isSensitive`); without it, this device's
    /// choice for the key, else `SectionLocks.lockedWhileUnknown`, so a section whose category
    /// hasn't arrived yet is never shown or sent outside as open. Never read a missing record as
    /// open (the `lock-without-its-category` check).
    static func isSensitive(key: String, template: CategoryTemplate?, in container: ModelContainer?) -> Bool {
        if let template { return template.isSensitive }
        let byDefault = SectionLocks.lockedWhileUnknown(key)
        guard let container else { return byDefault }
        return SectionLocks.of(container).isLocked(key, byDefault: byDefault)
    }

    /// The same answer, from the categories by key (`TemplateStore.templatesByKey`).
    static func isSensitive(key: String, among templates: [String: CategoryTemplate], in container: ModelContainer?) -> Bool {
        isSensitive(key: key, template: templates[key], in: container)
    }
}

extension Asset {
    /// Whether this section's category is behind Face ID on this device
    /// (`CategoryTemplate.isSensitive(key:template:in:)`), given its category's record when the
    /// caller has it.
    func isSensitive(template: CategoryTemplate?) -> Bool {
        CategoryTemplate.isSensitive(key: templateKey, template: template, in: modelContext?.container)
    }

    /// The same answer, from the categories by key.
    func isSensitive(among templates: [String: CategoryTemplate]) -> Bool {
        isSensitive(template: templates[templateKey])
    }
}

// MARK: - The whole binder

/// Which categories are behind Face ID on this device across the whole binder: the one answer
/// (`CategoryTemplate.isSensitive(key:template:in:)`) asked for every category whose record is
/// here and for every category a section names whose record isn't here yet, so a section that
/// arrives before its category counts as locked, as it reads on its own page. Whatever asks
/// whether anything of the binder is locked reads this, never the category records alone: the
/// app-switcher cover (`AppShell`, `LockCover`), Face ID before a backup (`BackupFlow`),
/// Settings' row for the locks and De verificat (the `lock-without-its-category` check).
struct BinderLocks: Equatable {
    /// The keys of the categories behind Face ID on this device.
    let lockedKeys: Set<String>
    /// The binder couldn't be read: something of it may be behind Face ID (locks fail closed).
    private let unread: Bool

    /// From the categories' records and the keys the sections (or anything else asked about, such
    /// as an item waiting in De verificat) name.
    init(templates: [CategoryTemplate], naming keys: some Sequence<String>, in container: ModelContainer?) {
        var byKey: [String: [CategoryTemplate]] = [:]
        for template in templates { byKey[template.key, default: []].append(template) }
        var locked = Set<String>()
        // Two copies of one category before they are joined (`RecordsMeet`): locked if either is.
        for (key, copies) in byKey where copies.contains(where: { CategoryTemplate.isSensitive(key: key, template: $0, in: container) }) {
            locked.insert(key)
        }
        for key in Set(keys) where byKey[key] == nil && CategoryTemplate.isSensitive(key: key, template: nil, in: container) {
            locked.insert(key)
        }
        lockedKeys = locked
        unread = false
    }

    private init(unread: Bool) {
        lockedKeys = []
        self.unread = unread
    }

    /// The binder in `context`: its categories and the categories its sections name. A store that
    /// can't be read gives an answer in which something is locked.
    static func read(in context: ModelContext) -> BinderLocks {
        do {
            let templates = try context.fetch(FetchDescriptor<CategoryTemplate>())
            let keys = try context.fetch(sections).map(\.templateKey)
            return BinderLocks(templates: templates, naming: keys, in: context.container)
        } catch {
            return BinderLocks(unread: true)
        }
    }

    /// Every section, for the category it names: what a screen that follows the binder's locks
    /// queries beside the categories (`@Query(BinderLocks.sections)`).
    static var sections: FetchDescriptor<Asset> {
        var descriptor = FetchDescriptor<Asset>()
        descriptor.propertiesToFetch = [\.templateKey]
        return descriptor
    }

    /// Whether anything of the binder may be behind Face ID on this device: a category's lock is
    /// on, a section whose category hasn't arrived reads as locked, or the binder couldn't be read.
    var anySectionLocked: Bool { unread || !lockedKeys.isEmpty }
}
