import CommonCrypto
import CryptoKit
import Foundation

/// A password-protected `.dosar`: the plain archive, encrypted with a key made
/// from the person's password. Nothing of the household can be read without it,
/// and the password itself is never stored anywhere.
///
/// The layout, as `shared/schemas/dosar-v3.md` describes it (integers big-endian):
///
///     header  "DOSARENC" (8 bytes) · version 1 (1 byte) · key derivation 1 = PBKDF2-HMAC-SHA256 (1 byte)
///             · iterations (4 bytes) · salt (16 bytes) · chunk size (4 bytes) · nonce prefix (8 bytes)
///     body    the plain archive in chunks of `chunk size` bytes (the last one may be shorter), each
///             encrypted with AES-256-GCM and followed by its 16-byte tag
///
/// Chunk `i` uses the nonce `prefix ‖ i` (4 bytes) and authenticates the whole
/// header plus one byte, 1 for the last chunk and 0 for the others, so chunks
/// can't be reordered, dropped or cut off without the archive refusing to open.
///
/// Both sides stream: `EncryptingSink` seals a chunk as soon as the next byte shows it
/// isn't the last, and `DecryptingSource` opens only the chunks a read needs, so neither
/// holds more than a chunk or two, whatever the archive's size.
public enum ArchiveEncryption {
    public static let magic = Data("DOSARENC".utf8)
    static let version: UInt8 = 1
    static let pbkdf2SHA256: UInt8 = 1
    /// Slow enough to make guessing expensive, quick enough on a phone (well under a second).
    public static let defaultIterations: UInt32 = 600_000
    /// The rounds a protected archive may ask for, written and read alike. Every protected
    /// archive this app has made used `defaultIterations`; the range leaves room for one step
    /// up, and keeps every try of a password about as quick as the app's own.
    public static let acceptedIterations: ClosedRange<UInt32> = 1...1_000_000
    public static let defaultChunkSize = 1 << 20
    /// The chunk sizes written and read: a reader never holds more than two chunks.
    public static let acceptedChunkSizes: ClosedRange<Int> = 1...(16 << 20)
    static let saltSize = 16
    static let noncePrefixSize = 8
    static let tagSize = 16
    static let headerSize = magic.count + 1 + 1 + 4 + saltSize + 4 + noncePrefixSize

    /// Passwords shorter than this are refused when exporting.
    public static let minimumPasswordLength = 8

    public enum Failure: Error, Equatable {
        /// The password doesn't open this archive (or the archive was changed after it was made).
        case wrongPassword
        /// The file says it is protected but can't be read as such.
        case damaged
    }

    /// Whether the source is a password-protected archive.
    public static func isEncrypted(_ source: ArchiveByteSource) -> Bool {
        guard source.size >= magic.count, let start = try? source.read(at: 0, count: magic.count) else { return false }
        return start == magic
    }

    // MARK: Writing

    /// Seals what it is given in chunks and passes them on. Call `finish()` once, after the
    /// last byte: it seals the last chunk, which may be shorter or even empty.
    public final class EncryptingSink: ArchiveByteSink {
        private let inner: ArchiveByteSink
        private let key: SymmetricKey
        private let header: Data
        private let prefix: Data
        private let chunkSize: Int
        private var pending = Data()
        private var index = 0
        private var finished = false

        public init(_ inner: ArchiveByteSink, password: String, iterations: UInt32 = defaultIterations, chunkSize: Int = defaultChunkSize) throws {
            precondition(acceptedIterations.contains(iterations), "Write only rounds a reader accepts.")
            precondition(acceptedChunkSizes.contains(chunkSize), "Write only chunk sizes a reader accepts.")
            self.inner = inner
            self.chunkSize = chunkSize
            let salt = randomBytes(saltSize)
            prefix = randomBytes(noncePrefixSize)
            var header = magic
            header.append(version)
            header.append(pbkdf2SHA256)
            header.appendUInt32BE(iterations)
            header.append(salt)
            header.appendUInt32BE(UInt32(chunkSize))
            header.append(prefix)
            self.header = header
            key = try deriveKey(password: password, salt: salt, iterations: iterations)
            try inner.write(header)
        }

        public func write(_ data: Data) throws {
            precondition(!finished, "Nothing is written after the last chunk.")
            pending.append(data)
            // A chunk is sealed once a byte after it arrives: then it can't be the last one.
            var consumed = 0
            while pending.count - consumed > chunkSize {
                let start = pending.startIndex + consumed
                try seal(pending[start..<(start + chunkSize)], isLast: false)
                consumed += chunkSize
            }
            if consumed > 0 { pending = Data(pending.dropFirst(consumed)) }
        }

        public func finish() throws {
            precondition(!finished, "An archive is finished once.")
            finished = true
            try seal(pending, isLast: true)
            pending = Data()
        }

        private func seal(_ chunk: Data, isLast: Bool) throws {
            let box = try AES.GCM.seal(chunk, using: key, nonce: try nonce(prefix: prefix, index: index), authenticating: header + [isLast ? 1 : 0])
            index += 1
            try inner.write(box.ciphertext + box.tag)
        }
    }

    // MARK: Reading

    /// The plain archive inside a protected one, opened a chunk at a time where it is read.
    /// Opening checks the password on the last chunk, so a wrong one fails at once; every
    /// chunk read afterwards is checked too, and its place: one changed, moved or cut off fails.
    public final class DecryptingSource: ArchiveByteSource {
        private let inner: ArchiveByteSource
        private let key: SymmetricKey
        private let header: Data
        private let prefix: Data
        private let chunkSize: Int
        private let chunkCount: Int
        private let body: Int
        /// The plain archive's size.
        public let size: Int
        /// The last two chunks opened, by index: a read across a chunk's end needs both.
        private var opened: [(index: Int, plain: Data)] = []

        public init(_ inner: ArchiveByteSource, password: String) throws {
            self.inner = inner
            guard inner.size >= headerSize + tagSize else { throw Failure.damaged }
            let header = try inner.read(at: 0, count: headerSize)
            guard header.prefix(magic.count) == magic else { throw Failure.damaged }
            var cursor = header.startIndex + magic.count
            guard header[cursor] == version, header[cursor + 1] == pbkdf2SHA256 else { throw Failure.damaged }
            cursor += 2
            let iterations = header.readUInt32BE(at: cursor - header.startIndex)
            cursor += 4
            let salt = header.subdata(in: cursor..<(cursor + saltSize))
            cursor += saltSize
            let chunkSize = Int(header.readUInt32BE(at: cursor - header.startIndex))
            cursor += 4
            prefix = header.subdata(in: cursor..<(cursor + noncePrefixSize))
            guard acceptedIterations.contains(iterations), acceptedChunkSizes.contains(chunkSize) else { throw Failure.damaged }
            self.header = header
            self.chunkSize = chunkSize

            body = inner.size - headerSize
            let sealedChunk = chunkSize + tagSize
            chunkCount = (body + sealedChunk - 1) / sealedChunk
            guard body - (chunkCount - 1) * sealedChunk >= tagSize else { throw Failure.damaged }
            size = body - chunkCount * tagSize
            key = try deriveKey(password: password, salt: salt, iterations: iterations)
            _ = try chunk(chunkCount - 1)
        }

        public func read(at offset: Int, count: Int) throws -> Data {
            guard offset >= 0, count >= 0, count <= size - offset else { throw DosarZipEngine.ZipError.invalidZipArchive }
            var result = Data(capacity: count)
            var position = offset
            while position < offset + count {
                let index = position / chunkSize
                let plain = try chunk(index)
                let from = position - index * chunkSize
                let take = min(plain.count - from, offset + count - position)
                guard take > 0 else { throw Failure.damaged }
                result.append(plain[(plain.startIndex + from)..<(plain.startIndex + from + take)])
                position += take
            }
            return result
        }

        private func chunk(_ index: Int) throws -> Data {
            if let hit = opened.first(where: { $0.index == index }) { return hit.plain }
            let sealedChunk = chunkSize + tagSize
            let start = headerSize + index * sealedChunk
            let length = min(sealedChunk, body - index * sealedChunk)
            let sealed = try inner.read(at: start, count: length)
            let plain: Data
            do {
                let box = try AES.GCM.SealedBox(
                    nonce: try nonce(prefix: prefix, index: index),
                    ciphertext: sealed.prefix(length - tagSize),
                    tag: sealed.suffix(tagSize)
                )
                plain = try AES.GCM.open(box, using: key, authenticating: header + [index == chunkCount - 1 ? 1 : 0])
            } catch {
                throw Failure.wrongPassword
            }
            opened.append((index, plain))
            if opened.count > 2 { opened.removeFirst() }
            return plain
        }
    }

    // MARK: Pieces

    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuffer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw Failure.damaged }
        return SymmetricKey(data: derived)
    }

    private static func nonce(prefix: Data, index: Int) throws -> AES.GCM.Nonce {
        var bytes = prefix
        bytes.appendUInt32BE(UInt32(index))
        return try AES.GCM.Nonce(data: bytes)
    }

    private static func randomBytes(_ count: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }
}

private extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) << 24 | UInt32(self[base + 1]) << 16 | UInt32(self[base + 2]) << 8 | UInt32(self[base + 3])
    }
}
