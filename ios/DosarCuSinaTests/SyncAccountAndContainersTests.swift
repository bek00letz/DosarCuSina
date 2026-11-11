import CloudKit
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// iCloud sync around the store: the account as an input (none, another one, the same), iCloud's
/// own reports read into one health shown in plain words, a store that can't open with iCloud
/// staying open on the phone, the old container retired whenever the store reopens (every holder
/// lets go, nothing writes through it, examples wait until one that synced is gone), what follows
/// the binder starting where the store opens, a new device waiting for its binder before
/// examples, and an old reminder's "Am rezolvat" checked against the store. All without iCloud:
/// the account and the reports are made up. Every value is a placeholder.
@MainActor
@Suite("iCloud account and containers")
struct SyncAccountAndContainersTests {
    // MARK: A controller over in-memory stores

    /// The account the phone is signed into, changed by the test.
    final class Account: ICloudAccountReader, @unchecked Sendable {
        var value: ICloudAccount
        init(_ value: ICloudAccount) { self.value = value }
        func current() async -> ICloudAccount { value }
    }

    /// What the store was opened as, and what the test makes it do.
    final class Store: @unchecked Sendable {
        var opens: [Bool] = []
        var examples = false
        var wanted = true
        var failsToSync = false
        var copiesKept = 0
    }

    struct CouldNotOpen: Error {}

    private func controller(_ store: Store, account: Account, memory: SyncMemory = InMemorySyncMemory(firstDownloadFinishedFor: "a")) -> PersistenceController {
        PersistenceController(
            storeURL: URL.temporaryDirectory.appending(path: "sync-\(UUID().uuidString).store"),
            isProtectedDataAvailable: { true },
            makeContainer: { _, syncs in
                store.opens.append(syncs)
                if syncs, store.failsToSync { throw CouldNotOpen() }
                let container = try makeInMemoryContainer()
                if syncs { ContainerRetirement.markSyncing(container) }
                return container
            },
            buildSyncs: true,
            personWantsSync: { store.wanted },
            holdsExamples: { _ in store.examples },
            account: account,
            memory: memory,
            keepCopy: { _ in
                store.copiesKept += 1
                return URL.temporaryDirectory
            }
        )
    }

    private func syncingNow(_ persistence: PersistenceController) -> Bool {
        persistence.container.map(PersistenceController.syncs) ?? false
    }

    // MARK: The account

    @Test func theStoreOpensOnThePhoneFirstAndSyncsOnceTheAccountIsKnown() async {
        let store = Store()
        let memory = InMemorySyncMemory()
        let persistence = controller(store, account: Account(.signedIn(id: "a")), memory: memory)
        #expect(persistence.sync == .checkingAccount)
        #expect(store.opens == [false], "Open on the phone at once, never with iCloud before the account is known")

        await persistence.settleSync()
        #expect(persistence.sync == .on)
        #expect(store.opens == [false, true])
        #expect(syncingNow(persistence))
        #expect(memory.syncedAccount == "a", "The first account is the binder's")
    }

    @Test func withoutAnAccountTheBinderStaysOnThePhone() async {
        let store = Store()
        let persistence = controller(store, account: Account(.none))
        await persistence.settleSync()
        #expect(persistence.sync == .noAccount)
        #expect(!store.opens.contains(true), "Never opened with iCloud, so nothing can clear it")
        #expect(persistence.container != nil)
    }

    @Test func anotherAccountKeepsTheBinderOnThePhoneUntilThePersonChooses() async throws {
        let store = Store()
        let memory = InMemorySyncMemory(syncedAccount: "a", firstDownloadFinishedFor: "a")
        let account = Account(.signedIn(id: "b"))
        let persistence = controller(store, account: account, memory: memory)
        await persistence.settleSync()
        #expect(persistence.sync == .otherAccount)
        #expect(!store.opens.contains(true))

        try await persistence.syncWithThisAccount()
        #expect(store.copiesKept == 1, "A copy of the binder is kept before the other account's comes down")
        #expect(memory.syncedAccount == "b")
        #expect(persistence.sync == .on)
        #expect(syncingNow(persistence))
    }

    @Test func signingOutWhileSyncingReopensOnThePhone() async {
        let store = Store()
        let account = Account(.signedIn(id: "a"))
        let persistence = controller(store, account: account)
        await persistence.settleSync()
        let syncing = persistence.container
        #expect(persistence.sync == .on)

        account.value = .none
        await persistence.settleSync()
        #expect(persistence.sync == .noAccount)
        #expect(!syncingNow(persistence))
        if let syncing { #expect(ContainerRetirement.isRetired(syncing)) }

        // Signed in again with the same account: it syncs by itself.
        account.value = .signedIn(id: "a")
        await persistence.settleSync()
        #expect(persistence.sync == .on)
    }

    @Test func iCloudNotAnsweringWhileSyncingChangesNothing() async {
        let store = Store()
        let account = Account(.signedIn(id: "a"))
        let persistence = controller(store, account: account)
        await persistence.settleSync()
        let opens = store.opens.count
        account.value = .unknown
        await persistence.settleSync()
        #expect(persistence.sync == .on)
        #expect(store.opens.count == opens)
    }

    @Test("Which account, compared with the binder's", arguments: [
        (ICloudAccount.signedIn(id: "a"), String?.none, PersistenceController.AccountMatch.same),
        (.signedIn(id: "a"), "a", .same),
        (.signedIn(id: "b"), "a", .other),
        (.signedIn(id: nil), "a", .unknown),
        (.none, "a", .none),
        (.unknown, nil, .unknown),
    ])
    func theAccountMatch(account: ICloudAccount, synced: String?, expected: PersistenceController.AccountMatch) {
        #expect(PersistenceController.match(account, syncedWith: synced) == expected)
    }

    @Test("The choice, with the account and sync stopping by itself", arguments: [
        (PersistenceController.AccountMatch.same, PersistenceController.SyncPause?.none, PersistenceController.SyncState.on),
        (.none, nil, .noAccount),
        (.other, nil, .otherAccount),
        (.unknown, nil, .checkingAccount),
        (.same, .iCloudFull, .paused(.iCloudFull)),
        (.same, .couldNotStart, .paused(.couldNotStart)),
    ])
    func theChoiceWithTheAccount(account: PersistenceController.AccountMatch, pause: PersistenceController.SyncPause?, expected: PersistenceController.SyncState) {
        #expect(PersistenceController.choice(builtIn: true, wanted: true, holdsExamples: false, pause: pause, account: account) == expected)
        #expect(PersistenceController.choice(builtIn: true, wanted: true, holdsExamples: true, pause: pause, account: account) == .waitingForExamples)
        #expect(PersistenceController.choice(builtIn: true, wanted: false, holdsExamples: false, pause: pause, account: account) == .off)
        #expect(PersistenceController.choice(builtIn: false, wanted: true, holdsExamples: false, pause: pause, account: account) == .notInThisBuild)
    }

    // MARK: A store that can't open with iCloud

    @Test func aStoreThatCantOpenWithICloudStaysOpenOnThePhone() async {
        let store = Store()
        store.failsToSync = true
        let persistence = controller(store, account: Account(.signedIn(id: "a")))
        await persistence.settleSync()
        #expect(persistence.sync == .paused(.couldNotStart))
        guard case .ready = persistence.state else {
            Issue.record("The recovery screen is only for a store that can't open at all")
            return
        }
        #expect(!syncingNow(persistence))

        store.failsToSync = false
        persistence.retrySync()
        await persistence.settleSync()
        #expect(persistence.sync == .on)
    }

    // MARK: What iCloud reports

    @Test func aFullICloudStopsSyncUntilThereIsRoom() async {
        let store = Store()
        let persistence = controller(store, account: Account(.signedIn(id: "a")))
        await persistence.settleSync()
        #expect(persistence.sync == .on)

        persistence.record(SyncEvent(kind: .upload, finishedAt: noon("2026-11-11"), succeeded: false, problem: .iCloudFull))
        #expect(persistence.sync == .paused(.iCloudFull))
        #expect(!syncingNow(persistence), "On the phone, where a change of account can't clear what never went up")

        // There is room again: "Încearcă din nou".
        persistence.retrySync()
        await persistence.settleSync()
        #expect(persistence.sync == .on)
    }

    @Test func cloudKitErrorsAreReadIntoWhatThePersonCanDo() {
        func ck(_ code: CKError.Code, _ info: [String: Any] = [:]) -> NSError {
            NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: info)
        }
        #expect(SyncProblem(ck(.quotaExceeded)) == .iCloudFull)
        #expect(SyncProblem(ck(.notAuthenticated)) == .notSignedIn)
        #expect(SyncProblem(ck(.networkUnavailable)) == .offline)
        #expect(SyncProblem(ck(.requestRateLimited)) == .busy)
        #expect(SyncProblem(ck(.partialFailure, [CKPartialErrorsByItemIDKey: ["x": ck(.zoneBusy), "y": ck(.quotaExceeded)]])) == .iCloudFull,
                "One of several: the one the person must act on")
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [NSUnderlyingErrorKey: ck(.quotaExceeded)])
        #expect(SyncProblem(wrapped) == .iCloudFull, "Wrapped by Core Data")
        #expect(SyncProblem(NSError(domain: NSCocoaErrorDomain, code: 1)) == .other)
    }

    @Test func theHealthFollowsTheReports() {
        let memory = InMemorySyncMemory()
        let tracker = SyncHealthTracker(account: "a", memory: memory)
        #expect(tracker.health == .downloading, "Never downloaded here: a binder may be on its way")
        tracker.record(SyncEvent(kind: .setup, finishedAt: noon("2026-11-11"), succeeded: true))
        #expect(tracker.health == .downloading)
        tracker.record(SyncEvent(kind: .download, finishedAt: noon("2026-11-11"), succeeded: true))
        #expect(tracker.health == .upToDate(noon("2026-11-11")))
        #expect(memory.firstDownloadFinishedFor == "a")
        #expect(tracker.record(SyncEvent(kind: .upload, finishedAt: noon("2026-11-12"), succeeded: false, problem: .offline)) == .offline)
        #expect(tracker.health == .waitingForNetwork)
        tracker.record(SyncEvent(kind: .upload, finishedAt: noon("2026-11-12"), succeeded: false, problem: .busy))
        #expect(tracker.health == .retrying)

        let known = SyncHealthTracker(account: "a", memory: memory)
        #expect(known.health == .starting, "Downloaded here before: nothing is on its way")
    }

    @Test(arguments: [
        PersistenceController.SyncState.checkingAccount, .noAccount, .otherAccount, .paused(.iCloudFull), .paused(.couldNotStart), .on,
    ])
    func settingsSaysHowSyncIsGoingInPlainWords(state: PersistenceController.SyncState) throws {
        let status = try #require(SyncWording.status(sync: state, health: .waitingForNetwork, isStopping: false))
        for text in [status.title, status.detail ?? "", SyncWording.footer(for: state)] {
            #expect(!text.contains("!"))
            #expect(!text.contains("CloudKit"), "No jargon")
        }
        if status.tone == .attention, state != .on {
            #expect(status.detail != nil, "What happened comes with what to do")
        }
    }

    @Test func settingsSaysNothingExtraWhereSyncIsOffOrNotBuilt() {
        #expect(SyncWording.status(sync: .off, health: nil, isStopping: false) == nil)
        #expect(SyncWording.status(sync: .notInThisBuild, health: nil, isStopping: false) == nil)
        #expect(SyncWording.status(sync: .off, health: nil, isStopping: true)?.tone == .working, "Stopping is said until it has stopped")
    }

    // MARK: A new device

    @Test func aNewDeviceWaitsForItsBinderBeforeOfferingExamples() async {
        let store = Store()
        let persistence = controller(store, account: Account(.signedIn(id: "a")), memory: InMemorySyncMemory())
        #expect(persistence.binderMayBeArriving, "Signed in and never synced here: a binder may be on its way")
        await persistence.settleSync()
        #expect(persistence.sync == .on)
        #expect(!persistence.examplesMayLoad)
        await #expect(throws: PersistenceController.ExamplesWaitForICloud.self) {
            try await persistence.loadingExamples { _ in () }
        }

        persistence.record(SyncEvent(kind: .download, finishedAt: noon("2026-11-11"), succeeded: true))
        #expect(!persistence.binderMayBeArriving, "The first download finished: what is there is the binder")
        #expect(persistence.examplesMayLoad)
    }

    @Test func withoutAnAccountExamplesAreOfferedAtOnce() async {
        let store = Store()
        let persistence = controller(store, account: Account(.none), memory: InMemorySyncMemory())
        await persistence.settleSync()
        #expect(!persistence.binderMayBeArriving)
    }

    // MARK: Examples and the container that synced

    @Test func examplesAreWrittenOnlyOnceTheContainerThatSyncedIsGone() async throws {
        let store = Store()
        let persistence = controller(store, account: Account(.signedIn(id: "a")))
        await persistence.settleSync()
        #expect(persistence.sync == .on)
        weak let syncing = persistence.container

        let wroteSyncing = try await persistence.loadingExamples { container in
            (PersistenceController.syncs(container), syncing == nil)
        }
        #expect(!wroteSyncing.0, "Written into a store that doesn't sync")
        #expect(wroteSyncing.1, "The container that synced was gone before anything was written")
        #expect(persistence.sync == .waitingForExamples)
        #expect(!persistence.isStoppingSync)

        // Nothing settles them back into iCloud while they're there.
        store.examples = true
        await persistence.settleSync()
        #expect(persistence.sync == .waitingForExamples)
        #expect(!syncingNow(persistence))
    }

    // MARK: Retiring a container

    @Test func everyHolderLetsGoOfARetiredContainer() async throws {
        weak var gone: ModelContainer?
        var search: SearchIndexStore?
        var sideEffects: SideEffectsCoordinator?
        var synced: SyncedChanges?
        do {
            let container = try makeInMemoryContainer()
            gone = container
            search = SearchIndexStore(container: container)
            sideEffects = SideEffectsCoordinator(container: container, notificationClient: FakeNotificationCenter(status: .authorized),
                                                 widgetWriter: WidgetSnapshotWriter(directory: URL.temporaryDirectory.appending(path: UUID().uuidString)))
            synced = SyncedChanges(container: container)
            ContainerRetirement.retire(container)
            #expect(search?.isFollowing(container) == false)
            #expect(sideEffects?.isFollowing(container) == false)
        }
        await synced?.read()
        await sideEffects?.reconcileNow()
        #expect(gone == nil, "Nothing still holds it, so it is gone")
        _ = (search, sideEffects, synced)
    }

    @Test func nothingIsWrittenThroughARetiredContainer() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        ContainerRetirement.retire(container)
        context.insert(Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle))
        #expect(throws: BinderReopened.self) { try UnitOfWork.save(context) }
        #expect(try PersistenceController.context(in: container).fetchCount(FetchDescriptor<Asset>()) == 0)
        let own = PersistenceController.context(in: container)
        own.insert(Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle))
        #expect(throws: BinderReopened.self) { try UnitOfWork.performPrivate(in: own) { () } }
    }

    @Test func aReceiptFromARetiredContainerOffersNoUndo() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        try UnitOfWork.save(context)
        let renamed = try UnitOfWork.performUndoable(in: context) {
            car.name = "Dacia Logan 2015"
            try UnitOfWork.save(context)
        }
        #expect(renamed.receipt.canUndo)

        ContainerRetirement.retire(container)
        #expect(!renamed.receipt.canUndo)
        #expect(throws: UndoError.binderReopened) { try renamed.receipt.undo() }
        let id = car.id
        let stored = try #require(try PersistenceController.context(in: container).fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first)
        #expect(stored.name == "Dacia Logan 2015", "Nothing taken back through the old container")
        #expect(!UndoError.binderReopened.localizedDescription.contains("!"))
    }

    @Test func aContainerSyncsOnlyWhileItLives() throws {
        let container = try makeInMemoryContainer()
        ContainerRetirement.markSyncing(container)
        #expect(PersistenceController.syncs(container))
        let other = try makeInMemoryContainer()
        #expect(!PersistenceController.syncs(other), "Known by the container itself, never by an address another one can take")
    }

    // MARK: Following from where the store opens

    @Test func whatFollowsTheBinderStartsWhereTheStoreOpens() async {
        let store = Store()
        let persistence = controller(store, account: Account(.signedIn(id: "a")))
        var followed: [ObjectIdentifier] = []
        persistence.followEveryContainer { followed.append(ObjectIdentifier($0)) }
        #expect(followed.count == 1, "The container already open, at once")
        await persistence.settleSync()
        #expect(followed.count == 2, "And the one the store reopened under, before any screen")
        #expect(followed.last == persistence.container.map(ObjectIdentifier.init))
    }

    // MARK: An old reminder after another device completed it

    @Test func anOldReminderAfterAnotherDeviceCompletedItChangesNothing() async throws {
        let folder = URL.temporaryDirectory.appending(path: "remote-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let calendar = Calendar.bucharest
        let now = noon("2026-12-03")
        let container = try PersistenceController.makeContainer(storeURL: folder.appending(path: "Dosar.store"))
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let rent = try ObligationActions(context: context, calendar: calendar, now: { now })
            .create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-12-05"), for: nil, recurrence: .interval(.months(1), anchor: .dueDate))
        let id = rent.id

        // The other device completed December; iCloud writes it under the store.
        let fromICloud = ModelContext(container)
        fromICloud.author = "NSCloudKitMirroringDelegate.import"
        let theirs = try #require(try fromICloud.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })).first)
        theirs.dueDay = CalendarDay("2027-01-05")
        try fromICloud.save()

        // This phone's December reminder: "Am rezolvat".
        let failures = OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)")
        let center = FakeNotificationCenter(status: .authorized)
        let coordinator = SideEffectsCoordinator(container: container, notificationClient: center,
                                                 widgetWriter: WidgetSnapshotWriter(directory: folder), calendar: calendar, now: { now })
        let outcome = try await IntentEngine.perform(OutsideRequest(obligationId: id, cycle: CalendarDay("2026-12-05"), action: .complete, surface: .notification),
                                                     container: container, sideEffects: { _ in coordinator }, failures: failures, calendar: calendar, now: { now })
        #expect(outcome == .skipped, "December was closed on the other device")
        let stored = try #require(try PersistenceController.context(in: container).fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })).first)
        #expect(stored.dueDay == CalendarDay("2027-01-05"), "January stays open: nothing completed a second time")
        #expect(stored.history.isEmpty)
    }

    // MARK: Examples, looked for cheaply

    @Test func examplesAreFoundByTheFirstOne() throws {
        let container = try makeInMemoryContainer()
        #expect(!PersistenceController.anyExamples(in: container))
        try ExampleDataService(context: container.mainContext).loadExamples()
        #expect(PersistenceController.anyExamples(in: container))
    }
}
