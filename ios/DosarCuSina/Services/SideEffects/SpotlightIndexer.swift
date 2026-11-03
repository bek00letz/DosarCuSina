import AppIntents
import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Keeps the iPhone's search (Spotlight) showing what `SpotlightCatalog` allows, and
/// nothing else. It is the coordinator's one Spotlight indexer: it runs after every
/// pass, so it reacts to saves the way reminders and widgets do.
///
/// Only what changed is written: a ledger on this phone remembers each indexed
/// identifier with a fingerprint of what it shows, so a pass sends only new or changed
/// entries and deletes the ones that went away (deleted, locked, archived, made an
/// example), in one batch. The index keeps a token of the last batch; when it doesn't
/// match the ledger (a phone restored from a backup, an index the system cleared), the
/// app's whole index is deleted and written again, so the two never drift apart.
///
/// With "Arată în căutarea iPhone-ului" off, or with the whole app locked, the app's whole
/// index is deleted once and nothing is written until that changes (`showsAnything`).
@MainActor
public final class SpotlightIndexer: SideEffectIndexer {
    /// What the last pass did, for Settings and tests.
    public struct Change: Equatable, Sendable {
        public var indexed: [String] = []
        public var removed: [String] = []
        public var removedEverything = false
    }

    public private(set) var lastChange: Change?

    private let index: any SpotlightIndexClient
    private let ledger: SpotlightLedgerStore
    private let isEnabled: @MainActor () -> Bool
    private let locale: Locale

    public init(
        index: any SpotlightIndexClient = SystemSpotlightIndex(),
        ledger: SpotlightLedgerStore = .standard,
        isEnabled: @escaping @MainActor () -> Bool = { SpotlightIndexer.showsAnything(AppPreferences.shared) },
        locale: Locale = .dosarDefault
    ) {
        self.index = index
        self.ledger = ledger
        self.isEnabled = isEnabled
        self.locale = locale
    }

    /// Whether anything of the app may be in the iPhone's search: the setting is on and the
    /// whole app isn't locked. Someone who locks the whole app finds nothing of it outside.
    public static func showsAnything(_ preferences: AppPreferences) -> Bool {
        preferences.showsInSpotlight && !preferences.appLockEnabled
    }

    public func reconcile(obligations: [ObligationSnapshot], context: ModelContext) async {
        guard isEnabled() else {
            await removeEverything()
            return
        }
        guard let entries = try? SpotlightCatalog.entries(obligations: obligations, in: context, locale: locale) else { return }
        var known = ledger.load()
        var change = Change()
        do {
            // The index and the ledger describe the same batch, or everything is written again.
            if try await index.lastState() != known.state {
                try await index.deleteAll()
                known = .empty
                change.removedEverything = true
            }
            let wanted = Dictionary(entries.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
            let upserts = wanted.values.filter { known.entries[$0.identifier] != $0.fingerprint }
                .sorted { $0.identifier < $1.identifier }
            let removals = known.entries.keys.filter { wanted[$0] == nil }.sorted()
            if !upserts.isEmpty || !removals.isEmpty {
                let state = Data(UUID().uuidString.utf8)
                try await index.apply(upserts: upserts, removals: removals, state: state)
                known = SpotlightLedger(entries: wanted.mapValues(\.fingerprint), state: state, isCleared: false)
                change.indexed = upserts.map(\.identifier)
                change.removed = removals
            }
            if change != Change() { ledger.save(known) }
            lastChange = change
        } catch {
            // Not written (the phone is locked, the index is busy): the ledger stays as it
            // was, so the next pass sends the same changes again.
        }
    }

    /// Deletes the app's whole index, once, and remembers that it did.
    private func removeEverything() async {
        let known = ledger.load()
        guard !known.isCleared || !known.entries.isEmpty else { return }
        do {
            try await index.deleteAll()
            ledger.save(.cleared)
            lastChange = Change(removedEverything: true)
        } catch {
            // Tried again on the next pass.
        }
    }
}

// MARK: - The index

/// The part of Core Spotlight the indexer uses, so tests can stand in for it.
@MainActor
public protocol SpotlightIndexClient: AnyObject {
    /// The token written with the last batch, or nil when there is none.
    func lastState() async throws -> Data?
    /// Writes and deletes in one batch, then records `state`.
    func apply(upserts: [SpotlightEntry], removals: [String], state: Data) async throws
    /// Deletes everything the app has in the index.
    func deleteAll() async throws
}

/// The app's Core Spotlight index. Its items are readable only while the phone is
/// unlocked (complete file protection), never expire on their own, and a deadline is
/// linked to its Siri and Shortcuts entity on iOS 27.
@MainActor
public final class SystemSpotlightIndex: SpotlightIndexClient {
    private let index: CSSearchableIndex

    public init(name: String = "DosarCuSina") {
        index = CSSearchableIndex(name: name, protectionClass: .complete)
    }

    public func lastState() async throws -> Data? {
        guard CSSearchableIndex.isIndexingAvailable() else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            index.fetchLastClientState { state, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: state) }
            }
        }
    }

    public func apply(upserts: [SpotlightEntry], removals: [String], state: Data) async throws {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        stage(upserts.map(Self.item), removals: removals)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.endBatch(withClientState: state) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    /// Opens a batch with the writes and deletions; ending it with the token commits them
    /// and reports whether they were kept.
    private func stage(_ items: [CSSearchableItem], removals: [String]) {
        index.beginBatch()
        if !items.isEmpty { index.indexSearchableItems(items, completionHandler: nil) }
        if !removals.isEmpty { index.deleteSearchableItems(withIdentifiers: removals, completionHandler: nil) }
    }

    public func deleteAll() async throws {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.deleteAllSearchableItems { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    static func item(_ entry: SpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.displayName = entry.title
        attributes.contentDescription = entry.detail
        attributes.keywords = entry.keywords
        let item = CSSearchableItem(uniqueIdentifier: entry.identifier, domainIdentifier: entry.kind.rawValue, attributeSet: attributes)
        // Items expire after a month unless told otherwise; these live as long as the record.
        item.expirationDate = .distantFuture
        if #available(iOS 27.0, *), case .obligation(let id) = entry.route {
            item.relatedAppEntityIdentifier = EntityIdentifier(for: ObligationEntity.self, identifier: id)
        }
        return item
    }
}

// MARK: - The ledger

/// What the app last wrote to the index: each identifier with the fingerprint of what
/// it shows, and the token written with that batch. No titles, only fingerprints.
public struct SpotlightLedger: Codable, Equatable, Sendable {
    public var entries: [String: String]
    public var state: Data?
    /// The whole index was deleted and nothing written since.
    public var isCleared: Bool

    public static let empty = SpotlightLedger(entries: [:], state: nil, isCleared: false)
    public static let cleared = SpotlightLedger(entries: [:], state: nil, isCleared: true)
}

/// The ledger, kept in a file on this phone, left out of the phone's backups: a
/// restored phone starts with an empty index, so it starts with no ledger either.
public struct SpotlightLedgerStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var standard: SpotlightLedgerStore {
        SpotlightLedgerStore(url: URL.applicationSupportDirectory.appending(path: "Spotlight/ledger.json"))
    }

    public func load() -> SpotlightLedger {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(SpotlightLedger.self, from: data)) ?? .empty
    }

    public func save(_ ledger: SpotlightLedger) {
        do {
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var file = url
            try? file.setResourceValues(values)
        } catch {
            // A ledger that couldn't be written no longer matches the index's token, so
            // the next pass writes everything again.
        }
    }
}
