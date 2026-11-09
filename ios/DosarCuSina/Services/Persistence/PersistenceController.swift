import Foundation
import SwiftData
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Opens the household database once and shares it with the app, App Intents
/// and notification actions. A store that can't be opened never crashes the app:
/// - while the phone hasn't been unlocked since it started (a launch in the
///   background, say), the files can't be read yet: the state is
///   `.waitingForUnlock` and the store opens again by itself once they can;
/// - otherwise the state becomes `.failed` and the UI offers to retry or start fresh.
@MainActor
@Observable
public final class PersistenceController {
    public enum State {
        case ready(ModelContainer)
        /// The phone hasn't been unlocked since it started; the store opens as soon as it is.
        case waitingForUnlock
        case failed(StoreFailure)
    }

    /// Why the store didn't open, in terms the recovery screen can act on.
    public enum StoreFailure: Equatable, Sendable {
        /// The phone is full.
        case outOfSpace
        /// Anything else: the file can't be read as it is.
        case unreadable
    }

    public static let shared = PersistenceController()

    public private(set) var state: State

    /// The ready container, or nil while the store can't be opened.
    public var container: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    private let storeURL: URL
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let makeContainer: (URL) throws -> ModelContainer
    @ObservationIgnored private var unlockObserver: (any NSObjectProtocol)?

    public convenience init(storeURL: URL = PersistenceController.defaultStoreURL) {
        self.init(storeURL: storeURL, isProtectedDataAvailable: Self.systemProtectedDataAvailable, makeContainer: { try Self.makeContainer(storeURL: $0) })
    }

    init(
        storeURL: URL,
        isProtectedDataAvailable: @escaping @MainActor () -> Bool,
        makeContainer: @escaping (URL) throws -> ModelContainer
    ) {
        self.storeURL = storeURL
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.makeContainer = makeContainer
        self.state = .waitingForUnlock
        open()
    }

    /// Tries to open the store again (for example after freeing space).
    public func retry() {
        open()
    }

    /// Moves the unreadable store aside (it is kept, renamed, next to the new
    /// one) and opens an empty store. Never while the phone's files are still
    /// locked: then the store isn't broken, only waiting.
    public func startFresh() {
        guard isProtectedDataAvailable() else { return open() }
        Self.moveStoreAside(at: storeURL)
        open()
    }

    /// The phone's files can be read now: open the store if it was waiting.
    func protectedDataDidBecomeAvailable() {
        if case .waitingForUnlock = state { open() }
    }

    private func open() {
        do {
            state = .ready(try makeContainer(storeURL))
            stopWaiting()
        } catch {
            if !isProtectedDataAvailable() {
                state = .waitingForUnlock
                waitForUnlock()
            } else {
                state = .failed(SaveFailure.isOutOfSpace(error) ? .outOfSpace : .unreadable)
                stopWaiting()
            }
        }
    }

    private func waitForUnlock() {
        #if canImport(UIKit)
        guard unlockObserver == nil else { return }
        unlockObserver = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.protectedDataDidBecomeAvailable() }
        }
        #endif
    }

    private func stopWaiting() {
        if let unlockObserver { NotificationCenter.default.removeObserver(unlockObserver) }
        unlockObserver = nil
    }

    private static func systemProtectedDataAvailable() -> Bool {
        #if canImport(UIKit)
        return UIApplication.shared.isProtectedDataAvailable
        #else
        return true
        #endif
    }

    // MARK: Container

    /// The store lives in Application Support under a name tied to this schema
    /// generation. Stores from before the versioned schema are left untouched.
    public nonisolated static var defaultStoreURL: URL {
        let base = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "Dosar-v2.store")
    }

    public nonisolated static let schema = Schema(versionedSchema: DosarSchemaV7.self)

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
