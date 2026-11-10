import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Holds the backup screen's steps the way the system would, so tests can see each one and stop it.
@MainActor
final class RecordingBackupKeeper: BackupKeeper {
    final class Hold: BackupHold {
        let run: BackupRun
        let subtitle: String
        private(set) var outcome: Bool?
        init(run: BackupRun, subtitle: String) {
            self.run = run
            self.subtitle = subtitle
        }
        func end(success: Bool) { outcome = success }
    }

    private(set) var holds: [Hold] = []
    /// Stops every step as soon as it starts, as the person would from the system's progress.
    var stopsAtOnce = false

    func hold(_ run: BackupRun, title: String, subtitle: String) -> any BackupHold {
        let hold = Hold(run: run, subtitle: subtitle)
        holds.append(hold)
        if stopsAtOnce { run.cancel() }
        return hold
    }
}

/// A long backup step keeps going in the background with progress the system shows, can be
/// stopped there leaving nothing half-done, and waits for the phone to be unlocked before it
/// touches the binder's documents. Every value is a placeholder.
@MainActor
@Suite("A long backup keeps going in the background")
struct BackupInBackgroundTests {
    private func flow(_ household: BackupHousehold, keeper: RecordingBackupKeeper) throws -> (BackupFlow, URL) {
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(.succeed), appLockEnabled: { false }, observesAppLifecycle: false)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (BackupFlow(container: household.container, vault: vault, workDirectory: directory, inbox: directory.appending(path: "Inbox"), keeper: keeper), directory)
    }

    private func files(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter { $0 != "Inbox" }
    }

    // MARK: The run

    @Test func aStoppedRunStopsAtItsNextFile() throws {
        let run = BackupRun()
        try run.checkpoint(needsProtectedData: true)
        run.cancel()
        #expect(throws: CancellationError.self) { try run.checkpoint(needsProtectedData: false) }
        #expect(run.isCancelled)
    }

    @Test func stoppingFromTheSystemsProgressStopsTheRun() {
        let run = BackupRun()
        run.progress.cancel()
        #expect(run.isCancelled)
    }

    @Test func aStepThatNeedsTheDocumentsWaitsForTheUnlock() async throws {
        let run = BackupRun(protectedDataAvailable: false)
        try run.checkpoint(needsProtectedData: false)
        let waited = Task.detached { try run.checkpoint(needsProtectedData: true) }
        await Task.yield()
        run.protectedData(isAvailable: true)
        try await waited.value
        #expect(run.timesLocked == 0, "Locked before it started, not while it ran")
        run.protectedData(isAvailable: false)
        #expect(run.timesLocked == 1)
    }

    @Test func stoppingWakesAStepWaitingForTheUnlock() async {
        let run = BackupRun(protectedDataAvailable: false)
        let waited = Task.detached { try run.checkpoint(needsProtectedData: true) }
        await Task.yield()
        run.cancel()
        await #expect(throws: CancellationError.self) { try await waited.value }
    }

    @Test func theImportsUnitRunsAgainOnlyWhenThePhoneLockedWhileItRan() throws {
        struct Failed: Error {}
        let run = BackupRun()
        var attempts = 0
        let value = try run.writing { () throws -> Int in
            attempts += 1
            if attempts == 1 {
                run.protectedData(isAvailable: false)
                run.protectedData(isAvailable: true)
                throw Failed()
            }
            return 7
        }
        #expect(value == 7)
        #expect(attempts == 2)

        attempts = 0
        #expect(throws: Failed.self) {
            try run.writing { () throws -> Int in
                attempts += 1
                throw Failed()
            }
        }
        #expect(attempts == 1, "Any other failure is the failure")
    }

    // MARK: Making a copy

    @Test func aCopyShowsItsProgressAndIsHeldUntilItEnds() async throws {
        let household = try BackupHousehold()
        let keeper = RecordingBackupKeeper()
        let (flow, directory) = try flow(household, keeper: keeper)
        defer { try? FileManager.default.removeItem(at: directory) }
        await flow.export(password: nil)
        #expect(flow.exportURL != nil)
        let hold = try #require(keeper.holds.first)
        #expect(hold.outcome == true)
        #expect(hold.run.progress.totalUnitCount > 0)
        #expect(hold.run.progress.completedUnitCount == hold.run.progress.totalUnitCount, "The progress ends full")
        #expect(!hold.subtitle.isEmpty)
    }

    @Test func aCopyStoppedFromTheSystemLeavesNoFileAndSaysSo() async throws {
        let household = try BackupHousehold()
        let keeper = RecordingBackupKeeper()
        keeper.stopsAtOnce = true
        let (flow, directory) = try flow(household, keeper: keeper)
        defer { try? FileManager.default.removeItem(at: directory) }
        await flow.export(password: "parola-exemplu")
        #expect(flow.exportURL == nil)
        #expect(try files(in: directory).isEmpty, "Nothing half-written is left")
        #expect(flow.error?.message == BackupStopped.making.errorDescription)
        #expect(keeper.holds.first?.outcome == false)
        #expect(flow.work == nil)
    }

    @Test func aCopyWaitsForTheUnlockBeforeItReadsTheDocuments() async throws {
        let household = try BackupHousehold()
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let run = BackupRun(protectedDataAvailable: false)
        let export = Task { try await household.service.export(to: directory, password: nil, run: run) }
        // Locked: nothing is handed out.
        await Task.yield()
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).allSatisfy { $0.hasSuffix(".partial") })
        run.protectedData(isAvailable: true)
        let url = try await export.value
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) == [url.lastPathComponent])
    }

    // MARK: Bringing one in

    @Test func bringingACopyInIsHeldAndStoppingItChangesNothing() async throws {
        let household = try BackupHousehold()
        let keeper = RecordingBackupKeeper()
        let (flow, directory) = try flow(household, keeper: keeper)
        defer { try? FileManager.default.removeItem(at: directory) }
        await flow.export(password: nil)
        let backup = try #require(flow.exportURL)

        // Checked, then brought in "Înlocuiește tot" with the step stopped from the system.
        await flow.open(backup)
        let pending = try #require(flow.pending)
        let before = try ModelContext(household.container).fetchCount(FetchDescriptor<Asset>())
        _ = try household.actions.update(household.person, name: "Nume schimbat", values: household.person.values, notes: nil)
        keeper.stopsAtOnce = true
        await flow.runImport(pending, mode: .replace)
        #expect(flow.error?.message == BackupStopped.bringingIn.errorDescription)
        #expect(try household.asset(household.person.id).name == "Nume schimbat", "Nothing of the backup came in")
        #expect(try ModelContext(household.container).fetchCount(FetchDescriptor<Asset>()) == before)
        #expect(keeper.holds.last?.outcome == false)
        #expect(!FileManager.default.fileExists(atPath: pending.url.path(percentEncoded: false)), "The working copy goes")

        // Not stopped, it comes in whole, its progress full.
        keeper.stopsAtOnce = false
        flow.error = nil
        await flow.open(backup)
        let again = try #require(flow.pending)
        await flow.runImport(again, mode: .replace)
        #expect(flow.error == nil)
        let hold = try #require(keeper.holds.last)
        #expect(hold.outcome == true)
        #expect(hold.run.progress.completedUnitCount == hold.run.progress.totalUnitCount)
        #expect(try household.asset(household.person.id).name == "Manole Corina")
    }

    // MARK: The system's side

    @Test func theAppAllowsTheBackupStepsToContinue() throws {
        // The tests run inside the app, so its Info.plist is the main bundle's.
        let info = try #require(Bundle.main.infoDictionary)
        let allowed = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
        #expect(allowed.contains(SystemBackupKeeper.identifierPrefix + "*"))
        #expect(SystemBackupKeeper.identifierPrefix.hasPrefix((Bundle.main.bundleIdentifier ?? "") + "."), "Continued tasks start with the app's own identifier")
    }
}
