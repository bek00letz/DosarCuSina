import Foundation
import Observation
import SwiftData

/// What one save changed, read from `ModelContext.didSave`.
public struct SearchChanges: Sendable, Equatable {
    /// Records added or changed.
    public var changed: Set<PersistentIdentifier> = []
    /// Records deleted.
    public var deleted: Set<PersistentIdentifier> = []
    /// The save can't say what it changed: read everything again.
    public var everything = false

    public init(changed: Set<PersistentIdentifier> = [], deleted: Set<PersistentIdentifier> = [], everything: Bool = false) {
        self.changed = changed
        self.deleted = deleted
        self.everything = everything
    }

    public init(_ notification: Notification) {
        let info = notification.userInfo ?? [:]
        func ids(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
            info[key.rawValue] as? [PersistentIdentifier] ?? []
        }
        changed = Set(ids(.insertedIdentifiers) + ids(.updatedIdentifiers))
        deleted = Set(ids(.deletedIdentifiers))
        everything = info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] != nil
    }

    public var isEmpty: Bool { changed.isEmpty && deleted.isEmpty && !everything }
}

/// Keeps Caută's index in step with the database, away from the main thread. The
/// first look reads every record; after that, a save reads again only the records
/// it changed and those that show them (`SearchIndexBuilder.recordsShowing`). A
/// change to a category, or a save that can't say what it changed, reads everything.
public actor SearchIndexer {
    private let container: ModelContainer
    /// Which documents each record gave, to take them out when it changes.
    private var documentIDs: [PersistentIdentifier: [String]] = [:]
    private var index: SearchIndex?
    /// How many records the last pass read, for tests: everything, or only what changed.
    public private(set) var lastRecordsRead = 0

    public init(container: ModelContainer) {
        self.container = container
    }

    /// The index, read in full the first time.
    public func current() throws -> SearchIndex {
        if let index { return index }
        return try rebuild()
    }

    /// Reads every record again.
    @discardableResult
    public func rebuild() throws -> SearchIndex {
        let byRecord = try SearchIndexBuilder(context: ModelContext(container)).buildByRecord()
        documentIDs = byRecord.mapValues { $0.map(\.id) }
        let fresh = SearchIndex(byRecord.values.flatMap { $0 })
        index = fresh
        lastRecordsRead = byRecord.count
        return fresh
    }

    /// Brings the index up to date with one save, reading only what it touched.
    public func apply(_ changes: SearchChanges) throws -> SearchIndex {
        guard let index, !changes.everything else { return try rebuild() }
        guard !changes.isEmpty else { return index }
        let builder = SearchIndexBuilder(context: ModelContext(container))
        var records: Set<PersistentIdentifier> = []
        for id in changes.changed.subtracting(changes.deleted) {
            guard let showing = try builder.recordsShowing(id) else { return try rebuild() }
            records.formUnion(showing)
        }
        if changes.deleted.contains(where: { $0.entityName == SearchIndexBuilder.entity(CategoryTemplate.self) }) {
            return try rebuild()
        }
        var removing: Set<String> = []
        for id in changes.deleted {
            removing.formUnion(documentIDs.removeValue(forKey: id) ?? [])
        }
        let templates = try builder.templates()
        var adding: [SearchDocument] = []
        for id in records {
            removing.formUnion(documentIDs[id] ?? [])
            let documents = try builder.documents(forRecord: id, templates: templates)
            documentIDs[id] = documents.isEmpty ? nil : documents.map(\.id)
            adding += documents
        }
        let updated = index.updating(removing: removing, adding: adding)
        self.index = updated
        lastRecordsRead = records.count
        return updated
    }
}

/// The search index the screen shows, kept up to date after every save in the
/// database, from any context. One per database, so switching tabs never reads
/// the whole binder again.
@MainActor
@Observable
final class SearchIndexStore {
    /// Nil until the first read is done.
    private(set) var index: SearchIndex?
    /// Goes up each time the index changes, for screens to search again.
    private(set) var generation = 0

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let indexer: SearchIndexer
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private static var instance: SearchIndexStore?

    static func shared(for container: ModelContainer) -> SearchIndexStore {
        if let instance, instance.container === container { return instance }
        let store = SearchIndexStore(container: container)
        instance = store
        return store
    }

    init(container: ModelContainer) {
        self.container = container
        self.indexer = SearchIndexer(container: container)
    }

    private func show(_ fresh: SearchIndex?) {
        guard let fresh else { return }
        index = fresh
        generation += 1
    }

    /// Listens for saves, then reads the index. Saves made while it reads wait their turn.
    func start() {
        guard listener == nil else { return }
        let indexer = indexer
        let container = container
        listener = Task { [weak self] in
            let saves = NotificationCenter.default.notifications(named: ModelContext.didSave)
                .compactMap { note -> SearchChanges? in
                    guard let context = note.object as? ModelContext, context.container === container else { return nil }
                    return SearchChanges(note)
                }
            Task { [weak self] in
                let first = try? await indexer.current()
                self?.show(first)
            }
            for await changes in saves where !changes.isEmpty {
                guard let updated = try? await indexer.apply(changes) else { continue }
                self?.show(updated)
            }
        }
    }
}
