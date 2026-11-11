import Foundation
import SwiftData

/// A custom stage of `DosarMigrationPlan` that carries something across the store's change of
/// shape: what it reads from the version before (in `willMigrate`) is kept in a file beside the
/// store before the shape changes (`MigrationCarry.keep`), and put where the current version keeps
/// it once the store has opened (`finish`). Each one is listed in `MigrationCarry.carries`.
protocol MigrationCarrying {
    associatedtype Carried: Codable
    /// The carry's part of its file's name. Never changed once shipped: a store halfway through its
    /// upgrade finds its carry by it.
    static var carryName: String { get }
    /// Puts what was carried where the current version keeps it, in `container`, opened at the
    /// current version. It runs before anything else reads the store, and again at the next launch
    /// when it stopped before the file went, so running it twice gives what running it once does.
    static func finish(_ carried: Carried, in container: ModelContainer) throws
}

/// How a custom stage's carry survives an upgrade that stops halfway (the app killed, the phone
/// full): one mechanism for every custom stage.
///
/// 1. Before the store changes shape, the stage writes what it carries to a file beside the store
///    (`keep`), protected like the phone's other private files. If it can't, the stage throws and
///    the store isn't changed: the upgrade runs again at the next launch.
/// 2. The store changes shape.
/// 3. Every time the store opens (`PersistenceController.makeContainer`), before anything reads it,
///    every carry still beside it is finished, oldest stage first, and its file removed
///    (`finishPending`). That is the one way a carry is finished, so an upgrade that stopped after
///    step 2 finishes at the next launch exactly as one that didn't stop, even with later stages in
///    between. Removing the file is part of finishing: if it can't go, the store doesn't open, and
///    the next try finishes again before anyone can change what it wrote.
///
/// "Începe din nou" moves the carries aside with the store they belong to.
enum MigrationCarry {
    /// Every carry, oldest stage first: finished in this order.
    static var carries: [any MigrationCarrying.Type] { [DayMigration.self, LockMigration.self] }

    /// A store opened in memory has no file beside it to carry anything in.
    struct NoStoreFile: Error {}

    /// Where the store at `url` keeps the carry `name` while its upgrade is under way.
    static func file(named name: String, forStoreAt url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".carry-\(name).json")
    }

    /// Writes `carried` beside the store `context` reads, before the store changes shape (a stage's
    /// `willMigrate`). Throws when it can't, so the stage stops and the store stays as it was.
    static func keep<C: MigrationCarrying>(_ carried: C.Carried, for carry: C.Type, from context: ModelContext) throws {
        guard let configuration = context.container.configurations.first, !configuration.isStoredInMemoryOnly else { throw NoStoreFile() }
        let data = try MachineText.jsonEncoder().encode(carried)
        try data.write(to: file(named: C.carryName, forStoreAt: configuration.url), options: [.atomic, .completeFileProtection])
    }

    /// Finishes every carry still beside the store `container` opened, oldest stage first, and
    /// removes each one's file once it is finished. Throws when one can't be finished: then the
    /// store mustn't be used yet.
    static func finishPending(in container: ModelContainer) throws {
        guard let configuration = container.configurations.first, !configuration.isStoredInMemoryOnly else { return }
        for carry in carries {
            try carry.finishIfPending(storeAt: configuration.url, in: container)
        }
    }

    /// Whether a carry still waits beside the store at `url`.
    static func isPending(storeAt url: URL) -> Bool {
        carries.contains { FileManager.default.fileExists(atPath: file(named: $0.carryName, forStoreAt: url).path(percentEncoded: false)) }
    }
}

extension MigrationCarrying {
    /// Finishes this carry if its file is still beside the store at `url`, then removes the file.
    static func finishIfPending(storeAt url: URL, in container: ModelContainer) throws {
        let file = MigrationCarry.file(named: carryName, forStoreAt: url)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        let carried = try MachineText.jsonDecoder().decode(Carried.self, from: Data(contentsOf: file))
        try finish(carried, in: container)
        try FileManager.default.removeItem(at: file)
    }
}

/// The move from version 11, which kept a category's lock in the store, to version 12, which keeps
/// it on each device (`SectionLocks`). Before the store changes shape, every category's lock is
/// carried (`MigrationCarry`); once the store opens, the locks become this device's choices, for
/// every category it hasn't decided on, so every lock stays as it was. A lock that can't be written
/// stops the store from opening rather than open a section.
enum LockMigration: MigrationCarrying {
    typealias Carried = [String: Bool]

    static var carryName: String { "locks-v12" }

    static var stage: MigrationStage {
        .custom(fromVersion: DosarSchemaV11.self, toVersion: DosarSchemaV12.self, willMigrate: { context in
            let locks = try context.fetch(FetchDescriptor<DosarSchemaV11.CategoryTemplate>())
                .reduce(into: [String: Bool]()) { locks, template in locks[template.key] = (locks[template.key] ?? false) || template.isSensitive }
            guard !locks.isEmpty else { return }
            try MigrationCarry.keep(locks, for: LockMigration.self, from: context)
        }, didMigrate: nil)
    }

    static func finish(_ locks: [String: Bool], in container: ModelContainer) throws {
        try SectionLocks.of(container).adopt(locks)
    }
}
