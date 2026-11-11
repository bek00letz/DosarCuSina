import Foundation
import SwiftData
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Opens the household database once and shares it with the app, App Intents
/// and notification actions, and decides whether it syncs with the person's own private
/// iCloud (`sync`, `SyncState`). A store that can't be opened never crashes the app:
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

    /// Whether the binder syncs with the person's own private iCloud, and why not.
    public enum SyncState: Equatable, Sendable {
        /// This build doesn't sync: TestFlight and the App Store, until the data layout has settled
        /// (`syncShipsInReleaseBuilds`), and the host of a test run.
        case notInThisBuild
        /// The person turned it off in Settings. Everything stays on the phone.
        case off
        /// Examples are in the binder: they stay on this phone, and so does the binder until
        /// they go (`ExampleDataService`). Sync starts again the next time the store opens.
        case waitingForExamples
        /// Syncing with the private database of `cloudKitContainer`.
        case on
    }

    public static let shared = PersistenceController()

    public private(set) var state: State
    public private(set) var sync: SyncState = .notInThisBuild

    /// The ready container, or nil while the store can't be opened.
    public var container: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    private let storeURL: URL
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let makeContainer: @MainActor (URL, Bool) throws -> ModelContainer
    @ObservationIgnored private let buildSyncs: Bool
    @ObservationIgnored private let personWantsSync: @MainActor () -> Bool
    @ObservationIgnored private let holdsExamples: @MainActor (ModelContainer) -> Bool
    @ObservationIgnored private let didOpenToSync: @MainActor () -> Void
    @ObservationIgnored private var unlockObserver: (any NSObjectProtocol)?

    public convenience init(storeURL: URL = PersistenceController.defaultStoreURL) {
        self.init(
            storeURL: storeURL,
            isProtectedDataAvailable: Self.systemProtectedDataAvailable,
            makeContainer: { try Self.makeContainer(storeURL: $0, syncs: $1) },
            buildSyncs: Self.syncIsBuiltIn,
            personWantsSync: { AppPreferences.shared.syncsWithICloud },
            holdsExamples: { Self.anyExamples(in: $0) },
            didOpenToSync: { SecretKeySharing.standard.start() }
        )
    }

    init(
        storeURL: URL,
        isProtectedDataAvailable: @escaping @MainActor () -> Bool,
        makeContainer: @escaping @MainActor (URL, Bool) throws -> ModelContainer,
        buildSyncs: Bool = false,
        personWantsSync: @escaping @MainActor () -> Bool = { true },
        holdsExamples: @escaping @MainActor (ModelContainer) -> Bool = { _ in false },
        didOpenToSync: @escaping @MainActor () -> Void = {}
    ) {
        self.storeURL = storeURL
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.makeContainer = makeContainer
        self.buildSyncs = buildSyncs
        self.personWantsSync = personWantsSync
        self.holdsExamples = holdsExamples
        self.didOpenToSync = didOpenToSync
        self.state = .waitingForUnlock
        open()
    }

    /// Opens the store again when whether it should sync changed: the person turned sync on or
    /// off, or the examples went. Nothing happens when the choice is the same. The screens keep
    /// their place: only the container under them changes.
    public func applySyncChoice() {
        guard let container else { return }
        let choice = Self.choice(builtIn: buildSyncs, wanted: personWantsSync(), holdsExamples: holdsExamples(container))
        guard choice != sync else { return }
        open()
    }

    /// The examples are about to come in: on a phone that syncs, the store opens again without
    /// iCloud first, so no example ever reaches it. Returns the container to load them into.
    public func containerForExamples() -> ModelContainer? {
        guard sync == .on else { return container }
        do {
            state = .ready(try makeContainer(storeURL, false))
            sync = .waitingForExamples
        } catch {
            open()
        }
        return container
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
            let (container, sync) = try openDecidingSync()
            state = .ready(container)
            self.sync = sync
            stopWaiting()
            // The binder syncs from now: this device's sealing key goes to iCloud Keychain at once,
            // so the codes it sealed open on the person's other devices (`SecretKeySharing`).
            if sync == .on { didOpenToSync() }
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

    /// The store, opened to sync or not. A store that would sync is looked at first without
    /// iCloud: examples in it keep it on this phone (`SyncState.waitingForExamples`).
    private func openDecidingSync() throws -> (ModelContainer, SyncState) {
        let choice = Self.choice(builtIn: buildSyncs, wanted: personWantsSync(), holdsExamples: false)
        guard choice == .on else { return (try makeContainer(storeURL, false), choice) }
        do {
            let local = try makeContainer(storeURL, false)
            if holdsExamples(local) { return (local, .waitingForExamples) }
        }
        return (try makeContainer(storeURL, true), .on)
    }

    /// What the store should do, from whether the build and the person want sync and whether
    /// examples are on the phone.
    nonisolated static func choice(builtIn: Bool, wanted: Bool, holdsExamples: Bool) -> SyncState {
        guard builtIn else { return .notInThisBuild }
        guard wanted else { return .off }
        return holdsExamples ? .waitingForExamples : .on
    }

    /// Whether any record of the household is an example (`isExample`).
    private static func anyExamples(in container: ModelContainer) -> Bool {
        let context = context(in: container)
        func any<M: PersistentModel>(_ descriptor: FetchDescriptor<M>) -> Bool {
            var descriptor = descriptor
            descriptor.fetchLimit = 1
            return ((try? context.fetchCount(descriptor)) ?? 0) > 0
        }
        return any(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample }))
            || any(FetchDescriptor<Obligation>(predicate: #Predicate { $0.isExample }))
            || any(FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.isExample }))
            || any(FetchDescriptor<ServiceItem>(predicate: #Predicate { $0.isExample }))
            || any(FetchDescriptor<MeasurementLog>(predicate: #Predicate { $0.isExample }))
            || any(FetchDescriptor<Attachment>(predicate: #Predicate { $0.isExample }))
            || any(FetchDescriptor<Provider>(predicate: #Predicate { $0.isExample }))
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

    public nonisolated static let schema = Schema(versionedSchema: DosarSchemaV13.self)

    // MARK: iCloud

    /// The person's own iCloud container: only its private database is used, never a shared or
    /// public one, and there is no server of ours.
    public nonisolated static let cloudKitContainer = "iCloud.com.ar.dosarcusina.app"

    /// **The one switch for shipping sync.** Development builds (Debug) sync with CloudKit's
    /// development environment; TestFlight and App Store builds (Release) keep the binder on the
    /// phone until this is true. Before turning it on: deploy the CloudKit schema to production in
    /// CloudKit Console (the owner does that, once the data layout has settled), then set this to
    /// `true` in a pull request of its own. Read only here.
    nonisolated static let syncShipsInReleaseBuilds = false

    /// Whether this build syncs at all: a development build, or a release one once sync ships. Never
    /// the host of a test run, whose binder is the Simulator's own.
    nonisolated static var syncIsBuiltIn: Bool {
        syncIsBuiltIn(debug: isDebugBuild, shipsInRelease: syncShipsInReleaseBuilds, testHost: BuildInfo.isTestHost)
    }

    nonisolated static func syncIsBuiltIn(debug: Bool, shipsInRelease: Bool, testHost: Bool) -> Bool {
        !testHost && (debug || shipsInRelease)
    }

    private nonisolated static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The store's configuration: the person's private iCloud database when it syncs, none otherwise.
    nonisolated static func configuration(storeURL: URL?, inMemory: Bool, syncs: Bool) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return ModelConfiguration(schema: schema, url: storeURL ?? defaultStoreURL, cloudKitDatabase: syncs ? .private(cloudKitContainer) : .none)
    }

    /// Containers open on the person's iCloud, so an import knows not to bring examples into them.
    private static var syncing: Set<ObjectIdentifier> = []

    /// Whether `container` syncs with iCloud.
    public static func syncs(_ container: ModelContainer) -> Bool {
        syncing.contains(ObjectIdentifier(container))
    }

    /// A container for the on-disk store, or an in-memory one for tests and previews. The one
    /// place a container is made: its main context saves only through the unit of work, and every
    /// context it gives says the change is the app's own (`localAuthor`), so a change that came
    /// from another device is told apart (`SyncedChanges`). An in-memory one never syncs.
    public static func makeContainer(storeURL: URL? = nil, inMemory: Bool = false, syncs: Bool = false) throws -> ModelContainer {
        let configuration = configuration(storeURL: storeURL, inMemory: inMemory, syncs: syncs && !inMemory)
        let container = try ModelContainer(for: schema, migrationPlan: DosarMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        container.mainContext.author = localAuthor
        if configuration.cloudKitContainerIdentifier != nil { syncing.insert(ObjectIdentifier(container)) }
        return container
    }

    /// Who made a change saved on this phone, in the store's history: the app itself.
    public nonisolated static let localAuthor = "app"

    // MARK: Contexts

    /// A context of its own on `container` (a backup written away from the main thread, a
    /// reader for search or the widgets): the one way the app makes a context. Like the main
    /// context, it saves only when the unit of work saves it, never by itself, so every save
    /// keeps change times, masks card numbers and can be rolled back (`UnitOfWork`). SwiftData
    /// saves a context by itself otherwise, around all of that.
    public nonisolated static func context(in container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.author = localAuthor
        return context
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
