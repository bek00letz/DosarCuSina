import CryptoKit
import Foundation
import Testing
@testable import DosarCuSina

/// Each app reads the other's bytes, with the archives in `shared/test-vectors/archive` (its
/// README says what each file is): the archives this app made still open with what they hold,
/// the Android app's open here the same way, and both apps refuse the same crafted archives with
/// the same kind of error. The Android tests (`android/archive`, `ArchiveVectorsTest`) do the
/// mirror, with the same entries made the same way.
///
/// `TEST_RUNNER_ARCHIVE_VECTORS_WRITE=1` writes this app's two archives again (once, when the
/// format changes on purpose); commit them, then run the Android tests.
@Suite("Archives both ways")
struct ArchiveVectorsTests {
    static var directory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/archive")
    }

    static var writes: Bool { ProcessInfo.processInfo.environment["ARCHIVE_VECTORS_WRITE"] == "1" }

    /// The placeholder password of the protected files, with a letter outside ASCII.
    static let password = "parol\u{0103}-exemplu"

    /// 2026-11-25T10:00:00Z: when every entry says it was written. Entry times are local to the
    /// writer's phone and never compared.
    static let written = Date(timeIntervalSince1970: 1_795_600_800)

    /// The entries every vector holds, in the order they are written: a folder among them.
    static func entries() -> [DosarZipEngine.Entry] {
        [
            .init(path: "text/repeated.txt", data: Data(String(repeating: "Dosar cu \u{0218}in\u{0103}, vector de test.\n", count: 200).utf8), modifiedDate: written),
            .init(path: "text/empty.txt", data: Data(), modifiedDate: written),
            .init(path: "acte/", data: Data(), modifiedDate: written),
            .init(
                path: "acte/\u{00EE}nsemnare-\u{0219}.txt",
                data: Data("\u{00CE}nsemnare de prob\u{0103}: \u{0219}, \u{021B}, \u{0103}, \u{00EE}, \u{00E2}.\n".utf8),
                modifiedDate: written
            ),
            .init(path: "vault/pagini.bin", data: pages(), modifiedDate: written),
        ]
    }

    /// 1 100 000 bytes: the SHA-256 of "pagina-0", of "pagina-1", and so on, one after another.
    static func pages() -> Data {
        let size = 1_100_000
        var data = Data(capacity: size + 32)
        var block = 0
        while data.count < size {
            data.append(contentsOf: SHA256.hash(data: Data("pagina-\(block)".utf8)))
            block += 1
        }
        return data.prefix(size)
    }

    /// What a reader lists of the entries: `<sha256>  <path>` lines, folders left out.
    static func listing() -> String {
        entries().filter { !$0.path.hasSuffix("/") }.map { "\(DossierArchiveReader.sha256($0.data))  \($0.path)\n" }.joined()
    }

    // MARK: Tests

    @Test("The listing is what the entries are")
    func theListingIsTheEntries() throws {
        let committed = try String(contentsOf: try Self.committed("contents.sha256"), encoding: .utf8)
        #expect(committed == Self.listing())
    }

    @Test("The archives this app made still open with everything in them")
    func ownArchivesStillOpen() throws {
        let plain = Self.directory.appending(path: "ios-plain.zip")
        let protected = Self.directory.appending(path: "ios-password.dosar")
        if Self.writes {
            try Self.write(to: plain, password: nil)
            try Self.write(to: protected, password: Self.password)
        }
        try Self.expectHoldsTheVector(try ArchiveFileSource(url: try Self.committed("ios-plain.zip")))
        try Self.expectProtectedVector(try Self.committed("ios-password.dosar"))
    }

    @Test("The Android app's archives open with everything in them")
    func androidArchivesOpen() throws {
        try Self.expectHoldsTheVector(try ArchiveFileSource(url: try Self.committed("android-plain.zip")))
        try Self.expectProtectedVector(try Self.committed("android-password.dosar"))
    }

    @Test("Both apps refuse the same archives with the same kind of error")
    func bothRefuseTheSameArchives() throws {
        let lines = try String(contentsOf: try Self.committed("refused.tsv"), encoding: .utf8)
            .split(separator: "\n").dropFirst().map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        #expect(lines.count >= 10)
        for line in lines {
            let (file, kind) = (line[0], line[1])
            let data = try Data(contentsOf: try Self.committed("refused/\(file)"))
            #expect(Self.refusal(of: data) == kind, "\(file): \(line[2])")
        }
    }

    // MARK: What every vector holds

    /// Writes the entries the app's way: a file, sealed chunk by chunk on its way there with a password.
    static func write(to url: URL, password: String?) throws {
        try? FileManager.default.removeItem(at: url)
        let file = try ArchiveFileSink(creating: url)
        let sealed = try password.map { try ArchiveEncryption.EncryptingSink(file, password: $0) }
        let sink: ArchiveByteSink = sealed.map { $0 as ArchiveByteSink } ?? file
        let zip = DosarZipEngine.Writer(sink: sink)
        for entry in entries() { try zip.add(path: entry.path, data: entry.data, modifiedDate: entry.modifiedDate) }
        try zip.finish()
        try sealed?.finish()
        try file.close()
    }

    static func expectHoldsTheVector(_ source: ArchiveByteSource) throws {
        let reader = try DosarZipEngine.Reader(source: source)
        let expected = listing().split(separator: "\n").map { $0.components(separatedBy: "  ") }
        #expect(reader.items.map(\.path) == expected.map { $0[1] }, "Every file, in order, the folder left out")
        for line in expected {
            let item = try #require(reader.item(at: line[1]))
            var hasher = SHA256()
            try reader.stream(item) { hasher.update(data: $0) }
            #expect(MachineText.hex(hasher.finalize()) == line[0], "\(line[1])")
        }
        #expect(reader.item(at: "text/repeated.txt")?.method == 8, "A compressed file")
        #expect(reader.item(at: "vault/pagini.bin")?.method == 0, "A stored file")
    }

    /// A protected vector opens with its password (written in either form), holds the vector, is
    /// written as the app writes one, and refuses every change the Android tests try.
    static func expectProtectedVector(_ url: URL) throws {
        let sealed = try Data(contentsOf: url)
        #expect(sealed.prefix(8) == ArchiveEncryption.magic)
        #expect(sealed.bigEndian(at: 10) == ArchiveEncryption.defaultIterations, "The rounds the app writes")
        #expect(Int(sealed.bigEndian(at: 30)) == ArchiveEncryption.defaultChunkSize, "The chunk size the app writes")
        #expect(sealed.count > ArchiveEncryption.headerSize + ArchiveEncryption.defaultChunkSize + ArchiveEncryption.tagSize, "More than one chunk")

        try expectHoldsTheVector(try ArchiveEncryption.DecryptingSource(ArchiveFileSource(url: url), password: password))
        // The same password typed with its letter in two characters.
        _ = try DosarZipEngine.Reader(source: try ArchiveEncryption.DecryptingSource(ArchiveFileSource(url: url), password: "parola\u{0306}-exemplu"))
        // The opening rule (`DossierArchiveReader.opened`) before anything else is read.
        #expect(throws: ArchiveError.needsPassword) { try DossierArchiveReader.summary(contentsOf: url) }
        #expect(throws: ArchiveError.noPasswordTyped) { try DossierArchiveReader.summary(contentsOf: url, password: "") }
        #expect(throws: ArchiveError.wrongPassword) { try DossierArchiveReader.summary(contentsOf: url, password: "alta-parola") }

        func failure(opening changed: Data) -> ArchiveEncryption.Failure? {
            do {
                let reader = try DosarZipEngine.Reader(source: try ArchiveEncryption.DecryptingSource(MemoryByteSource(changed), password: password))
                for item in reader.items { try reader.stream(item) { _ in } }
                return nil
            } catch let failure as ArchiveEncryption.Failure {
                return failure
            } catch {
                return nil
            }
        }
        var firstChunk = sealed
        firstChunk[ArchiveEncryption.headerSize + 10] ^= 0x01
        #expect(failure(opening: firstChunk) == .wrongPassword, "A byte of the first chunk changed")
        let cut = sealed.prefix(ArchiveEncryption.headerSize + ArchiveEncryption.defaultChunkSize + ArchiveEncryption.tagSize)
        #expect(failure(opening: Data(cut)) == .wrongPassword, "Cut after its first chunk")
        var noRounds = sealed
        noRounds.replaceSubrange(10..<14, with: [0, 0, 0, 0])
        #expect(failure(opening: noRounds) == .damaged, "A header that asks for no rounds")
        var newerVersion = sealed
        newerVersion[8] = 2
        #expect(failure(opening: newerVersion) == .damaged, "A version this app doesn't know")
    }

    /// The kind of error reading `data` whole, every file to its end, is refused with, as its
    /// case is named (`overlappingEntries`); nil when it is read.
    static func refusal(of data: Data) -> String? {
        do {
            let reader = try DosarZipEngine.Reader(source: MemoryByteSource(data))
            for item in reader.items { try reader.stream(item) { _ in } }
            return nil
        } catch let error as DosarZipEngine.ZipError {
            return String(String(describing: error).prefix { $0 != "(" })
        } catch {
            return "\(type(of: error))"
        }
    }

    static func committed(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try #require(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), "\(name) isn't in shared/test-vectors/archive. Its README says how each file is made.")
        return url
    }
}

private extension Data {
    func bigEndian(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) << 24 | UInt32(self[base + 1]) << 16 | UInt32(self[base + 2]) << 8 | UInt32(self[base + 3])
    }
}
