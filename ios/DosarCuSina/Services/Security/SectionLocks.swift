import Foundation
import Observation
import SwiftData

/// Which categories this device keeps behind Face ID: the one source of truth for a section's
/// lock (`CategoryTemplate.isSensitive` reads it, `CategoryTemplate.setLock` writes it).
///
/// Locking travels, opening doesn't (DECISIONS, 2026-11-25). This device's choices live on it,
/// beside the store, never in it, each with when it was made (`chosenAt`); locking a category
/// also writes when on its record (`CategoryTemplate.lockedEverywhereAt`), which iCloud carries.
/// A category is locked here when it was locked anywhere after this device last chose for it
/// (or this device never chose), else as this device chose, else as the catalog says (Acte and
/// Sănătate) or as it was made. So locking on one device locks it on every device, a new one
/// included, and opening it with Face ID opens it only on the device that opens it: a lock
/// turned off on one device can't open a section on another. Each device sends up the locks it
/// already had once (`LockPublishing`).
///
/// The choices are kept in a small file next to the store (`file(forStoreAt:)`), readable once the
/// phone was unlocked after it started (so reminders and widgets planned in the background follow
/// it), and a store kept in memory (tests, previews) has its own, gone with it. The file belongs to
/// the device, not to the binder: "Începe din nou" leaves it where it is.
///
/// Locks stay on when they can't be read (`needsChoosingAgain`). A file that is there but can't be
/// read, or none where one was set aside (`wasSetAside`: by a change that couldn't write the new one
/// after it, or by an older build's "Începe din nou"), means every category is locked, whatever it
/// was before and whatever is chosen meanwhile, until the person keeps the locks in Settings
/// (`chooseAgain`, after Face ID); then they open what they want, one by one. What couldn't be read
/// is never written over: the first change reads the file again, and if it still can't, sets it
/// aside and starts a new one that remembers the wait. What was set aside stays beside the file,
/// as it was; once a file that reads is there, the file alone says what is chosen. A choice that
/// can't be written throws, so the screen says so and nothing shows as locked that isn't.
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
    /// When this device made each choice, kept beside the choices (`timesFile`). A choice without
    /// a time (made before version 19, or its time lost) is older than any lock made anywhere.
    private var chosenAt: [String: Date]
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
        chosenAt = file.map { Self.loadTimes(Self.timesFile(for: $0)) } ?? [:]
    }

    /// Whether `key` is locked on this device: locked anywhere (`lockedEverywhereAt`, from its
    /// record) after this device last chose for it, else its choice here, else `byDefault`. While
    /// the locks wait to be chosen again, every category is locked.
    func isLocked(_ key: String, byDefault: Bool, lockedEverywhereAt: Date? = nil) -> Bool {
        registrar.access(self, keyPath: \.generation)
        return mutex.withLock {
            if untilChosenAgain { return true }
            if let lockedEverywhereAt, !(chosenAt[key].map { $0 > lockedEverywhereAt } ?? false) { return true }
            return choices[key] ?? byDefault
        }
    }

    /// Whether this device chose to lock `key` itself, and when (`LockPublishing` sends it up).
    func lockedHere(_ key: String) -> (locked: Bool, at: Date?)? {
        mutex.withLock { choices[key].map { ($0, chosenAt[key]) } }
    }

    /// Whether this device's locks couldn't be read and wait for the person to keep them as they
    /// are now (Settings says so).
    var needsChoosingAgain: Bool {
        registrar.access(self, keyPath: \.generation)
        return mutex.withLock { untilChosenAgain }
    }

    /// Every choice this device made.
    var all: [String: Bool] { mutex.withLock { choices } }

    /// Locks or opens `key` on this device, as chosen `now`: a newer choice than any lock made
    /// elsewhere, so opening here opens it here. Throws when the choice can't be kept; then
    /// nothing changes.
    func set(_ locked: Bool, for key: String, at now: Date = Date()) throws {
        try update(choosing: [key], at: now) { $0[key] = locked }
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
    func chooseAgain(_ locks: [String: Bool], at now: Date = Date()) throws {
        try update(endingTheWait: true, choosing: Set(locks.keys), at: now) { choices in
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

    private func update(endingTheWait: Bool = false, choosing: Set<String> = [], at now: Date = Date(), _ change: (inout [String: Bool]) -> Void) throws {
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
            var times = chosenAt
            for key in choosing where key != Self.waitKey && next[key] != nil { times[key] = now }
            guard next != choices || waits != untilChosenAgain || times != chosenAt else { return false }
            if let file {
                // The times first: a choice whose time didn't make it reads as older, so locked
                // wherever a lock was made since (locks fail closed).
                if times != chosenAt { try MachineText.jsonEncoder().encode(times).write(to: Self.timesFile(for: file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                if fileUnread { try Self.setAside(file) }
                var stored = next
                if waits { stored[Self.waitKey] = true }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(stored).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                fileUnread = false
            }
            choices = next
            chosenAt = times
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
    /// none where one was set aside (`wasSetAside`), every category is locked too, until the person
    /// chooses again; a file that reads, once written, says what is chosen whatever lies beside it.
    static func load(_ file: URL) -> Loaded {
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            guard let data = try? Data(contentsOf: file), var stored = try? JSONDecoder().decode([String: Bool].self, from: data) else {
                return Loaded(choices: [:], untilChosenAgain: true, fileUnread: true)
            }
            let waits = stored.removeValue(forKey: waitKey) ?? false
            return Loaded(choices: stored, untilChosenAgain: waits, fileUnread: false)
        }
        return Loaded(choices: [:], untilChosenAgain: wasSetAside(file), fileUnread: false)
    }

    /// When this device made each choice: beside the choices, under a name that starts with
    /// theirs, so "Începe din nou" leaves it with them (`PersistenceController.moveStoreAside`).
    static func timesFile(for file: URL) -> URL {
        file.deletingLastPathComponent().appending(path: file.lastPathComponent + ".times")
    }

    /// What the times file says; none when it isn't there or can't be read (every choice then
    /// reads as older than any lock made elsewhere).
    static func loadTimes(_ file: URL) -> [String: Date] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? MachineText.jsonDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    /// How a file of choices that couldn't be read is named once set aside, after its own name
    /// ("<file>.unread-<id>", as the Android app names it).
    static let setAsideMark = ".unread-"

    /// How an older build's "Începe din nou" named what it moved aside, before the file's name
    /// ("unreadable-<when>-<file>").
    static let movedAsideMark = "unreadable-"

    /// Whether this device's choices were set aside with none written after them: by a change that
    /// set an unread file aside and then couldn't write its own ("<file>.unread-<id>"), or by an
    /// older build's "Începe din nou" ("unreadable-<when>-<file>"). Read only while `file` isn't
    /// there: the first file written after them says what is chosen. A folder that can't be listed
    /// may hold one, so it counts as set aside (locks fail closed); a folder that isn't there holds
    /// nothing.
    static func wasSetAside(_ file: URL) -> Bool {
        let name = file.lastPathComponent
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path(percentEncoded: false))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        } catch {
            return true
        }
        return names.contains {
            $0.hasPrefix(name + setAsideMark) || ($0.hasPrefix(movedAsideMark) && $0.hasSuffix("-" + name))
        }
    }

    /// Keeps a file that couldn't be read beside the new one, never under it, under a name
    /// `wasSetAside` knows, so a new file that then can't be written leaves every category locked.
    private static func setAside(_ file: URL) throws {
        let target = file.deletingLastPathComponent().appending(path: file.lastPathComponent + setAsideMark + UUID().uuidString)
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

extension Obligation {
    /// Whether this deadline's section is behind Face ID on this device, read now (the one answer,
    /// `Asset.isSensitive(template:)`, with its category's record from `context`): what closing it
    /// asks (`DeadlineChange`), never a copy kept from earlier, such as a snapshot read before a
    /// lock was turned on. A deadline of the whole household has no section, so no lock.
    @MainActor
    func isSensitive(in context: ModelContext) -> Bool {
        guard let asset else { return false }
        let template = (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil
        return asset.isSensitive(template: template)
    }
}

extension Attachment {
    /// Every section this document belongs to: its own, its deadline's, its record's in Istoric
    /// (a visit's invoice, a bill), its part's and its reading's, each once.
    var sections: [Asset] {
        let candidates = [asset, obligation?.asset, historyEntry?.asset, serviceItem?.entry?.asset, measurement?.asset]
        var found: [Asset] = []
        for case let section? in candidates where !found.contains(where: { $0.id == section.id }) { found.append(section) }
        return found
    }

    /// The lock the document's page is drawn behind, by the one answer for each section it belongs
    /// to: a section whose category is locked if it has one (so the page is locked if any of them
    /// is), else its first section. A document of the whole household's (a household deadline's
    /// paper) is open; one that names nothing that can be found is `RouteLock.unknownSection`,
    /// locked while anything of the binder is (locks fail closed).
    func lock(among templates: [String: CategoryTemplate]) -> RouteLock {
        let sections = sections
        if let locked = sections.first(where: { $0.isSensitive(among: templates) }) { return .section(locked.id) }
        if let first = sections.first { return .section(first.id) }
        let belongsToTheHousehold = obligation != nil || historyEntry != nil
        return belongsToTheHousehold ? .open : .unknownSection
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
