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
public enum ArchiveEncryption {
    public static let magic = Data("DOSARENC".utf8)
    static let version: UInt8 = 1
    static let pbkdf2SHA256: UInt8 = 1
    /// Slow enough to make guessing expensive, quick enough on a phone (well under a second).
    public static let defaultIterations: UInt32 = 600_000
    static let maxIterations: UInt32 = 10_000_000
    static let saltSize = 16
    static let noncePrefixSize = 8
    static let tagSize = 16
    public static let defaultChunkSize = 1 << 20
    static let headerSize = magic.count + 1 + 1 + 4 + saltSize + 4 + noncePrefixSize

    /// Passwords shorter than this are refused when exporting.
    public static let minimumPasswordLength = 8

    public enum Failure: Error, Equatable {
        /// The password doesn't open this archive (or the archive was changed after it was made).
        case wrongPassword
        /// The file says it is protected but can't be read as such.
        case damaged
    }

    /// Whether the data is a password-protected archive.
    public static func isEncrypted(_ data: Data) -> Bool {
        data.count >= magic.count && data.prefix(magic.count).elementsEqual(magic)
    }

    /// Encrypts a plain archive with a key made from `password`.
    public static func encrypt(
        _ plain: Data,
        password: String,
        iterations: UInt32 = defaultIterations,
        chunkSize: Int = defaultChunkSize
    ) throws -> Data {
        precondition(chunkSize > 0 && chunkSize <= Int(UInt32.max))
        let salt = randomBytes(saltSize)
        let prefix = randomBytes(noncePrefixSize)
        var header = magic
        header.append(version)
        header.append(pbkdf2SHA256)
        header.appendUInt32BE(iterations)
        header.append(salt)
        header.appendUInt32BE(UInt32(chunkSize))
        header.append(prefix)

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        var output = header
        output.reserveCapacity(header.count + plain.count + (plain.count / chunkSize + 1) * tagSize)
        let chunkCount = max(1, (plain.count + chunkSize - 1) / chunkSize)
        for index in 0..<chunkCount {
            let start = plain.startIndex + index * chunkSize
            let end = min(start + chunkSize, plain.endIndex)
            let isLast = index == chunkCount - 1
            let box = try AES.GCM.seal(
                plain[start..<end], using: key,
                nonce: try nonce(prefix: prefix, index: index),
                authenticating: header + [isLast ? 1 : 0]
            )
            output.append(box.ciphertext)
            output.append(box.tag)
        }
        return output
    }

    /// Opens a password-protected archive and returns the plain one.
    public static func decrypt(_ data: Data, password: String) throws -> Data {
        guard isEncrypted(data), data.count >= headerSize + tagSize else { throw Failure.damaged }
        // Offsets count from the data's own start, whatever slice it is.
        let base = data.startIndex
        var cursor = base + magic.count
        guard data[cursor] == version, data[cursor + 1] == pbkdf2SHA256 else { throw Failure.damaged }
        cursor += 2
        let iterations = data.readUInt32BE(at: cursor - base)
        cursor += 4
        let salt = data.subdata(in: cursor..<(cursor + saltSize))
        cursor += saltSize
        let chunkSize = Int(data.readUInt32BE(at: cursor - base))
        cursor += 4
        let prefix = data.subdata(in: cursor..<(cursor + noncePrefixSize))
        guard (1...maxIterations).contains(iterations), chunkSize > 0 else { throw Failure.damaged }
        let header = data.subdata(in: base..<(base + headerSize))

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let body = data.count - headerSize
        let sealedChunk = chunkSize + tagSize
        let chunkCount = (body + sealedChunk - 1) / sealedChunk
        var plain = Data()
        plain.reserveCapacity(max(0, body - chunkCount * tagSize))
        for index in 0..<chunkCount {
            let start = base + headerSize + index * sealedChunk
            let end = min(start + sealedChunk, data.endIndex)
            guard end - start >= tagSize else { throw Failure.damaged }
            let isLast = index == chunkCount - 1
            do {
                let box = try AES.GCM.SealedBox(
                    nonce: try nonce(prefix: prefix, index: index),
                    ciphertext: data[start..<(end - tagSize)],
                    tag: data[(end - tagSize)..<end]
                )
                plain.append(try AES.GCM.open(box, using: key, authenticating: header + [isLast ? 1 : 0]))
            } catch {
                throw Failure.wrongPassword
            }
        }
        return plain
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
