import Foundation
#if canImport(zlib)
import zlib
#endif

// MARK: - Bytes in and out

/// Where an archive is read from, a piece at a time and at any place: a file on disk, or
/// a password-protected one opened chunk by chunk (`ArchiveEncryption.DecryptingSource`).
/// Nothing reads a whole archive into memory.
public protocol ArchiveByteSource: AnyObject {
    /// How many bytes there are.
    var size: Int { get }
    /// `count` bytes from `offset`, exactly; anything outside the source throws.
    func read(at offset: Int, count: Int) throws -> Data
}

/// Where an archive is written, a piece after another: a file, or a password-protected one
/// sealed chunk by chunk (`ArchiveEncryption.EncryptingSink`).
public protocol ArchiveByteSink: AnyObject {
    func write(_ data: Data) throws
}

/// A file read where it lies.
public final class ArchiveFileSource: ArchiveByteSource {
    private let handle: FileHandle
    public let size: Int

    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = Int(try handle.seekToEnd())
    }

    deinit { try? handle.close() }

    public func read(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, count <= size - offset else { throw DosarZipEngine.ZipError.invalidZipArchive }
        guard count > 0 else { return Data() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw DosarZipEngine.ZipError.invalidZipArchive }
        return data
    }
}

/// A new file, written a piece after another, protected while the phone is locked: closed to it
/// (`complete`), or, for a file a running backup works on, open to it only while it is open
/// (`BackupFileProtection.working`).
public final class ArchiveFileSink: ArchiveByteSink {
    private let handle: FileHandle

    /// Makes the file (it must not exist yet) and opens it for writing.
    public init(creating url: URL, protection: FileProtectionType = .complete) throws {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.createFile(atPath: path, contents: nil, attributes: [.protectionKey: protection]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
        }
        handle = try FileHandle(forWritingTo: url)
    }

    deinit { try? handle.close() }

    public func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        try handle.write(contentsOf: data)
    }

    /// Everything written is on disk.
    public func close() throws {
        try handle.synchronize()
        try handle.close()
    }
}

// MARK: - Zip

/// A PKZip 2.0 writer and reader with no dependencies, using the system's `zlib` for raw
/// DEFLATE and CRC-32, compatible with macOS Archive Utility, `unzip` and Java's
/// `ZipInputStream`.
///
/// Both sides stream: the writer takes one file at a time and never keeps what it wrote,
/// the reader reads the directory and then one file at a time, in pieces. Both read the
/// same `Limits`, so whatever this app can write, it can read back.
public enum DosarZipEngine {

    /// What an archive may hold, read by the writer and the reader alike: an archive this
    /// app writes is one it reads back, on any phone that runs it. Memory doesn't grow with
    /// the archive, since nothing holds it whole; the limits keep each file's size known
    /// before it is read.
    public struct Limits: Sendable, Equatable {
        /// Files in one archive.
        public var maxEntries: Int
        /// Bytes of one file, as it is once read back.
        public var maxEntryBytes: Int
        /// Bytes of one file's name.
        public var maxPathBytes: Int
        /// How many times a compressed file may grow when read back…
        public var maxExpansion: Int
        /// …once it is bigger than this; a small file may grow any amount.
        public var expansionAllowance: Int
        /// Bytes of the whole archive.
        public var maxArchiveBytes: Int

        public init(
            maxEntries: Int,
            maxEntryBytes: Int,
            maxPathBytes: Int = 1_024,
            maxExpansion: Int = 200,
            expansionAllowance: Int = 1 << 20,
            maxArchiveBytes: Int = Int(UInt32.max) - 1
        ) {
            self.maxEntries = maxEntries
            self.maxEntryBytes = maxEntryBytes
            self.maxPathBytes = maxPathBytes
            self.maxExpansion = maxExpansion
            self.expansionAllowance = expansionAllowance
            self.maxArchiveBytes = maxArchiveBytes
        }

        /// The one set the app uses both ways: as many files as a plain zip can count (65 535
        /// marks a ZIP64 archive, which no writer here makes), 128 MB per file, a file at most
        /// 200 times its compressed size past its first megabyte, and a plain zip's 4 GB.
        public static let standard = Limits(maxEntries: Int(UInt16.max) - 1, maxEntryBytes: 128 << 20)

        /// Whether a file of `size` bytes kept as `stored` bytes may be read back.
        public func admitsExpansion(stored: Int, size: Int) -> Bool {
            size <= expansionAllowance || size / maxExpansion <= stored
        }
    }

    public enum ZipError: LocalizedError, Sendable, Equatable {
        case invalidZipArchive
        case endOfCentralDirectoryNotFound
        case unsupportedCompressionMethod(UInt16)
        case crcMismatch(path: String, expected: UInt32, actual: UInt32)
        case fileCorrupted(path: String)
        case unsafeEntryPath(path: String)
        case duplicateEntry(path: String)
        case sizeLimitExceeded
        /// More files than one archive holds.
        case tooManyFilesToWrite
        /// More bytes than one archive holds.
        case tooLargeToWrite
        /// One file bigger than an archive may carry.
        case fileTooLargeToWrite(path: String)
        case zlibError(code: Int32, message: String)

        public var errorDescription: String? {
            switch self {
            case .invalidZipArchive, .endOfCentralDirectoryNotFound:
                return String(localized: "Fișierul nu e o arhivă validă.")
            case .unsupportedCompressionMethod:
                return String(localized: "Arhiva folosește un tip de compresie pe care aplicația nu îl citește.")
            case .crcMismatch(let path, _, _), .fileCorrupted(let path):
                return String(localized: "Fișierul \(path) din arhivă e deteriorat.")
            case .unsafeEntryPath(let path):
                return String(localized: "Arhiva conține un nume de fișier nepermis: \(path).")
            case .duplicateEntry(let path):
                return String(localized: "Arhiva conține de două ori fișierul \(path).")
            case .sizeLimitExceeded:
                return String(localized: "Arhiva e prea mare pentru a fi deschisă pe acest dispozitiv.")
            case .tooManyFilesToWrite:
                return String(localized: "Dosarul are prea multe fișiere pentru o singură copie. Șterge documentele de care nu mai ai nevoie, apoi încearcă din nou.", comment: "Backup: more files than one backup can hold.")
            case .tooLargeToWrite:
                return String(localized: "Dosarul e prea mare pentru o singură copie. Șterge documentele mari de care nu mai ai nevoie, apoi încearcă din nou.", comment: "Backup: more bytes than one backup can hold.")
            case .fileTooLargeToWrite:
                return String(localized: "Un document e prea mare pentru o copie. Scoate-l din dosar și păstrează-l în altă parte, apoi încearcă din nou.", comment: "Backup: one file is too large for a backup.")
            case .zlibError:
                return String(localized: "Arhiva nu a putut fi dezarhivată.")
            }
        }
    }

    /// An entry path is accepted only if it is relative, uses `/`, and has no
    /// empty, `.` or `..` components.
    public static func isSafeEntryPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"), !path.contains(":") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let body = path.hasSuffix("/") ? components.dropLast() : components[...]
        return !body.isEmpty && body.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    // MARK: Checksums and compression

    /// IEEE 802.3 CRC-32 of `data`, continuing from `previous`.
    public static func computeCRC32(_ data: Data, continuing previous: UInt32 = 0) -> UInt32 {
        guard !data.isEmpty else { return previous }
        #if canImport(zlib)
        return data.withUnsafeBytes { ptr -> UInt32 in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return previous }
            return UInt32(crc32(uLong(previous), base, uInt(ptr.count)))
        }
        #else
        return previous
        #endif
    }

    /// Compresses one file with raw DEFLATE (-MAX_WBITS), as PKZip stores it.
    public static func deflateRaw(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        #if canImport(zlib)
        var stream = z_stream()
        let initStatus = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw ZipError.zlibError(code: initStatus, message: "deflateInit2 failed") }
        defer { deflateEnd(&stream) }

        var compressed = Data()
        let chunkSize = 1 << 16
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        try data.withUnsafeBytes { rawIn -> Void in
            guard let inBase = rawIn.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(data.count)
            var status = Z_OK
            while status == Z_OK {
                buffer.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = deflate(&stream, Z_FINISH)
                    let written = chunkSize - Int(stream.avail_out)
                    if written > 0, let base = outBuf.baseAddress { compressed.append(base, count: written) }
                }
            }
            guard status == Z_STREAM_END else { throw ZipError.zlibError(code: status, message: "deflate stream did not finish cleanly") }
        }
        return compressed
        #else
        return data
        #endif
    }

    /// Raw INFLATE fed a piece at a time; what comes out goes to `emit`, a piece at a time.
    final class Inflater {
        #if canImport(zlib)
        /// On the heap: zlib keeps the stream's address between calls.
        private let stream: UnsafeMutablePointer<z_stream>
        #endif
        private(set) var finished = false
        private static let outputSize = 1 << 18

        init() throws {
            #if canImport(zlib)
            stream = .allocate(capacity: 1)
            stream.initialize(to: z_stream())
            let status = inflateInit2_(stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard status == Z_OK else {
                stream.deinitialize(count: 1)
                stream.deallocate()
                throw ZipError.zlibError(code: status, message: "inflateInit2 failed")
            }
            #endif
        }

        deinit {
            #if canImport(zlib)
            inflateEnd(stream)
            stream.deinitialize(count: 1)
            stream.deallocate()
            #endif
        }

        func feed(_ input: Data, emit: (Data) throws -> Void) throws {
            #if canImport(zlib)
            guard !input.isEmpty, !finished else { return }
            let stream = stream
            var buffer = [UInt8](repeating: 0, count: Self.outputSize)
            var reachedEnd = false
            try input.withUnsafeBytes { rawIn -> Void in
                guard let inBase = rawIn.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
                stream.pointee.next_in = UnsafeMutablePointer(mutating: inBase)
                stream.pointee.avail_in = uInt(input.count)
                defer {
                    // Nothing of `input` is kept past this call.
                    stream.pointee.next_in = nil
                    stream.pointee.avail_in = 0
                }
                while true {
                    var status = Z_OK
                    var produced = Data()
                    buffer.withUnsafeMutableBufferPointer { outBuf in
                        stream.pointee.next_out = outBuf.baseAddress
                        stream.pointee.avail_out = uInt(Self.outputSize)
                        status = inflate(stream, Z_NO_FLUSH)
                        let written = Self.outputSize - Int(stream.pointee.avail_out)
                        if written > 0, let base = outBuf.baseAddress { produced = Data(bytes: base, count: written) }
                        stream.pointee.next_out = nil
                    }
                    if !produced.isEmpty { try emit(produced) }
                    switch status {
                    case Z_STREAM_END:
                        reachedEnd = true
                        return
                    case Z_OK where stream.pointee.avail_in > 0 || produced.count == Self.outputSize:
                        continue
                    case Z_OK, Z_BUF_ERROR:
                        // Everything given is taken; more comes with the next piece.
                        return
                    default:
                        throw ZipError.zlibError(code: status, message: "inflate failed")
                    }
                }
            }
            if reachedEnd { finished = true }
            #else
            try emit(input)
            #endif
        }
    }

    // MARK: Writing

    /// Writes an archive to a sink, one file at a time. Each file is checked against the
    /// limits before a byte of it is written; what the writer accepts, `Reader` reads.
    /// A file is compressed only when that makes it smaller and keeps it within what the
    /// reader lets a file expand; otherwise it is stored as it is.
    public final class Writer {
        private struct Record {
            let pathBytes: [UInt8]
            let uncompressedSize: UInt32
            let compressedSize: UInt32
            let crc: UInt32
            let compressionMethod: UInt16
            let dosTime: UInt16
            let dosDate: UInt16
            let localHeaderOffset: UInt32
        }

        public let limits: Limits
        private let sink: ArchiveByteSink
        private var records: [Record] = []
        private var paths: Set<String> = []
        private var offset = 0
        private var directoryBytes = 0
        private var finished = false

        public init(sink: ArchiveByteSink, limits: Limits = .standard) {
            self.sink = sink
            self.limits = limits
        }

        /// How many files are written so far.
        public var count: Int { records.count }

        public func add(path: String, data: Data, modifiedDate: Date) throws {
            precondition(!finished, "An archive takes no file once finished.")
            guard isSafeEntryPath(path) else { throw ZipError.unsafeEntryPath(path: path) }
            let pathBytes = Array(path.utf8)
            guard pathBytes.count <= limits.maxPathBytes else { throw ZipError.unsafeEntryPath(path: path) }
            guard !paths.contains(path) else { throw ZipError.duplicateEntry(path: path) }
            guard records.count < limits.maxEntries else { throw ZipError.tooManyFilesToWrite }
            guard data.count <= limits.maxEntryBytes else { throw ZipError.fileTooLargeToWrite(path: path) }

            let crc = computeCRC32(data)
            let compressed = try deflateRaw(data)
            let useCompression = !data.isEmpty && compressed.count < data.count && limits.admitsExpansion(stored: compressed.count, size: data.count)
            let payload = useCompression ? compressed : data
            let entryBytes = 30 + pathBytes.count + payload.count
            let recordBytes = 46 + pathBytes.count
            // Every offset, the directory and its end record stay inside what a plain zip describes.
            guard offset + entryBytes + directoryBytes + recordBytes + 22 <= limits.maxArchiveBytes else { throw ZipError.tooLargeToWrite }

            let (dosTime, dosDate) = dosDateTime(from: modifiedDate)
            let record = Record(
                pathBytes: pathBytes, uncompressedSize: UInt32(data.count), compressedSize: UInt32(payload.count), crc: crc,
                compressionMethod: useCompression ? 8 : 0, dosTime: dosTime, dosDate: dosDate, localHeaderOffset: UInt32(offset)
            )
            var header = Data(capacity: 30 + pathBytes.count)
            header.appendUInt32LE(0x04034b50) // Local file header signature
            header.appendUInt16LE(20)          // Version needed: 2.0
            header.appendUInt16LE(0x0800)      // General purpose bit flag: UTF-8 names (bit 11)
            header.appendUInt16LE(record.compressionMethod)
            header.appendUInt16LE(dosTime)
            header.appendUInt16LE(dosDate)
            header.appendUInt32LE(crc)
            header.appendUInt32LE(record.compressedSize)
            header.appendUInt32LE(record.uncompressedSize)
            header.appendUInt16LE(UInt16(pathBytes.count))
            header.appendUInt16LE(0)           // Extra field length
            header.append(contentsOf: pathBytes)
            try sink.write(header)
            try sink.write(payload)

            offset += entryBytes
            directoryBytes += recordBytes
            paths.insert(path)
            records.append(record)
        }

        /// Writes the directory and its end record. Returns the archive's size in bytes.
        @discardableResult
        public func finish() throws -> Int {
            precondition(!finished, "An archive is finished once.")
            finished = true
            var directory = Data(capacity: directoryBytes)
            for record in records {
                directory.appendUInt32LE(0x02014b50) // Central directory header signature
                directory.appendUInt16LE(0x0314)     // Version made by: UNIX (0x03), PKZip 2.0 (0x14)
                directory.appendUInt16LE(20)         // Version needed: 2.0
                directory.appendUInt16LE(0x0800)     // UTF-8 names
                directory.appendUInt16LE(record.compressionMethod)
                directory.appendUInt16LE(record.dosTime)
                directory.appendUInt16LE(record.dosDate)
                directory.appendUInt32LE(record.crc)
                directory.appendUInt32LE(record.compressedSize)
                directory.appendUInt32LE(record.uncompressedSize)
                directory.appendUInt16LE(UInt16(record.pathBytes.count))
                directory.appendUInt16LE(0)          // Extra field length
                directory.appendUInt16LE(0)          // File comment length
                directory.appendUInt16LE(0)          // Disk number start
                directory.appendUInt16LE(0)          // Internal file attributes
                directory.appendUInt32LE(0o100644 << 16) // External attributes: regular file rw-r--r--
                directory.appendUInt32LE(record.localHeaderOffset)
                directory.append(contentsOf: record.pathBytes)
            }
            directory.appendUInt32LE(0x06054b50) // End of central directory signature
            directory.appendUInt16LE(0)          // Disk number
            directory.appendUInt16LE(0)          // Start disk
            directory.appendUInt16LE(UInt16(records.count))
            directory.appendUInt16LE(UInt16(records.count))
            directory.appendUInt32LE(UInt32(directoryBytes))
            directory.appendUInt32LE(UInt32(offset))
            directory.appendUInt16LE(0)          // Comment length
            try sink.write(directory)
            return offset + directory.count
        }
    }

    // MARK: Reading

    /// Reads an archive's directory, then each file on request, a piece at a time. Every
    /// file is checked against the limits before any of it is read.
    public final class Reader {
        public struct Item: Sendable, Equatable {
            public let path: String
            public let method: UInt16
            public let crc: UInt32
            public let compressedSize: Int
            public let size: Int
            public let modifiedDate: Date
            let localHeaderOffset: Int
        }

        /// The archive's files, in the directory's order (folders left out).
        public let items: [Item]
        private let indexByPath: [String: Int]
        private let source: ArchiveByteSource
        public let limits: Limits
        /// How much of a file is read at once.
        static let pieceSize = 1 << 20

        public init(source: ArchiveByteSource, limits: Limits = .standard) throws {
            self.source = source
            self.limits = limits
            let size = source.size
            guard size >= 22 else { throw ZipError.invalidZipArchive }
            guard size <= limits.maxArchiveBytes else { throw ZipError.sizeLimitExceeded }

            // The end of central directory record, searched backwards over its longest comment.
            let tailStart = max(0, size - 65_557)
            let tail = try source.read(at: tailStart, count: size - tailStart)
            var eocd: Int?
            for i in stride(from: tail.count - 22, through: 0, by: -1) where tail.readUInt32LE(at: i) == 0x06054b50 {
                eocd = i
                break
            }
            guard let eocd else { throw ZipError.endOfCentralDirectoryNotFound }

            // A zip64 archive marks its counts and offsets with all ones; no writer here makes one.
            let totalEntries = Int(tail.readUInt16LE(at: eocd + 10))
            guard totalEntries != Int(UInt16.max),
                  tail.readUInt32LE(at: eocd + 12) != UInt32.max,
                  tail.readUInt32LE(at: eocd + 16) != UInt32.max else { throw ZipError.sizeLimitExceeded }
            let directorySize = Int(tail.readUInt32LE(at: eocd + 12))
            let directoryOffset = Int(tail.readUInt32LE(at: eocd + 16))
            guard directoryOffset + directorySize <= tailStart + eocd else { throw ZipError.invalidZipArchive }
            guard totalEntries <= limits.maxEntries else { throw ZipError.sizeLimitExceeded }

            var cursor = PieceCursor(source: source, start: directoryOffset, end: directoryOffset + directorySize)
            var items: [Item] = []
            var index: [String: Int] = [:]
            for _ in 0..<totalEntries {
                let fixed = try cursor.take(46)
                guard fixed.readUInt32LE(at: 0) == 0x02014b50 else { throw ZipError.invalidZipArchive }
                let method = fixed.readUInt16LE(at: 10)
                let dosTime = fixed.readUInt16LE(at: 12)
                let dosDate = fixed.readUInt16LE(at: 14)
                let crc = fixed.readUInt32LE(at: 16)
                let compressedSize = Int(fixed.readUInt32LE(at: 20))
                let uncompressedSize = Int(fixed.readUInt32LE(at: 24))
                let nameLength = Int(fixed.readUInt16LE(at: 28))
                let extraLength = Int(fixed.readUInt16LE(at: 30))
                let commentLength = Int(fixed.readUInt16LE(at: 32))
                let localHeaderOffset = Int(fixed.readUInt32LE(at: 42))
                guard nameLength <= limits.maxPathBytes else { throw ZipError.sizeLimitExceeded }
                let nameData = try cursor.take(nameLength)
                try cursor.skip(extraLength + commentLength)
                let path = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
                guard isSafeEntryPath(path) else { throw ZipError.unsafeEntryPath(path: path) }
                if path.hasSuffix("/") { continue } // A folder.
                guard index[path] == nil else { throw ZipError.duplicateEntry(path: path) }
                guard uncompressedSize <= limits.maxEntryBytes else { throw ZipError.sizeLimitExceeded }
                if method == 0 {
                    guard compressedSize == uncompressedSize else { throw ZipError.fileCorrupted(path: path) }
                } else {
                    guard limits.admitsExpansion(stored: compressedSize, size: uncompressedSize) else { throw ZipError.sizeLimitExceeded }
                }
                guard localHeaderOffset < directoryOffset else { throw ZipError.invalidZipArchive }
                index[path] = items.count
                items.append(Item(
                    path: path, method: method, crc: crc, compressedSize: compressedSize, size: uncompressedSize,
                    modifiedDate: date(fromDosTime: dosTime, date: dosDate), localHeaderOffset: localHeaderOffset
                ))
            }
            self.items = items
            indexByPath = index
        }

        public func item(at path: String) -> Item? {
            indexByPath[path].map { items[$0] }
        }

        /// One file, whole. For the small files an archive describes itself with; its size is
        /// already within `maxEntryBytes`.
        public func data(of item: Item) throws -> Data {
            var data = Data(capacity: item.size)
            try stream(item) { data.append($0) }
            return data
        }

        /// One file a piece at a time, checked against its size and CRC as it goes; a file
        /// that turns out longer or shorter than it says, or changed, throws.
        public func stream(_ item: Item, into emit: (Data) throws -> Void) throws {
            let header = try source.read(at: item.localHeaderOffset, count: 30)
            guard header.readUInt32LE(at: 0) == 0x04034b50 else { throw ZipError.invalidZipArchive }
            let dataStart = item.localHeaderOffset + 30 + Int(header.readUInt16LE(at: 26)) + Int(header.readUInt16LE(at: 28))
            guard dataStart + item.compressedSize <= source.size else { throw ZipError.invalidZipArchive }

            var tally = Tally(size: item.size)
            var cursor = PieceCursor(source: source, start: dataStart, end: dataStart + item.compressedSize)
            switch item.method {
            case 0:
                while cursor.remaining > 0 {
                    let piece = try cursor.take(min(Self.pieceSize, cursor.remaining))
                    try tally.count(piece)
                    try emit(piece)
                }
            case 8:
                let inflater = try Inflater()
                while cursor.remaining > 0, !inflater.finished {
                    try inflater.feed(try cursor.take(min(Self.pieceSize, cursor.remaining))) { piece in
                        try tally.count(piece)
                        try emit(piece)
                    }
                }
                guard inflater.finished || item.size == 0 else { throw ZipError.fileCorrupted(path: item.path) }
            default:
                throw ZipError.unsupportedCompressionMethod(item.method)
            }
            guard tally.produced == item.size else { throw ZipError.fileCorrupted(path: item.path) }
            guard tally.crc == item.crc else { throw ZipError.crcMismatch(path: item.path, expected: item.crc, actual: tally.crc) }
        }

        /// What a file gave so far: never more than it said, and its CRC.
        private struct Tally {
            let size: Int
            private(set) var produced = 0
            private(set) var crc: UInt32 = 0

            init(size: Int) { self.size = size }

            mutating func count(_ piece: Data) throws {
                produced += piece.count
                guard produced <= size else { throw ZipError.sizeLimitExceeded }
                crc = computeCRC32(piece, continuing: crc)
            }
        }
    }

    /// Reads a range of a source in order, holding at most one piece of it.
    struct PieceCursor {
        let source: ArchiveByteSource
        private(set) var position: Int
        let end: Int
        private var window = Data()
        private var windowStart = 0

        init(source: ArchiveByteSource, start: Int, end: Int) {
            self.source = source
            position = start
            self.end = end
            windowStart = start
        }

        var remaining: Int { end - position }

        mutating func take(_ count: Int) throws -> Data {
            guard count >= 0, count <= remaining else { throw ZipError.invalidZipArchive }
            if position + count > windowStart + window.count {
                // A new window from here: at least a piece, or the whole request when it is longer.
                windowStart = position
                window = try source.read(at: position, count: min(max(count, Reader.pieceSize), remaining))
            }
            let from = window.startIndex + (position - windowStart)
            position += count
            return window.subdata(in: from..<(from + count))
        }

        mutating func skip(_ count: Int) throws {
            guard count >= 0, count <= remaining else { throw ZipError.invalidZipArchive }
            position += count
        }
    }

    // MARK: Dates

    static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar.dosar
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        // A zip date runs from 1980 to 2107. The manifest keeps the real export time,
        // so a date outside that range is written as its nearest end.
        guard let year = comps.year, year >= 1980 else { return (0, (1 << 5) | 1) }
        guard year <= 2107 else { return ((23 << 11) | (59 << 5) | 29, (127 << 9) | (12 << 5) | 31) }
        let month = max(1, comps.month ?? 1)
        let day = max(1, comps.day ?? 1)
        let dosTime = UInt16(((comps.hour ?? 0) << 11) | ((comps.minute ?? 0) << 5) | ((comps.second ?? 0) / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }

    static func date(fromDosTime time: UInt16, date: UInt16) -> Date {
        var comps = DateComponents()
        comps.year = 1980 + Int((date >> 9) & 0x7F)
        comps.month = max(1, min(12, Int((date >> 5) & 0x0F)))
        comps.day = max(1, min(31, Int(date & 0x1F)))
        comps.hour = Int((time >> 11) & 0x1F)
        comps.minute = Int((time >> 5) & 0x3F)
        comps.second = Int((time & 0x1F) * 2)
        return Calendar.dosar.date(from: comps) ?? Date()
    }
}

extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) | (UInt32(self[base + 1]) << 8) | (UInt32(self[base + 2]) << 16) | (UInt32(self[base + 3]) << 24)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }
}
