import Foundation
import SwiftData
import Observation

/// Everything the backup screen does, in one place the tests can drive:
///
/// - **Export** asks for Face ID or the passcode first whenever any lock is on,
///   then writes (and, with a password, encrypts) the binder to a file away from the
///   main thread, a piece at a time.
/// - **Import** copies the chosen file somewhere only the app reads, removes a
///   file the system handed over through "Open in", and checks it away from the
///   main thread. Only a short summary is kept while the person decides; the
///   file is read again when they confirm, its documents' files through a folder of
///   their own, so a backup of any size is never held in memory.
/// - **Bringing a backup in**, either way ("Adaugă" or "Înlocuiește tot"), asks for
///   Face ID or the passcode first whenever any lock is on.
/// - **One thing at a time:** the work is marked started before Face ID is asked, so a
///   second tap while the prompt is up starts nothing.
/// - **It keeps going in the background.** Making a copy, checking one and bringing one in each
///   run as a `BackupRun` the system keeps going once the person leaves the app or locks the phone
///   (`BackupKeeper`), with its progress shown by the system and a way to stop it there. A step
///   stopped that way leaves nothing half-done and says so in plain words (`BackupStopped`).
@MainActor
@Observable
final class BackupFlow {
    /// A backup read and waiting for the person to choose how to bring it in.
    struct PendingImport: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let password: String?
        let summary: ArchiveSummary
    }

    /// A password-protected backup waiting for its password.
    struct LockedFile: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        /// The last password tried didn't open it.
        var wasWrong = false
    }

    enum Work: Equatable {
        /// Face ID or the passcode is being asked before an export or an import.
        case confirming
        case exporting
        case reading
        case importing
    }

    private(set) var work: Work?
    var exportURL: URL?
    var pending: PendingImport?
    var lockedFile: LockedFile?
    private(set) var resultText: String?
    var error: UserFacingError?
    private(set) var doneCount = 0

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let vault: BiometricVaultManager
    @ObservationIgnored private let workDirectory: URL
    @ObservationIgnored private let inbox: URL
    @ObservationIgnored private let keeper: any BackupKeeper

    init(
        container: ModelContainer,
        vault: BiometricVaultManager,
        workDirectory: URL = .temporaryDirectory,
        inbox: URL = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory),
        keeper: any BackupKeeper = SystemBackupKeeper.shared
    ) {
        self.container = container
        self.vault = vault
        self.workDirectory = workDirectory
        self.inbox = inbox
        self.keeper = keeper
    }

    /// What the system shows above a backup step while it runs.
    private static var title: String { String(localized: "Copia de siguranță", comment: "Title of the system's progress while a backup step runs in the background.") }

    /// Runs `body` as one step the system keeps going in the background, and ends its hold with
    /// the step's outcome. A step the person or the system stopped throws `stopped`.
    private func keptGoing<T>(_ subtitle: String, stopped: BackupStopped, _ body: (BackupRun) async throws -> T) async throws -> T {
        let run = BackupRun()
        let hold = keeper.hold(run, title: Self.title, subtitle: subtitle)
        do {
            let value = try await body(run)
            hold.end(success: true)
            return value
        } catch {
            hold.end(success: false)
            if error is CancellationError || run.isCancelled { throw stopped }
            throw error
        }
    }

    /// Whether a section of the household is behind Face ID.
    private var anySectionLocked: Bool {
        ((try? container.mainContext.fetch(FetchDescriptor<CategoryTemplate>())) ?? []).contains(where: \.isSensitive)
    }

    /// Face ID or the passcode for the whole binder, whenever any lock is on. The work is
    /// already marked started, so nothing else starts while the prompt is up.
    private func confirmWholeBinder(_ reason: String) async -> Bool {
        work = .confirming
        return await vault.confirmWholeBinder(anySectionLocked: anySectionLocked, reason: reason) == .success
    }

    // MARK: Export

    /// Makes a backup, with or without a password. Nothing is written unless
    /// Face ID or the passcode succeeded (when any lock is on).
    func export(password: String?) async {
        guard work == nil else { return }
        defer { work = nil }
        let reason = String(localized: "Fă o copie de siguranță a dosarului.", comment: "Face ID reason before exporting a backup.")
        guard await confirmWholeBinder(reason) else { return }
        work = .exporting
        do {
            let service = DossierArchiveService(container: container)
            let directory = workDirectory
            exportURL = try await keptGoing(String(localized: "Se face copia…", comment: "Subtitle of the system's progress while a backup is made."), stopped: .making) { run in
                try await service.export(to: directory, password: password, run: run)
            }
        } catch {
            self.error = UserFacingError(error, doing: String(localized: "Copia nu s-a făcut", comment: "Title of an export error."))
        }
    }

    /// The share sheet closed: the temporary file goes.
    func finishSharing() {
        if let exportURL { BackupFiles.remove(exportURL) }
        exportURL = nil
    }

    // MARK: Import

    /// Opens a backup the person picked or opened from another app.
    func open(_ url: URL) async {
        guard work == nil else { return }
        work = .reading
        defer { work = nil }
        removeLeftoverCopies()
        let copy: URL
        do {
            copy = try takeCopy(of: url)
        } catch {
            self.error = UserFacingError(error, doing: String(localized: "Copia nu se deschide", comment: "Title of an import error."))
            return
        }
        await read(copy, password: nil)
    }

    /// Tries a password on a backup that asked for one.
    func unlock(_ file: LockedFile, with password: String) async {
        guard work == nil else { return }
        lockedFile = nil
        work = .reading
        defer { work = nil }
        await read(file.url, password: password)
    }

    /// The person chose not to bring a backup in: its working copy goes.
    func discard(_ url: URL) {
        BackupFiles.remove(url)
        if pending?.url == url { pending = nil }
        if lockedFile?.url == url { lockedFile = nil }
    }

    /// Brings a backup in, either way. It asks for Face ID or the passcode first whenever
    /// any lock is on: what comes in lands among the locked sections, and replacing
    /// everything can't be undone. Without it, the backup waits as it was.
    func runImport(_ pending: PendingImport, mode: ArchiveImportMode) async {
        guard work == nil else { return }
        self.pending = nil
        defer { work = nil }
        let reason = switch mode {
        case .replace: String(localized: "Înlocuiește tot dosarul cu copia.", comment: "Face ID reason before replacing everything with a backup.")
        case .merge: String(localized: "Adaugă în dosar ce e în copie.", comment: "Face ID reason before adding a backup's records to the binder.")
        }
        guard await confirmWholeBinder(reason) else {
            self.pending = pending
            return
        }
        work = .importing
        let staging = Self.stagingFolder(for: pending.url)
        defer {
            BackupFiles.remove(staging)
            BackupFiles.remove(pending.url)
        }
        do {
            let service = DossierArchiveService(container: container)
            let result = try await keptGoing(String(localized: "Se pune copia înapoi…", comment: "Subtitle of the system's progress while a backup is brought in."), stopped: .bringingIn) { run in
                // Read while the phone may lock: the copy is open to it while this works on it.
                try? BackupFileProtection.set(BackupFileProtection.working, on: pending.url)
                let package = try await Self.readPackage(at: pending.url, password: pending.password, extractingTo: staging, run: run)
                // Written away from the main thread: a large backup never pauses the screen. The
                // import has the repair list look again itself, and the prompt says so once
                // Settings closes.
                return try await service.importPackageAway(package, mode: mode, run: run)
            }
            resultText = BackupWording.result(result)
            doneCount += 1
        } catch {
            self.error = UserFacingError(error, doing: String(localized: "Copia nu s-a pus înapoi", comment: "Title of an import error."))
        }
    }

    // MARK: Pieces

    private func read(_ copy: URL, password: String?) async {
        do {
            let summary = try await keptGoing(String(localized: "Se verifică copia…", comment: "Subtitle of the system's progress while a backup is checked."), stopped: .checking) { run in
                try? BackupFileProtection.set(BackupFileProtection.working, on: copy)
                return try await Self.readSummary(at: copy, password: password, run: run)
            }
            pending = PendingImport(url: copy, password: password, summary: summary)
        } catch ArchiveError.needsPassword {
            lockedFile = LockedFile(url: copy)
        } catch ArchiveError.wrongPassword {
            lockedFile = LockedFile(url: copy, wasWrong: true)
        } catch {
            BackupFiles.remove(copy)
            self.error = UserFacingError(error, doing: String(localized: "Copia nu se deschide", comment: "Title of an import error."))
        }
    }

    /// Working copies of backups the person walked away from, and their files.
    private func removeLeftoverCopies() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: workDirectory.path(percentEncoded: false))) ?? []
        for name in names where name.hasPrefix("import-") && (name.hasSuffix(".dosar") || name.hasSuffix(".files")) {
            BackupFiles.remove(workDirectory.appending(path: name))
        }
        pending = nil
        lockedFile = nil
    }

    /// Where a working copy's documents' files go while it is brought in.
    private static func stagingFolder(for copy: URL) -> URL {
        copy.deletingPathExtension().appendingPathExtension("files")
    }

    /// Checks a backup and says what it holds, away from the main thread. Once checked, the copy
    /// waits for the person closed to a locked phone again.
    nonisolated static func readSummary(at url: URL, password: String?, run: BackupRun = BackupRun()) async throws -> ArchiveSummary {
        try await run.perform {
            let summary = Result { try DossierArchiveReader.summary(contentsOf: url, password: password, run: run) }
            // Read or not (a password to ask for), the copy waits closed to a locked phone.
            try? run.checkpoint(needsProtectedData: true)
            try BackupFileProtection.set(BackupFileProtection.finished, on: url)
            return try summary.get()
        }
    }

    /// Reads, checks and decodes a backup away from the main thread; its documents' files
    /// go to `staging`, one file each.
    nonisolated static func readPackage(at url: URL, password: String?, extractingTo staging: URL, run: BackupRun = BackupRun()) async throws -> DossierV3.Package {
        try await run.perform {
            try DossierArchiveReader.read(contentsOf: url, password: password, extractingTo: staging, run: run)
        }
    }

    /// Copies the file where only the app reads it, protected while the phone is
    /// locked. A file the system put in the app's Inbox ("Open in") is removed:
    /// it was only ever a copy for us.
    private func takeCopy(of url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let copy = workDirectory.appending(path: "import-\(UUID().uuidString).dosar")
        let fileManager = FileManager.default
        defer { if BackupFiles.isInside(url, inbox) { BackupFiles.remove(url) } }
        try fileManager.copyItem(at: url, to: copy)
        try? BackupFileProtection.set(BackupFileProtection.finished, on: copy)
        return copy
    }
}

/// A backup step the person stopped from the system's progress, or the system ended, in plain
/// words: what happened and that nothing was left half-done.
enum BackupStopped: LocalizedError, Equatable {
    case making
    case checking
    case bringingIn

    var errorDescription: String? {
        switch self {
        case .making:
            String(localized: "Copia s-a oprit înainte să fie gata și nu a rămas nimic pe jumătate. Fă-o din nou când vrei.", comment: "A backup being made was stopped before it finished.")
        case .checking:
            String(localized: "Verificarea copiei s-a oprit înainte să fie gata. Deschide copia din nou.", comment: "A backup being checked was stopped before it finished.")
        case .bringingIn:
            String(localized: "Copia s-a oprit înainte să intre în dosar. Dosarul e cum era; încearcă din nou când vrei.", comment: "A backup being brought in was stopped before it was saved; nothing changed.")
        }
    }
}
