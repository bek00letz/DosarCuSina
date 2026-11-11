import CloudKit
import CoreData
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
///
/// The store always opens first on the phone alone, so the app, its reminders and a launch in
/// the background have the binder at once. It opens with iCloud only once it is known that it
/// may (`settleSync`): the build and the person want it, no example is in it, and the phone is
/// signed into the iCloud account the binder synced with before (or its first one). iCloud's
/// mirroring clears a store's copy on the phone when the account it synced with goes or
/// changes, with whatever hadn't gone up yet, so a store never opens with iCloud for another
/// account or none: then it stays on the phone, and Settings says why and what to do.
///
/// Whenever the store opens again under another container, the old one is retired
/// (`ContainerRetirement`): everything that held it lets go and nothing writes through it
/// again. One that synced is waited for until it is gone before examples are written, so it
/// can't send them.
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
        /// they go (`ExampleDataService`). Sync starts again the next time it is settled.
        case waitingForExamples
        /// The iCloud account is being asked about; the binder is open on the phone meanwhile.
        case checkingAccount
        /// The phone isn't signed into iCloud (or iCloud is off for the app). Everything stays on
        /// the phone; sync starts by itself once it is signed in again with the same account.
        case noAccount
        /// The phone is signed into another iCloud account than the one the binder synced with.
        /// The binder stays on the phone until the person chooses to sync with this one
        /// (`syncWithThisAccount`), which keeps a copy of it first.
        case otherAccount
        /// Sync stopped by itself and waits for the person (`retrySync`).
        case paused(SyncPause)
        /// Syncing with the private database of `cloudKitContainer`.
        case on
    }

    /// Why sync stopped by itself.
    public enum SyncPause: Equatable, Sendable {
        /// The person's iCloud storage is full: nothing more could go up, so the binder stays on
        /// the phone (where a change of account can't clear what never went up) until there's room.
        case iCloudFull
        /// The store couldn't be opened with iCloud. It is open on the phone, whole.
        case couldNotStart
    }

    /// How the iCloud account compares with the one the binder synced with.
    enum AccountMatch: Equatable, Sendable {
        /// Not asked yet, or iCloud couldn't say.
        case unknown
        case none
        case other
        /// The same account, or the first one the binder syncs with.
        case same
    }

    /// Examples can't come in while a container that synced is still going; past this, something
    /// still holds it, and the examples aren't loaded rather than risk reaching iCloud.
    static let syncStopBound: Duration = .seconds(5)

    public static let shared = PersistenceController()

    public private(set) var state: State
    public private(set) var sync: SyncState = .notInThisBuild
    /// How sync is going, from iCloud's own reports; nil while the binder doesn't sync.
    public private(set) var health: SyncHealth?
    /// A container that synced was retired and isn't gone yet: Settings says sync is stopping.
    public private(set) var isStoppingSync = false
    /// Whether the person's binder may still be coming down from iCloud on this phone: the first
    /// download for this account hasn't finished. Examples wait until it is known the iCloud
    /// binder is empty (`examplesMayLoad`).
    public private(set) var binderMayBeArriving = false

    /// The ready container, or nil while the store can't be opened.
    public var container: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    /// Whether examples may come in now: not while the person's binder may still be on its way.
    public var examplesMayLoad: Bool { !binderMayBeArriving }

    private let storeURL: URL
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let makeContainer: @MainActor (URL, Bool) throws -> ModelContainer
    @ObservationIgnored private let buildSyncs: Bool
    @ObservationIgnored private let personWantsSync: @MainActor () -> Bool
    @ObservationIgnored private let holdsExamples: @Sendable (ModelContainer) -> Bool
    @ObservationIgnored private let account: any ICloudAccountReader
    @ObservationIgnored private let memory: SyncMemory
    @ObservationIgnored private let keepCopy: @MainActor (ModelContainer) async throws -> URL
    @ObservationIgnored private let didOpenToSync: @MainActor () -> Void
    @ObservationIgnored private var unlockObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var systemObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var pause: SyncPause?
    @ObservationIgnored private var tracker: SyncHealthTracker?
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var retiringSyncing = 0
    @ObservationIgnored private var syncStopWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var openedHandlers: [@MainActor (ModelContainer) -> Void] = []

    public convenience init(storeURL: URL = PersistenceController.defaultStoreURL) {
        let builtIn = Self.syncIsBuiltIn
        self.init(
            storeURL: storeURL,
            isProtectedDataAvailable: Self.systemProtectedDataAvailable,
            makeContainer: { try Self.makeContainer(storeURL: $0, syncs: $1) },
            buildSyncs: builtIn,
            personWantsSync: { AppPreferences.shared.syncsWithICloud },
            holdsExamples: { Self.anyExamples(in: $0) },
            account: SystemICloudAccountReader(),
            memory: DeviceSyncMemory.shared,
            keepCopy: { try await KeptCopies.keep(container: $0) },
            didOpenToSync: { SecretKeySharing.standard.start() }
        )
        if builtIn { observeTheSystem() }
    }

    init(
        storeURL: URL,
        isProtectedDataAvailable: @escaping @MainActor () -> Bool,
        makeContainer: @escaping @MainActor (URL, Bool) throws -> ModelContainer,
        buildSyncs: Bool = false,
        personWantsSync: @escaping @MainActor () -> Bool = { true },
        holdsExamples: @escaping @Sendable (ModelContainer) -> Bool = { _ in false },
        account: any ICloudAccountReader = SignedIn(),
        memory: SyncMemory = InMemorySyncMemory(),
        keepCopy: @escaping @MainActor (ModelContainer) async throws -> URL = { _ in URL.temporaryDirectory },
        didOpenToSync: @escaping @MainActor () -> Void = {}
    ) {
        self.storeURL = storeURL
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.makeContainer = makeContainer
        self.buildSyncs = buildSyncs
        self.personWantsSync = personWantsSync
        self.holdsExamples = holdsExamples
        self.account = account
        self.memory = memory
        self.keepCopy = keepCopy
        self.didOpenToSync = didOpenToSync
        self.state = .waitingForUnlock
        open()
    }

    /// An account that is always the same one, for tests and previews.
    struct SignedIn: ICloudAccountReader {
        var id = "placeholder-account"
        func current() async -> ICloudAccount { .signedIn(id: id) }
    }

    // MARK: Following the container

    /// Runs `handler` with the container now (when it is open) and every time the store opens
    /// under a new one, before any screen draws it: what follows the binder outside a screen
    /// (reminders, the badge, widgets, Spotlight, another device's changes) starts from here, so
    /// it follows in a launch in the background too.
    public func followEveryContainer(_ handler: @escaping @MainActor (ModelContainer) -> Void) {
        openedHandlers.append(handler)
        if let container { handler(container) }
    }

    // MARK: Deciding whether the binder syncs

    /// Settles whether the binder syncs, after something it depends on may have changed: the
    /// person turned sync on or off, the examples went, the app came back, the iCloud account
    /// changed. Nothing happens when the choice is the same. The screens keep their place: only
    /// the container under them changes.
    public func applySyncChoice() {
        Task { await settleSync() }
    }

    /// Settles whether the binder syncs, and returns once it is settled. Calls run one after
    /// another, each on what is true when it runs.
    func settleSync() async {
        let previous = settling
        let run = Task { [weak self] in
            await previous?.value
            await self?.settleNow()
        }
        settling = run
        await run.value
    }

    private func settleNow() async {
        guard let container else { return }
        guard buildSyncs, personWantsSync() else {
            if ContainerRetirement.syncs(container) {
                reopen(syncs: false, as: Self.choice(builtIn: buildSyncs, wanted: personWantsSync(), holdsExamples: false, pause: nil, account: .same))
            } else {
                sync = Self.choice(builtIn: buildSyncs, wanted: personWantsSync(), holdsExamples: false, pause: nil, account: .same)
            }
            followArrival()
            return
        }
        if ContainerRetirement.syncs(container), pause == nil, sync == .on {
            // Already syncing: only a change of account matters, and examples can't be in it.
            let match = await accountMatch()
            guard self.container === container, sync == .on else { return }
            // iCloud not answering just now (no network) changes nothing; no account, or another, does.
            if match == .none || match == .other { reopen(syncs: false, as: Self.choice(builtIn: true, wanted: true, holdsExamples: false, pause: nil, account: match)) }
            followArrival()
            return
        }
        guard examplesComing == 0 else { return }
        // Just turned on: say so while iCloud answers.
        if sync == .off || sync == .notInThisBuild { sync = .checkingAccount }
        followArrival()
        let match = await accountMatch()
        // Examples are looked for only when the binder would otherwise sync, away from the main thread.
        var examples = false
        if match == .same, pause == nil {
            let holdsExamples = holdsExamples
            examples = await Task.detached { holdsExamples(container) }.value
        }
        guard self.container === container, examplesComing == 0 else { return }
        let choice = Self.choice(builtIn: true, wanted: personWantsSync(), holdsExamples: examples, pause: pause, account: match)
        if choice == .on {
            if case .signedIn(let id?) = lastAccount, memory.syncedAccount == nil { memory.syncedAccount = id }
            reopen(syncs: true, as: .on)
        } else {
            sync = choice
        }
        followArrival()
    }

    @ObservationIgnored private var lastAccount: ICloudAccount = .unknown

    /// Asks iCloud which account the phone is signed into, and compares it with the one the
    /// binder synced with.
    private func accountMatch() async -> AccountMatch {
        let current = await account.current()
        lastAccount = current
        return Self.match(current, syncedWith: memory.syncedAccount)
    }

    nonisolated static func match(_ account: ICloudAccount, syncedWith synced: String?) -> AccountMatch {
        switch account {
        case .none: return .none
        case .unknown: return .unknown
        case .signedIn(let id?):
            guard let synced else { return .same }
            return id == synced ? .same : .other
        case .signedIn(nil):
            // Signed in, but iCloud didn't say who: it can't be told apart from another account.
            return .unknown
        }
    }

    /// What the store should do, from whether the build and the person want sync, whether
    /// examples are on the phone, whether sync stopped by itself, and the iCloud account.
    nonisolated static func choice(builtIn: Bool, wanted: Bool, holdsExamples: Bool, pause: SyncPause? = nil, account: AccountMatch = .same) -> SyncState {
        guard builtIn else { return .notInThisBuild }
        guard wanted else { return .off }
        if holdsExamples { return .waitingForExamples }
        if let pause { return .paused(pause) }
        switch account {
        case .unknown: return .checkingAccount
        case .none: return .noAccount
        case .other: return .otherAccount
        case .same: return .on
        }
    }

    /// The app came back to the screen: the person may have signed into iCloud, or into another
    /// account, meanwhile. Settled again only where the account decides; a change that waits for
    /// the screen to be away (examples gone) still waits for it.
    public func accountMayHaveChanged() {
        switch sync {
        case .on, .checkingAccount, .noAccount, .otherAccount: applySyncChoice()
        case .notInThisBuild, .off, .waitingForExamples, .paused: break
        }
    }

    /// Sync stopped by itself (iCloud full, couldn't start): try again now.
    public func retrySync() {
        pause = nil
        applySyncChoice()
    }

    /// "Sincronizează cu contul acesta": the phone is signed into another account than the one
    /// the binder synced with. A copy of the binder is kept on the phone first (`KeptCopies`,
    /// offered in Settings to bring back in), then the binder syncs with this account, whose own
    /// binder comes down in its place.
    public func syncWithThisAccount() async throws {
        guard sync == .otherAccount, let container else { return }
        guard case .signedIn(let id?) = await account.current() else { throw AccountUnreadable() }
        _ = try await keepCopy(container)
        memory.syncedAccount = id
        await settleSync()
    }

    /// iCloud couldn't say which account the phone is signed into.
    struct AccountUnreadable: LocalizedError {
        var errorDescription: String? {
            String(localized: "iCloud nu a spus încă ce cont e pe telefon. Încearcă din nou peste un minut.",
                   comment: "Switching sync to the phone's iCloud account failed because iCloud didn't say which account it is.")
        }
    }

    // MARK: Examples

    /// Examples being written now: whether the binder syncs isn't settled meanwhile.
    @ObservationIgnored private var examplesComing = 0

    /// Writes the examples (`write`, given the container to write them into): on a phone that
    /// syncs, the store opens again without iCloud first, and the container that synced is
    /// waited for until it is gone, so no example ever reaches iCloud. Whether the binder syncs
    /// isn't settled while they are written; after, it waits for them to go
    /// (`SyncState.waitingForExamples`). Refused while the person's binder may still be on its
    /// way from iCloud (`examplesMayLoad`).
    public func loadingExamples<T>(_ write: (ModelContainer) throws -> T) async throws -> T {
        guard examplesMayLoad else { throw ExamplesWaitForICloud() }
        examplesComing += 1
        defer { examplesComing -= 1 }
        await settling?.value
        guard container != nil else { throw ExamplesNotNow() }
        // Never held across the wait below: holding it would keep it from going.
        if let current = container, ContainerRetirement.syncs(current) {
            reopen(syncs: false, as: .waitingForExamples)
        }
        guard await syncStopped(within: Self.syncStopBound), let local = self.container, !ContainerRetirement.syncs(local) else {
            throw ExamplesNotNow()
        }
        if buildSyncs, personWantsSync() { sync = .waitingForExamples }
        followArrival()
        return try write(local)
    }

    /// Examples wait while the person's binder may still be coming down from iCloud.
    public struct ExamplesWaitForICloud: LocalizedError, Equatable {
        public var errorDescription: String? {
            String(localized: "Aștept întâi dosarul tău din iCloud. Dacă e gol, poți încărca exemplele după.",
                   comment: "Examples refused while the person's binder may still be coming down from iCloud.")
        }
    }

    /// The store couldn't stop syncing in time for the examples.
    public struct ExamplesNotNow: LocalizedError, Equatable {
        public var errorDescription: String? {
            String(localized: "Nu am putut opri sincronizarea pentru exemple. Închide aplicația, deschide-o din nou și încearcă iar.",
                   comment: "Examples couldn't load because sync didn't stop in time.")
        }
    }

    /// Returns true once no retired container that synced is left, false past `bound`.
    func syncStopped(within bound: Duration) async -> Bool {
        guard retiringSyncing > 0 else { return true }
        let token = UUID()
        return await withCheckedContinuation { continuation in
            syncStopWaiters[token] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: bound)
                self?.syncStopWaiters.removeValue(forKey: token)?.resume(returning: false)
            }
        }
    }

    // MARK: Opening

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

    /// Opens the store on the phone alone, then settles whether it syncs.
    private func open() {
        do {
            let local = try makeContainer(storeURL, false)
            let previous = container
            if let previous { retire(previous) }
            state = .ready(local)
            sync = Self.choice(builtIn: buildSyncs, wanted: personWantsSync(), holdsExamples: false, pause: pause, account: .unknown)
            stopWaiting()
            followArrival()
            opened(local)
            if buildSyncs, personWantsSync() { applySyncChoice() }
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

    /// Opens the store again under a new container, with iCloud or without, and retires the old
    /// one. A store that can't be opened with iCloud stays open on the phone as it is
    /// (`SyncPause.couldNotStart`): the recovery screen is only for a store that can't open at all.
    private func reopen(syncs: Bool, as newState: SyncState) {
        let fresh: ModelContainer
        do {
            fresh = try makeContainer(storeURL, syncs)
        } catch {
            PersistenceLog.logger.error("The store couldn't open \(syncs ? "with" : "without", privacy: .public) iCloud: \(String(describing: type(of: error)), privacy: .public).")
            if syncs {
                pause = .couldNotStart
                sync = .paused(.couldNotStart)
            }
            followArrival()
            return
        }
        if let old = container { retire(old) }
        state = .ready(fresh)
        sync = newState
        health = nil
        tracker = nil
        if syncs {
            var account = memory.syncedAccount
            if case .signedIn(let id?) = lastAccount { account = id }
            let tracker = SyncHealthTracker(account: account, memory: memory)
            self.tracker = tracker
            health = tracker.health
        }
        followArrival()
        opened(fresh)
        // The binder syncs from now: this device's sealing key goes to iCloud Keychain at once,
        // so the codes it sealed open on the person's other devices (`SecretKeySharing`).
        if syncs { didOpenToSync() }
    }

    /// Retires `old`: every holder lets go of it and nothing writes through it again. One that
    /// synced counts until it is gone (`isStoppingSync`).
    private func retire(_ old: ModelContainer) {
        if ContainerRetirement.syncs(old) {
            retiringSyncing += 1
            isStoppingSync = true
            ContainerRetirement.whenGone(old) { [weak self] in self?.syncingContainerGone() }
        }
        ContainerRetirement.retire(old)
    }

    private func syncingContainerGone() {
        retiringSyncing = max(0, retiringSyncing - 1)
        guard retiringSyncing == 0 else { return }
        isStoppingSync = false
        let waiters = syncStopWaiters
        syncStopWaiters = [:]
        for waiter in waiters.values { waiter.resume(returning: true) }
    }

    private func opened(_ container: ModelContainer) {
        for handler in openedHandlers { handler(container) }
    }

    /// Whether the person's binder may still be on its way: sync is wanted and this phone never
    /// finished a first download for the account.
    private func followArrival() {
        let arriving: Bool
        switch sync {
        case .on: arriving = tracker?.firstDownloadFinished == false
        case .checkingAccount: arriving = memory.firstDownloadFinishedFor == nil && memory.syncedAccount == nil
        default: arriving = false
        }
        if arriving != binderMayBeArriving { binderMayBeArriving = arriving }
        // The app's own steps on what is missing read it there, from any thread (`CloudArrival`).
        if let container { CloudArrival.firstDownload(pending: arriving, in: container) }
    }

    // MARK: What iCloud reports

    /// Takes in one of the mirroring's reports. A full iCloud stops sync on this phone until there
    /// is room (`SyncPause.iCloudFull`); iCloud saying no one is signed in asks for the account again.
    func record(_ event: SyncEvent) {
        guard sync == .on, let tracker else { return }
        if let container { CloudArrival.follow(event, in: container) }
        let problem = tracker.record(event)
        if health != tracker.health { health = tracker.health }
        followArrival()
        switch problem {
        case .iCloudFull?:
            pause = .iCloudFull
            reopen(syncs: false, as: .paused(.iCloudFull))
        case .notSignedIn?:
            applySyncChoice()
        default:
            break
        }
    }

    /// Follows what the system says about iCloud: the account changing, and the mirroring's reports.
    private func observeTheSystem() {
        let center = NotificationCenter.default
        systemObservers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySyncChoice() }
        })
        systemObservers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let event = SyncEvent(raw) else { return }
            MainActor.assumeIsolated { self?.record(event) }
        })
    }

    /// Whether any record of the household is an example (`isExample`). Stops at the first one
    /// found, and runs away from the main thread.
    nonisolated static func anyExamples(in container: ModelContainer) -> Bool {
        let context = context(in: container)
        func any<M: PersistentModel>(_ descriptor: FetchDescriptor<M>) -> Bool {
            var descriptor = descriptor
            descriptor.fetchLimit = 1
            return !((try? context.fetchIdentifiers(descriptor)) ?? []).isEmpty
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

    public nonisolated static let schema = Schema(versionedSchema: DosarSchemaV14.self)

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

    /// Whether `container` syncs with iCloud, so an import knows not to bring examples into it.
    /// Kept on the container itself (`ContainerRetirement.markSyncing`), so it goes with it.
    public nonisolated static func syncs(_ container: ModelContainer) -> Bool {
        ContainerRetirement.syncs(container)
    }

    /// A container for the on-disk store, or an in-memory one for tests and previews. The one
    /// place a container is made: its main context saves only through the unit of work, and every
    /// context it gives says the change is the app's own (`localAuthor`), so a change that came
    /// from another device is told apart (`SyncedChanges`). An in-memory one never syncs.
    ///
    /// Before anything reads it, an upgrade that stopped halfway is finished from what its stages
    /// carried (`MigrationCarry.finishPending`); if that can't be done yet, the store doesn't open
    /// (the recovery screen, or a wait for the phone's unlock), so nothing ever reads it half
    /// upgraded. This device's section locks are read again if they couldn't be before.
    public static func makeContainer(storeURL: URL? = nil, inMemory: Bool = false, syncs: Bool = false) throws -> ModelContainer {
        let configuration = configuration(storeURL: storeURL, inMemory: inMemory, syncs: syncs && !inMemory)
        let container = try ModelContainer(for: schema, migrationPlan: DosarMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        container.mainContext.author = localAuthor
        if !configuration.isStoredInMemoryOnly {
            try MigrationCarry.finishPending(in: container)
            SectionLocks.of(container).readAgainIfUnread()
        }
        if configuration.cloudKitContainerIdentifier != nil { ContainerRetirement.markSyncing(container) }
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

    /// Moves the store's files aside, with any carry of an upgrade under way (`MigrationCarry`),
    /// which belongs to that store. This device's section locks stay where they are: they are the
    /// device's choices, not the binder's, and the binder that comes back (from iCloud, or a
    /// backup) keeps them (`SectionLocks`).
    static func moveStoreAside(at url: URL) {
        let fileManager = FileManager.default
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent
        let locks = SectionLocks.file(forStoreAt: url).lastPathComponent
        let siblings = (try? fileManager.contentsOfDirectory(atPath: directory.path())) ?? []
        for name in siblings where name.hasPrefix(baseName) && !name.hasPrefix(locks) {
            let source = directory.appending(path: name)
            let target = directory.appending(path: "unreadable-\(stamp)-\(name)")
            try? fileManager.moveItem(at: source, to: target)
        }
    }
}
