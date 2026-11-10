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
    /// A document, by its title, is bigger than one file of a backup may be.
    case documentTooLarge(String)
    /// A section's photo, by the section's name, is bigger than one file of a backup may be.
    case photoTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .notADossier:
            return String(localized: "Fișierul nu e o arhivă Dosar cu Șină.")
        case .unsupportedVersion:
            return String(localized: "Arhiva a fost făcută de o versiune mai nouă a aplicației. Actualizează aplicația și încearcă din nou.")
        case .missingFile(let path):
            return String(localized: "Arhiva e incompletă: lipsește \(path).")
        case .checksumMismatch(let path), .unreadableFile(let path):
            return String(localized: "Fișierul \(path) din arhivă e deteriorat.")
        case .unlistedFile(let path):
            return String(localized: "Arhiva conține un fișier neașteptat: \(path).")
        case .brokenReference(let path):
            return String(localized: "Datele din \(path) nu se potrivesc între ele.")
        case .needsPassword:
            return String(localized: "Copia e protejată cu o parolă. Scrie parola cu care a fost făcută.")
        case .wrongPassword:
            return String(localized: "Parola nu deschide copia. Verifică literele mari și mici și încearcă din nou.")
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
        schemaVersion = package.manifest.schemaVersion
        platform = package.manifest.platform
        exportedAt = package.manifest.exportedAt
        counts = package.manifest.counts
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
/// database. Memory doesn't grow with the archive: only the files that describe the
/// household (the manifest and `data/*.json`) are held, and the documents' files are
/// either only checked (`summary`) or written to a folder of their own (`read`).
public enum DossierArchiveReader {
    /// What becomes of the documents' files as they are checked.
    enum Keeping {
        /// Checked against their checksums, then let go: enough to say what the archive holds.
        case checkOnly
        /// Written, one file each, to this folder (made if needed), for the importer to read.
        case extract(into: URL)
    }

    /// What an archive holds, once every file in it is checked. Its documents' files aren't kept.
    public static func summary(contentsOf url: URL, password: String? = nil, limits: DosarZipEngine.Limits = .standard) throws -> ArchiveSummary {
        ArchiveSummary(try read(try ArchiveFileSource(url: url), password: password, limits: limits, keeping: .checkOnly))
    }

    /// The archive, checked and decoded, its documents' files written to `directory` for the
    /// importer to read one at a time. The caller removes `directory` once the package is written.
    public static func read(contentsOf url: URL, password: String? = nil, extractingTo directory: URL, limits: DosarZipEngine.Limits = .standard) throws -> DossierV3.Package {
        try read(try ArchiveFileSource(url: url), password: password, limits: limits, keeping: .extract(into: directory))
    }

    static func read(_ source: ArchiveByteSource, password: String?, limits: DosarZipEngine.Limits, keeping: Keeping) throws -> DossierV3.Package {
        var plain = source
        if ArchiveEncryption.isEncrypted(source) {
            guard let password else { throw ArchiveError.needsPassword }
            plain = try inArchiveWords { try ArchiveEncryption.DecryptingSource(source, password: password) }
        }
        return try inArchiveWords { try readPlain(plain, limits: limits, keeping: keeping) }
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

    private static func readPlain(_ source: ArchiveByteSource, limits: DosarZipEngine.Limits, keeping: Keeping) throws -> DossierV3.Package {
        let zip = try DosarZipEngine.Reader(source: source, limits: limits)
        guard let manifestItem = zip.item(at: DossierV3.Path.manifest) else { throw ArchiveError.notADossier }
        let manifestData = try zip.data(of: manifestItem)
        struct VersionProbe: Decodable { let schemaVersion: Int; let format: String? }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: manifestData) else { throw ArchiveError.notADossier }
        if let format = probe.format, format != DossierV3.format { throw ArchiveError.notADossier }

        switch probe.schemaVersion {
        case 2:
            var checked = try check(
                zip, checksums: try DossierV2Converter.checksums(fromManifest: manifestData),
                dataFiles: DossierV2Converter.dataFiles, refusingUnlisted: false, keeping: keeping
            )
            checked.data[DossierV3.Path.manifest] = manifestData
            return try DossierV2Converter.package(from: checked.data, vault: checked.vault)
        case 3:
            break
        default:
            throw ArchiveError.unsupportedVersion(probe.schemaVersion)
        }

        let decoder = DossierV3.decoder()
        guard let manifest = try? decoder.decode(DossierV3.Manifest.self, from: manifestData) else {
            throw ArchiveError.unreadableFile(DossierV3.Path.manifest)
        }
        let checked = try check(zip, checksums: manifest.checksums, dataFiles: Set(DossierV3.Path.dataFiles), refusingUnlisted: true, keeping: keeping)

        func decode<T: Decodable>(_ type: [T].Type, _ path: String) throws -> [T] {
            guard let data = checked.data[path] else { return [] }
            do { return try decoder.decode(type, from: data) } catch { throw ArchiveError.unreadableFile(path) }
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
            files: checked.vault
        )
        try validateReferences(package)
        return package
    }

    /// Every listed file must exist and match its SHA-256; with `refusingUnlisted`, every
    /// other file (but the manifest) must be listed. Each file is read once: the data files
    /// whole (they are returned), the others a piece at a time, the documents' kept as
    /// `keeping` says.
    static func check(
        _ zip: DosarZipEngine.Reader,
        checksums: [String: String],
        dataFiles: Set<String>,
        refusingUnlisted: Bool,
        keeping: Keeping
    ) throws -> (data: [String: Data], vault: DossierV3.ArchiveFiles) {
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
        var vault: [String: DossierV3.ArchiveFiles.Content] = [:]
        for item in zip.items where item.path != DossierV3.Path.manifest {
            var hasher = SHA256()
            if dataFiles.contains(item.path) {
                let bytes = try zip.data(of: item)
                hasher.update(data: bytes)
                data[item.path] = bytes
            } else if item.path.hasPrefix(DossierV3.Path.vaultPrefix), let folder {
                // Named by its place, never by the archive's own path.
                let url = folder.appending(path: "\(vault.count)")
                let file = try ArchiveFileSink(creating: url)
                try zip.stream(item) { piece in
                    hasher.update(data: piece)
                    try file.write(piece)
                }
                try file.close()
                vault[item.path] = .file(url)
            } else {
                try zip.stream(item) { hasher.update(data: $0) }
                if item.path.hasPrefix(DossierV3.Path.vaultPrefix) { vault[item.path] = .checked }
            }
            if let expected = checksums[item.path], MachineText.hex(hasher.finalize()) != expected.lowercased() {
                throw ArchiveError.checksumMismatch(item.path)
            }
        }
        return (data, DossierV3.ArchiveFiles(vault))
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

    public init(container: ModelContainer, calendar: Calendar = .dosar) {
        self.container = container
        self.calendar = calendar
    }

    // MARK: Export

    /// Writes an archive to a file ready to share, protected while the device is locked.
    /// With a password, the whole archive is encrypted with it. Everything runs away from
    /// the main thread.
    public func export(to directory: URL = .temporaryDirectory, password: String? = nil, exportedAt: Date = Date()) async throws -> URL {
        let url = exportURL(in: directory, exportedAt: exportedAt)
        let writer = self.writer(exportedAt: exportedAt)
        try await Task.detached(priority: .userInitiated) {
            try writer.write(to: url, password: password)
        }.value
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
    /// everything or nothing.
    @discardableResult
    public func importPackage(_ package: DossierV3.Package, mode: ArchiveImportMode) throws -> ArchiveImportResult {
        try Self.write(package, mode: mode, container: container, calendar: calendar)
    }

    /// The same, away from the main thread, so a large backup never pauses the
    /// screen while it is written. The app's screens see the records once it saves.
    @discardableResult
    public func importPackageAway(_ package: DossierV3.Package, mode: ArchiveImportMode) async throws -> ArchiveImportResult {
        let container = container
        let calendar = calendar
        return try await Task.detached(priority: .userInitiated) {
            try Self.write(package, mode: mode, container: container, calendar: calendar)
        }.value
    }

    /// The one way a package is written: on a context of its own, saved once,
    /// everything or nothing.
    nonisolated private static func write(_ package: DossierV3.Package, mode: ArchiveImportMode, container: ModelContainer, calendar: Calendar) throws -> ArchiveImportResult {
        let context = PersistenceController.context(in: container)
        return try UnitOfWork.performPrivate(in: context) {
            try DossierImporter(context: context, package: package, mode: mode, calendar: calendar).run()
        }
    }
}

extension Bundle {
    public var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
