import Foundation
import Observation
import SwiftData

/// Which categories this device keeps behind Face ID: the one source of truth for a section's
/// lock (`CategoryTemplate.isSensitive` reads and writes it).
///
/// Each phone or iPad decides for itself. The choice lives on the device, beside the store, never
/// in it: iCloud never carries it, and a lock turned off on one device can't open a section on
/// another. A category this device hasn't decided on is locked as the catalog says (Acte and
/// Sănătate), or as it was made here; a category of one's own made on another device starts open
/// here until it is locked here.
///
/// The choices are kept in a small file next to the store (`file(forStoreAt:)`), readable once the
/// phone was unlocked after it started (so reminders and widgets planned in the background follow
/// it), and a store kept in memory (tests, previews) has its own, gone with it.
///
/// A backup carries the locks of the device that made it, as that device's settings; bringing one
/// in may lock a category here, never open one (`DossierImporter`).
final class SectionLocks: Observable, @unchecked Sendable {
    /// Posted after a choice changes, so what follows the locks (Spotlight, widgets, notifications,
    /// Caută) is worked out again.
    static let didChange = Notification.Name("SectionLocks.didChange")

    /// The built-in categories locked until this device decides otherwise.
    static let lockedByDefault: Set<String> = Set(BuiltInTemplates.all.filter(\.isSensitiveByDefault).map(\.key))

    private let file: URL?
    private let mutex = NSLock()
    private var choices: [String: Bool]
    private let registrar = ObservationRegistrar()
    /// Goes up with every change, for screens that show a lock.
    private(set) var generation = 0

    init(file: URL?) {
        self.file = file
        choices = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
    }

    /// Whether `key` is locked on this device: its choice here, else `byDefault`.
    func isLocked(_ key: String, byDefault: Bool) -> Bool {
        registrar.access(self, keyPath: \.generation)
        return choice(for: key) ?? byDefault
    }

    /// This device's choice for `key`, nil while it hasn't made one.
    func choice(for key: String) -> Bool? {
        mutex.withLock { choices[key] }
    }

    /// Every choice this device made.
    var all: [String: Bool] { mutex.withLock { choices } }

    /// Locks or opens `key` on this device.
    func set(_ locked: Bool, for key: String) {
        update { $0[key] = locked }
    }

    /// Takes `values` as this device's choices for the keys it hasn't decided on: an upgrade's
    /// locks, as the store had them.
    func adopt(_ values: [String: Bool]) {
        update { choices in
            for (key, locked) in values where choices[key] == nil { choices[key] = locked }
        }
    }

    private func update(_ change: (inout [String: Bool]) -> Void) {
        let changed: Bool = mutex.withLock {
            let before = choices
            change(&choices)
            guard choices != before else { return false }
            if let file, let data = try? JSONEncoder().encode(choices) {
                try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return true
        }
        guard changed else { return }
        registrar.withMutation(of: self, keyPath: \.generation) { generation += 1 }
        NotificationCenter.default.post(name: Self.didChange, object: self)
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
