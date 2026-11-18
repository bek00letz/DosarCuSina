import Foundation
import SwiftData
import CryptoKit
import UniformTypeIdentifiers

public enum ArchiveError: LocalizedError, Equatable {
    case notADossier
    case unsupportedVersion(Int)
    case missingFile(String)
    case checksumMismatch(String)
    case unlistedFile(String)
    case unreadableFile(String)
    case brokenReference(String)
    /// The archive is protected with a password and none was given.
    case needsPassword
    /// The password given doesn't open the archive.
    case wrongPassword
    /// A protected archive was given an empty password: nothing was typed.
    case noPasswordTyped
    /// A document, by its title, is bigger than one file of a backup may be.
    case documentTooLarge(String)
    /// A section's photo, by the section's name, is bigger than one file of a backup may be.
    case photoTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .notADossier:
            return String(localized: "Fișierul nu e o copie de siguranță Dosar cu Șină. Alege fișierul .dosar făcut din Setări.", comment: "Backup: the chosen file isn't a backup.")
        case .unsupportedVersion:
            return String(localized: "Copia de siguranță a fost făcută de o versiune mai nouă a aplicației. Actualizează aplicația și încearcă din nou.", comment: "Backup: made by a newer version.")
        // What went wrong, in plain words: never the archive's own path, which says nothing to
        // the person (the path stays on the error, for tests and the log).
        case .missingFile:
            return String(localized: "Copia de siguranță e incompletă: îi lipsește o parte. Fă copia din nou și încearcă iar.", comment: "Backup: a file is missing from it.")
        case .checksumMismatch, .unreadableFile:
            return String(localized: "O parte din copia de siguranță e deteriorată. Fă copia din nou și încearcă iar.", comment: "Backup: one file inside it is damaged.")
        case .unlistedFile:
            return String(localized: "Copia de siguranță conține un fișier pe care aplicația nu l-a pus acolo. Fă copia din nou din aplicație.", comment: "Backup: a file it doesn't list.")
        case .brokenReference:
            return String(localized: "Datele din copia de siguranță nu se potrivesc între ele. Fă copia din nou și încearcă iar.", comment: "Backup: its records point at records it doesn't have.")
        case .needsPassword:
            return String(localized: "Copia e protejată cu o parolă. Scrie parola cu care a fost făcută.")
        case .wrongPassword:
            return String(localized: "Parola nu deschide copia. Verifică literele mari și mici și încearcă din nou.")
        case .noPasswordTyped:
            return String(localized: "Nu ai scris nicio parolă. Scrie parola cu care a fost făcută copia.", comment: "Backup: a protected backup was opened with nothing typed for its password.")
        case .documentTooLarge(let title):
            return String(localized: "„\(title)” e prea mare pentru o copie de siguranță. Scoate-l din dosar și păstrează-l în altă parte, apoi fă copia din nou.", comment: "Backup: one document is larger than a backup's file may be. The argument is the document's title.")
        case .photoTooLarge(let name):
            return String(localized: "Poza secțiunii „\(name)” e prea mare pentru o copie de siguranță. Pune o poză mai mică, apoi fă copia din nou.", comment: "Backup: a section's photo is larger than a backup's file may be. The argument is the section's name.")
        }
    }
}

public enum ArchiveImportMode: String, Sendable {
    /// Keeps what is here; for records in both, the more recently edited one wins.
    case merge
    /// Replaces everything here with the archive.
    case replace
}

public struct ArchiveSummary: Hashable, Sendable {
    public var schemaVersion: Int
    public var platform: String
    public var exportedAt: Date
    public var counts: DossierV3.Manifest.Counts
}

extension ArchiveSummary {
    public init(_ package: DossierV3.Package) {
        self.init(package.manifest)
    }

    /// What a manifest says the archive holds.
    public init(_ manifest: DossierV3.Manifest) {
        schemaVersion = manifest.schemaVersion
        platform = manifest.platform
        exportedAt = manifest.exportedAt
        counts = manifest.counts
    }
}

public struct ArchiveImportResult: Hashable, Sendable {
    public var inserted = 0
    public var updated = 0
    public var skipped = 0
    /// Sections whose place in the archive couldn't be used (filed under
    /// themselves, or under something missing): they are at the top of the binder.
    public var movedToTop = 0
}

// MARK: - Reading

/// Reads, checks and decodes an archive file, a piece at a time: the directory, then each
/// file once, its checksum worked out as it is read. Thread-safe; nothing touches the
/// database. Memory doesn't grow with the archive: every file is checked as it streams by,
/// within the one set of limits both ways (`DosarZipEngine.Limits.standard`). Checking a
/// backup (`summary`) keeps none of them, only the manifest; bringing one in (`read`) writes
/// each to a folder of its own, then decodes the files that describe the household
/// (`data/*.json`) one at a time, so only one is ever held whole.
public enum DossierArchiveReader {
    /// What becomes of the archive's files as they are checked.
    enum Keeping {
        /// Checked against their checksums, then let go: enough to say what the archive holds.
        case checkOnly
        /// Written, one file each, to this folder (made if needed), for the importer to read.
        case extract(into: URL)
    }

    /// What an archive holds, once every file in it is checked. None of its files is kept.
    static func summary(contentsOf url: URL, password: String? = nil, limits: DosarZipEngine.Limits = .standard, run: BackupRun = BackupRun()) throws -> ArchiveSummary {
        try summary(try ArchiveFileSource(url: url), password: password, limits: limits, run: run)
    }

    /// The archive, checked and decoded, its documents' files written to `directory` for the
    /// importer to read one at a time. The caller removes `directory` once the package is written.
    static func read(contentsOf url: URL, password: String? = nil, extractingTo directory: URL, limits: DosarZipEngine.Limits = .standard, run: BackupRun = BackupRun()) throws -> DossierV3.Package {
        try read(try ArchiveFileSource(url: url), password: password, limits: limits, extractingTo: directory, run: run)
    }

    static func summary(_ source: ArchiveByteSource, password: String?, limits: DosarZipEngine.Limits, run: BackupRun = BackupRun()) throws -> ArchiveSummary {
        try opened(source, password: password) { plain in
            switch try readPlain(plain, limits: limits, keeping: .checkOnly, run: run) {
            case .summary(let summary): return summary
            case .package(let package): return ArchiveSummary(package)
            }
        }
    }

    static func read(_ source: ArchiveByteSource, password: String?, limits: DosarZipEngine.Limits, extractingTo directory: URL, run: BackupRun = BackupRun()) throws -> DossierV3.Package {
        try opened(source, password: password) { plain in
            switch try readPlain(plain, limits: limits, keeping: .extract(into: directory), run: run) {
            case .package(let package): return package
            case .summary: throw ArchiveError.notADossier
            }
        }
    }

    /// The archive's own bytes, opened with its password when it has one, handed to `body`.
    private static func opened<T>(_ source: ArchiveByteSource, password: String?, _ body: (ArchiveByteSource) throws -> T) throws -> T {
        var plain = source
        if ArchiveEncryption.isEncrypted(source) {
            guard let password else { throw ArchiveError.needsPassword }
            // No archive is protected with an empty password (`ArchiveEncryption.minimumPasswordLength`):
            // nothing was typed, which says nothing about the file.
            guard !password.isEmpty else { throw ArchiveError.noPasswordTyped }
            plain = try inArchiveWords { try ArchiveEncryption.DecryptingSource(source, password: password) }
        }
        return try inArchiveWords { try body(plain) }
    }

    /// A protected archive's failures, anywhere in it, as the archive's own.
    private static func inArchiveWords<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch ArchiveEncryption.Failure.wrongPassword {
            throw ArchiveError.wrongPassword
        } catch ArchiveEncryption.Failure.damaged {
            throw ArchiveError.notADossier
        }
    }

    /// What reading an archive gave: what it holds (checking only), or all of it.
    private enum Reading {
        case summary(ArchiveSummary)
        case package(DossierV3.Package)
    }

    private static func readPlain(_ source: ArchiveByteSource, limits: DosarZipEngine.Limits, keeping: Keeping, run: BackupRun) throws -> Reading {
        let zip = try DosarZipEngine.Reader(source: source, limits: limits)
        guard let manifestItem = zip.item(at: DossierV3.Path.manifest) else { throw ArchiveError.notADossier }
        let manifestData = try zip.data(of: manifestItem)
        struct VersionProbe: Decodable { let schemaVersion: Int; let format: String? }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: manifestData) else { throw ArchiveError.notADossier }
        if let format = probe.format, format != DossierV3.format { throw ArchiveError.notADossier }

        switch probe.schemaVersion {
        case 2:
            // The first format's files are converted together, so they are held while it is read.
            var checked = try check(
                zip, checksums: try DossierV2Converter.checksums(fromManifest: manifestData),
                dataFiles: DossierV2Converter.dataFiles, refusingUnlisted: false, keeping: keeping, holdingData: true, run: run
            )
            checked.data[DossierV3.Path.manifest] = manifestData
            return .package(try DossierV2Converter.package(from: checked.data, vault: checked.vault))
        case 3:
            break
        default:
            throw ArchiveError.unsupportedVersion(probe.schemaVersion)
        }

        let decoder = DossierV3.decoder()
        guard let manifest = try? decoder.decode(DossierV3.Manifest.self, from: manifestData) else {
            throw ArchiveError.unreadableFile(DossierV3.Path.manifest)
        }
        let checked = try check(zip, checksums: manifest.checksums, dataFiles: Set(DossierV3.Path.dataFiles), refusingUnlisted: true,
                                keeping: keeping, holdingData: false, run: run)
        guard case .extract = keeping else { return .summary(ArchiveSummary(manifest)) }

        /// Each file read from where it was written, decoded, and let go before the next.
        func decode<T: Decodable>(_ type: [T].Type, _ path: String) throws -> [T] {
            guard let url = checked.dataFiles[path] else { return [] }
            defer { try? FileManager.default.removeItem(at: url) }
            do { return try decoder.decode(type, from: try Data(contentsOf: url)) } catch { throw ArchiveError.unreadableFile(path) }
        }
        let package = DossierV3.Package(
            manifest: manifest,
            templates: try decode([DossierV3.Template].self, DossierV3.Path.templates),
            assets: try decode([DossierV3.Asset].self, DossierV3.Path.assets),
            obligations: try decode([DossierV3.Obligation].self, DossierV3.Path.obligations),
            historyEntries: try decode([DossierV3.HistoryEntry].self, DossierV3.Path.history),
            serviceItems: try decode([DossierV3.ServiceItem].self, DossierV3.Path.serviceItems),
            providers: try decode([DossierV3.Provider].self, DossierV3.Path.providers),
            measurements: try decode([DossierV3.Measurement].self, DossierV3.Path.measurements),
            attachments: try decode([DossierV3.Attachment].self, DossierV3.Path.attachments),
            issuerLessons: try decode([DossierV3.IssuerLesson].self, DossierV3.Path.issuerLessons),
            files: checked.vault
        )
        try validateReferences(package)
        return .package(package)
    }

    /// What checking an archive's files kept: the data files held (`holdingData`) or written
    /// out (where they are), and the documents' files.
    struct Checked {
        var data: [String: Data] = [:]
        var dataFiles: [String: URL] = [:]
        var vault: DossierV3.ArchiveFiles
    }

    /// Every listed file must exist and match its SHA-256; with `refusingUnlisted`, every
    /// other file (but the manifest) must be listed. Each file is read once, a piece at a time:
    /// kept as `keeping` says (only checked, or written to a file of its own in the folder,
    /// named by its place, never by the archive's own path), a data file held whole only with
    /// `holdingData`.
    static func check(
        _ zip: DosarZipEngine.Reader,
        checksums: [String: String],
        dataFiles: Set<String>,
        refusingUnlisted: Bool,
        keeping: Keeping,
        holdingData: Bool,
        run: BackupRun = BackupRun()
    ) throws -> Checked {
        for path in checksums.keys.sorted() where zip.item(at: path) == nil {
            throw ArchiveError.missingFile(path)
        }
        if refusingUnlisted {
            for item in zip.items where item.path != DossierV3.Path.manifest && checksums[item.path] == nil {
                throw ArchiveError.unlistedFile(item.path)
            }
        }
        var folder: URL?
        if case .extract(let directory) = keeping {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            folder = directory
        }
        var data: [String: Data] = [:]
        var written: [String: URL] = [:]
        var vault: [String: DossierV3.ArchiveFiles.Content] = [:]
        let items = zip.items.filter { $0.path != DossierV3.Path.manifest }
        run.expect(items.count)
        for item in items {
            // Only the backup's own files are read here: it goes on while the phone is locked.
            try run.checkpoint(needsProtectedData: false)
            defer { run.did() }
            var hasher = SHA256()
            let isData = dataFiles.contains(item.path)
            if isData, holdingData {
                let bytes = try zip.data(of: item)
                hasher.update(data: bytes)
                data[item.path] = bytes
            } else if let folder, isData || item.path.hasPrefix(DossierV3.Path.vaultPrefix) {
                // Named by its place, never by the archive's own path.
                let url = folder.appending(path: isData ? "data-\(written.count)" : "\(vault.count)")
                // On its way into the binder: open to a locked phone while the import holds it.
                let file = try ArchiveFileSink(creating: url, protection: BackupFileProtection.working)
                try zip.stream(item) { piece in
                    hasher.update(data: piece)
                    try file.write(piece)
                }
                try file.close()
                if isData { written[item.path] = url } else { vault[item.path] = .file(url) }
            } else {
                try zip.stream(item) { hasher.update(data: $0) }
                if item.path.hasPrefix(DossierV3.Path.vaultPrefix) { vault[item.path] = .checked }
            }
            if let expected = checksums[item.path], MachineText.hex(hasher.finalize()) != expected.lowercased() {
                throw ArchiveError.checksumMismatch(item.path)
            }
        }
        return Checked(data: data, dataFiles: written, vault: DossierV3.ArchiveFiles(vault))
    }

    static func validateReferences(_ package: DossierV3.Package) throws {
        for attachment in package.attachments {
            for path in attachment.allPaths where !package.files.contains(path) {
                throw ArchiveError.missingFile(path)
            }
        }
        for asset in package.assets {
            if let photo = asset.photoPath, !package.files.contains(photo) { throw ArchiveError.missingFile(photo) }
        }
    }

    public static func sha256(_ data: Data) -> String {
        Hashing.sha256(data)
    }
}

// MARK: - Service

/// Exports the household to a `.dosar` archive and imports one back. Import
/// builds everything in a separate context and saves once, so a failure part
/// way through leaves the existing data exactly as it was.
///
/// Both ways go through files, a piece at a time, never through the whole archive in
/// memory, and read the same limits (`DosarZipEngine.Limits.standard`): a backup this
/// app makes is one it can put back.
@MainActor
public struct DossierArchiveService {
    public let container: ModelContainer
    private let calendar: Calendar
    /// The repair list every import looks at again (`DataRepairs`).
    var repairs: DataRepairCenter = .shared

    public init(container: ModelContainer, calendar: Calendar = .dosar) {
        self.container = container
        self.calendar = calendar
    }

    // MARK: Export

    /// Writes an archive to a file ready to share, protected while the device is locked.
    /// With a password, the whole archive is encrypted with it. Everything runs away from
    /// the main thread.
    /// `run` keeps its progress and can stop it (`BackupRun`).
    func export(to directory: URL = .temporaryDirectory, password: String? = nil, exportedAt: Date = Date(), run: BackupRun = BackupRun()) async throws -> URL {
        let url = exportURL(in: directory, exportedAt: exportedAt)
        let writer = self.writer(exportedAt: exportedAt)
        try await run.perform {
            try writer.write(to: url, password: password, run: run)
        }
        return url
    }

    /// The same, on the calling thread.
    func exportFile(to directory: URL = .temporaryDirectory, password: String? = nil, appVersion: String = Bundle.main.shortVersion, exportedAt: Date = Date()) throws -> URL {
        let url = exportURL(in: directory, exportedAt: exportedAt)
        try writer(appVersion: appVersion, exportedAt: exportedAt).write(to: url, password: password)
        return url
    }

    private func writer(appVersion: String = Bundle.main.shortVersion, exportedAt: Date) -> DossierArchiveWriter {
        DossierArchiveWriter(container: container, calendar: calendar, appVersion: appVersion, exportedAt: exportedAt)
    }

    private func exportURL(in directory: URL, exportedAt: Date) -> URL {
        directory.appending(path: "Dosar cu Șină \(CalendarDay(exportedAt, calendar: calendar).isoString).dosar")
    }

    // MARK: Import

    /// Reads an archive file and writes it into the database, as one unit of work. Its
    /// documents' files pass through a folder of their own in `staging`, removed when done.
    @discardableResult
    public func importArchive(at url: URL, password: String? = nil, mode: ArchiveImportMode, staging: URL = .temporaryDirectory) throws -> ArchiveImportResult {
        let folder = staging.appending(path: "import-\(UUID().uuidString).files", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try importPackage(try DossierArchiveReader.read(contentsOf: url, password: password, extractingTo: folder), mode: mode)
    }

    /// Writes an already read package into the database, as one unit of work:
    /// everything or nothing. Then the repair list looks again (`lookForRepairs`).
    @discardableResult
    public func importPackage(_ package: DossierV3.Package, mode: ArchiveImportMode) throws -> ArchiveImportResult {
        let result = try Self.write(package, mode: mode, container: container, calendar: calendar, keepsExamples: !PersistenceController.syncs(container))
        lookForRepairs()
        return result
    }

    /// The same, away from the main thread, so a large backup never pauses the
    /// screen while it is written. The app's screens see the records once it saves.
    ///
    /// Its documents' files are written into the binder, which can't be done while the phone is
    /// locked: the unit opens once it is unlocked, and runs again when the phone locked while it
    /// ran, since the unit took everything back (`BackupRun.writing`). `run` can stop it until the
    /// unit opens; the unit itself runs to its end, everything or nothing.
    @discardableResult
    func importPackageAway(_ package: DossierV3.Package, mode: ArchiveImportMode, run: BackupRun = BackupRun()) async throws -> ArchiveImportResult {
        let container = container
        let calendar = calendar
        let keepsExamples = !PersistenceController.syncs(container)
        run.expect(1)
        let result = try await run.perform {
            try run.writing { try Self.write(package, mode: mode, container: container, calendar: calendar, keepsExamples: keepsExamples) }
        }
        run.did()
        lookForRepairs()
        return result
    }

    /// What a backup brought may need repairs (deadlines from a first-version copy, a firm
    /// kept twice): after every import, whichever way it came in, the repair list looks again,
    /// and the calm prompt says so. The backup is in by then, so a repair list that can't look
    /// doesn't undo it: the failure is logged, and the list looks again at the next launch.
    private func lookForRepairs() {
        PersistenceLog.attempt("Refreshing the repair list after an import") {
            try repairs.refresh(in: container.mainContext, announce: true)
        }
    }

    /// The one way a package is written: on a context of its own, saved once,
    /// everything or nothing.
    nonisolated static func write(_ package: DossierV3.Package, mode: ArchiveImportMode, container: ModelContainer, calendar: Calendar, keepsExamples: Bool = true) throws -> ArchiveImportResult {
        let context = PersistenceController.context(in: container)
        return try UnitOfWork.performPrivate(in: context) {
            try DossierImporter(context: context, package: package, mode: mode, calendar: calendar, keepsExamples: keepsExamples).run()
        }
    }
}

extension Bundle {
    public var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
