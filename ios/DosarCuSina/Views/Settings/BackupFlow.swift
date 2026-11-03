import Foundation
import SwiftData
import Observation

/// Everything the backup screen does, in one place the tests can drive:
///
/// - **Export** asks for Face ID or the passcode first whenever any lock is on,
///   then packs (and, with a password, encrypts) the binder away from the main thread.
/// - **Import** copies the chosen file somewhere only the app reads, removes a
///   file the system handed over through "Open in", and reads it away from the
///   main thread. Only a short summary is kept while the person decides; the
///   file is read again when they confirm, so a large backup isn't held in memory.
/// - **"Înlocuiește tot"** asks for Face ID or the passcode first whenever any lock is on.
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

    init(
        container: ModelContainer,
        vault: BiometricVaultManager,
        workDirectory: URL = .temporaryDirectory,
        inbox: URL = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
    ) {
        self.container = container
        self.vault = vault
        self.workDirectory = workDirectory
        self.inbox = inbox
    }

    /// Whether a section of the household is behind Face ID.
    private var anySectionLocked: Bool {
        let locked = FetchDescriptor<CategoryTemplate>(predicate: #Predicate { $0.isSensitive })
        return ((try? container.mainContext.fetchCount(locked)) ?? 0) > 0
    }

    // MARK: Export

    /// Makes a backup, with or without a password. Nothing is written unless
    /// Face ID or the passcode succeeded (when any lock is on).
    func export(password: String?) async {
        guard work == nil else { return }
        let reason = String(localized: "Fă o copie de siguranță a dosarului.", comment: "Face ID reason before exporting a backup.")
        guard await vault.confirmWholeBinder(anySectionLocked: anySectionLocked, reason: reason) == .success else { return }
        work = .exporting
        defer { work = nil }
        do {
            exportURL = try await DossierArchiveService(container: container).export(to: workDirectory, password: password)
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

    /// Brings a backup in. Replacing everything asks for Face ID or the passcode
    /// first whenever any lock is on; without it, the backup waits as it was.
    func runImport(_ pending: PendingImport, mode: ArchiveImportMode) async {
        guard work == nil else { return }
        self.pending = nil
        if mode == .replace {
            let reason = String(localized: "Înlocuiește tot dosarul cu copia.", comment: "Face ID reason before replacing everything with a backup.")
            guard await vault.confirmWholeBinder(anySectionLocked: anySectionLocked, reason: reason) == .success else {
                self.pending = pending
                return
            }
        }
        work = .importing
        defer {
            work = nil
            BackupFiles.remove(pending.url)
        }
        do {
            let package = try await Self.readPackage(at: pending.url, password: pending.password)
            // Written away from the main thread: a large backup never pauses the screen.
            let result = try await DossierArchiveService(container: container).importPackageAway(package, mode: mode)
            resultText = BackupWording.result(result)
            doneCount += 1
            // What the copy brought may need repairs (deadlines from a first-version copy):
            // the repair list looks again, and the prompt says so once Settings closes.
            try? DataRepairCenter.shared.refresh(in: container.mainContext, announce: true)
        } catch {
            self.error = UserFacingError(error, doing: String(localized: "Copia nu s-a pus înapoi", comment: "Title of an import error."))
        }
    }

    // MARK: Pieces

    private func read(_ copy: URL, password: String?) async {
        do {
            let summary = ArchiveSummary(try await Self.readPackage(at: copy, password: password))
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

    /// Working copies of backups the person walked away from.
    private func removeLeftoverCopies() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: workDirectory.path(percentEncoded: false))) ?? []
        for name in names where name.hasPrefix("import-") && name.hasSuffix(".dosar") {
            BackupFiles.remove(workDirectory.appending(path: name))
        }
        pending = nil
        lockedFile = nil
    }

    /// Reads, checks and decodes a backup away from the main thread.
    nonisolated static func readPackage(at url: URL, password: String?) async throws -> DossierV3.Package {
        try await Task.detached(priority: .userInitiated) {
            try DossierArchiveReader.read(contentsOf: url, password: password)
        }.value
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
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: copy.path(percentEncoded: false))
        return copy
    }
}
