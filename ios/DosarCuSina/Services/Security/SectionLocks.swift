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
/// read, or none where an older build's "Începe din nou" moved it aside, means every category of
/// one's own and every one the catalog locks is locked, with every lock the moved file still shows,
/// until the person keeps the locks as they are in Settings (`chooseAgain`, after Face ID). What
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
    /// Every category of one's own and every one the catalog locks stays locked until the person
    /// keeps the locks as they are (`chooseAgain`).
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
    /// wait to be chosen again, a category of one's own (`ownCategory`) is locked too.
    func isLocked(_ key: String, byDefault: Bool, ownCategory: Bool) -> Bool {
        registrar.access(self, keyPath: \.generation)
        return mutex.withLock {
            choices[key] ?? (byDefault || (untilChosenAgain && ownCategory))
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

    /// Ends the wait after the locks couldn't be read: `locks` (every category's lock as it is now)
    /// become this device's choices, and a category of one's own from another device starts open
    /// again. Only after Face ID (`TemplateStore.keepLocksAsTheyAre`).
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

    /// What `file` says. A file that is there and can't be read keeps every lock on. With none, the
    /// locks an older build's "Începe din nou" moved aside stay on, and so does every category of
    /// one's own and every one the catalog locks, until the person chooses again.
    static func load(_ file: URL) -> Loaded {
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            guard let data = try? Data(contentsOf: file), var stored = try? JSONDecoder().decode([String: Bool].self, from: data) else {
                return Loaded(choices: [:], untilChosenAgain: true, fileUnread: true)
            }
            let waits = stored.removeValue(forKey: waitKey) ?? false
            return Loaded(choices: stored, untilChosenAgain: waits, fileUnread: false)
        }
        guard let moved = movedAside(file) else { return Loaded(choices: [:], untilChosenAgain: false, fileUnread: false) }
        return Loaded(choices: moved, untilChosenAgain: true, fileUnread: false)
    }

    /// The locks that are on in the files an older build's "Începe din nou" moved aside with the
    /// store ("unreadable-<when>-<file>"); nil when there is none.
    private static func movedAside(_ file: URL) -> [String: Bool]? {
        let directory = file.deletingLastPathComponent()
        let suffix = "-" + file.lastPathComponent
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
            .filter { $0.hasPrefix("unreadable-") && $0.hasSuffix(suffix) }
        guard !names.isEmpty else { return nil }
        var locks: [String: Bool] = [:]
        for name in names {
            guard let data = try? Data(contentsOf: directory.appending(path: name)),
                  let stored = try? JSONDecoder().decode([String: Bool].self, from: data) else { continue }
            for (key, locked) in stored where locked && key != waitKey { locks[key] = true }
        }
        return locks
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
