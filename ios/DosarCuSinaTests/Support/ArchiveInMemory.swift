import Foundation
@testable import DosarCuSina

// Small archives built and taken apart in memory, for tests only. The app reads and writes
// archives only through files, a piece at a time; these go through the same writer, reader,
// sealer and importer, with the bytes kept in memory or in a temporary file.

/// Bytes kept in memory, read at any place; a slice of a bigger buffer reads the same.
final class MemoryByteSource: ArchiveByteSource {
    let data: Data
    init(_ data: Data) { self.data = data }
    var size: Int { data.count }

    func read(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, count <= size - offset else { throw DosarZipEngine.ZipError.invalidZipArchive }
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + count))
    }
}

/// Bytes written, kept in memory.
final class MemoryByteSink: ArchiveByteSink {
    private(set) var data = Data()
    /// The largest piece written at once.
    private(set) var largestWrite = 0

    func write(_ piece: Data) throws {
        largestWrite = max(largestWrite, piece.count)
        data.append(piece)
    }
}

extension DosarZipEngine {
    /// One file of a hand-made archive.
    struct Entry: Sendable {
        let path: String
        let data: Data
        let modifiedDate: Date

        init(path: String, data: Data, modifiedDate: Date = Date()) {
            self.path = path
            self.data = data
            self.modifiedDate = modifiedDate
        }
    }

    static func createArchive(entries: [Entry], limits: Limits = .standard) throws -> Data {
        let sink = MemoryByteSink()
        let writer = Writer(sink: sink, limits: limits)
        for entry in entries { try writer.add(path: entry.path, data: entry.data, modifiedDate: entry.modifiedDate) }
        try writer.finish()
        return sink.data
    }

    static func unpackArchive(_ data: Data, limits: Limits = .standard) throws -> [Entry] {
        let reader = try Reader(source: MemoryByteSource(data), limits: limits)
        return try reader.items.map { Entry(path: $0.path, data: try reader.data(of: $0), modifiedDate: $0.modifiedDate) }
    }
}

extension ArchiveEncryption {
    static func isEncrypted(_ data: Data) -> Bool {
        isEncrypted(MemoryByteSource(data))
    }

    static func encrypt(_ plain: Data, password: String, iterations: UInt32 = defaultIterations, chunkSize: Int = defaultChunkSize) throws -> Data {
        let sink = MemoryByteSink()
        let sealed = try EncryptingSink(sink, password: password, iterations: iterations, chunkSize: chunkSize)
        try sealed.write(plain)
        try sealed.finish()
        return sink.data
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        let source = try DecryptingSource(MemoryByteSource(data), password: password)
        return try source.read(at: 0, count: source.size)
    }
}

extension DossierArchiveReader {
    static func isPasswordProtected(_ data: Data) -> Bool {
        ArchiveEncryption.isEncrypted(MemoryByteSource(data))
    }

    /// The archive read the app's way, its documents' files taken out to a temporary folder
    /// and then held in memory, so a test can look at them.
    static func read(_ data: Data, password: String? = nil, limits: DosarZipEngine.Limits = .standard) throws -> DossierV3.Package {
        let folder = URL.temporaryDirectory.appending(path: "archive-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        var package = try read(MemoryByteSource(data), password: password, limits: limits, keeping: .extract(into: folder))
        var files: [String: DossierV3.ArchiveFiles.Content] = [:]
        for path in package.files.paths {
            if let bytes = try package.files.data(at: path) { files[path] = .data(Data(bytes)) }
        }
        package.files = DossierV3.ArchiveFiles(files)
        return package
    }
}

@MainActor
extension DossierArchiveService {
    /// The plain archive, written to a temporary file the app's way and read back.
    func exportData(appVersion: String = Bundle.main.shortVersion, exportedAt: Date = Date()) throws -> Data {
        let folder = URL.temporaryDirectory.appending(path: "export-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try Data(contentsOf: try exportFile(to: folder, appVersion: appVersion, exportedAt: exportedAt))
    }

    func inspect(_ data: Data, password: String? = nil) throws -> ArchiveSummary {
        try ArchiveFile.holding(data) { try DossierArchiveReader.summary(contentsOf: $0, password: password) }
    }

    @discardableResult
    func importArchive(_ data: Data, password: String? = nil, mode: ArchiveImportMode) throws -> ArchiveImportResult {
        try ArchiveFile.holding(data) { try importArchive(at: $0, password: password, mode: mode) }
    }
}

/// A temporary file holding an archive's bytes, for as long as `body` runs.
enum ArchiveFile {
    static func holding<T>(_ data: Data, _ body: (URL) throws -> T) throws -> T {
        let url = URL.temporaryDirectory.appending(path: "archive-test-\(UUID().uuidString).dosar")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }
}
