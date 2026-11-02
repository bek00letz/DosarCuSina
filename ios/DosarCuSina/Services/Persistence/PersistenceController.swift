import Foundation
import SwiftData
import Observation

/// Opens the household database once and shares it with the app, App Intents
/// and notification actions. A store that can't be opened never crashes the
/// app: the state becomes `.failed` and the UI offers to retry or start fresh.
@MainActor
@Observable
public final class PersistenceController {
    public enum State {
        case ready(ModelContainer)
        case failed(String)
    }

    public static let shared = PersistenceController()

    public private(set) var state: State

    /// The ready container, or nil while the store can't be opened.
    public var container: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    private let storeURL: URL

    public init(storeURL: URL = PersistenceController.defaultStoreURL) {
        self.storeURL = storeURL
        self.state = Self.open(at: storeURL)
    }

    /// Tries to open the store again (for example after freeing space).
    public func retry() {
        state = Self.open(at: storeURL)
    }

    /// Moves the unreadable store aside (it is kept, renamed, next to the new
    /// one) and opens an empty store.
    public func startFresh() {
        Self.moveStoreAside(at: storeURL)
        state = Self.open(at: storeURL)
    }

    // MARK: Container

    /// The store lives in Application Support under a name tied to this schema
    /// generation. Stores from before the versioned schema are left untouched.
    public nonisolated static var defaultStoreURL: URL {
        let base = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "Dosar-v2.store")
    }

    public nonisolated static let schema = Schema(versionedSchema: DosarSchemaV2.self)

    /// A container for the on-disk store, or an in-memory one for tests and previews.
    public nonisolated static func makeContainer(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, url: storeURL ?? defaultStoreURL, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: DosarMigrationPlan.self, configurations: [configuration])
    }

    private static func open(at url: URL) -> State {
        do {
            return .ready(try makeContainer(storeURL: url))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func moveStoreAside(at url: URL) {
        let fileManager = FileManager.default
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent
        let siblings = (try? fileManager.contentsOfDirectory(atPath: directory.path())) ?? []
        for name in siblings where name.hasPrefix(baseName) {
            let source = directory.appending(path: name)
            let target = directory.appending(path: "unreadable-\(stamp)-\(name)")
            try? fileManager.moveItem(at: source, to: target)
        }
    }
}
