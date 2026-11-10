import Foundation
#if canImport(zlib)
import zlib
#endif

/// Lightweight, zero-dependency, pure Swift PKZip 2.0 encoder and decoder
/// using Apple's system `zlib` for raw DEFLATE/INFLATE and CRC-32 calculations.
/// Conforms to PKZip APPNOTE.TXT and standard ZIP specifications for full
/// cross-platform compatibility with macOS Archive Utility, unzip, and Java ZipInputStream.
public final class DosarZipEngine: Sendable {
    public static let shared = DosarZipEngine()
    
    public init() {}
    
    // MARK: - Types
    
    public struct Entry: Sendable {
        public let path: String
        public let data: Data
        public let modifiedDate: Date
        
        public init(path: String, data: Data, modifiedDate: Date = Date()) {
            self.path = path
            self.data = data
            self.modifiedDate = modifiedDate
        }
    }
    
    /// Size limits applied while reading an archive.
    public struct Limits: Sendable {
        public var maxEntries: Int
        public var maxEntryBytes: Int
        public var maxTotalBytes: Int

        public init(maxEntries: Int, maxEntryBytes: Int, maxTotalBytes: Int) {
            self.maxEntries = maxEntries
            self.maxEntryBytes = maxEntryBytes
            self.maxTotalBytes = maxTotalBytes
        }

        /// Room for a large household: thousands of files, scans up to 128 MB each, 512 MB in total.
        public static let standard = Limits(maxEntries: 20_000, maxEntryBytes: 128 * 1_024 * 1_024, maxTotalBytes: 512 * 1_024 * 1_024)
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
        /// More files, or bigger ones, than a plain zip can describe.
        case tooLargeToWrite
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
            case .tooLargeToWrite:
                return String(localized: "Dosarul are prea multe fișiere pentru o singură copie. Arhivează documentele vechi de care nu mai ai nevoie, apoi încearcă din nou.")
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
    
    // MARK: - Compression & Decompression (zlib)
    
    /// Computes IEEE 802.3 CRC-32 checksum.
    public static func computeCRC32(_ data: Data) -> UInt32 {
        guard !data.isEmpty else { return 0 }
        #if canImport(zlib)
        return data.withUnsafeBytes { ptr -> UInt32 in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return 0 }
            return UInt32(crc32(0, base, uInt(ptr.count)))
        }
        #else
        return 0
        #endif
    }
    
    /// Compresses data using raw DEFLATE (-MAX_WBITS) for PKZip format.
    public static func deflateRaw(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        #if canImport(zlib)
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw ZipError.zlibError(code: initStatus, message: "deflateInit2 failed")
        }
        defer { deflateEnd(&stream) }
        
        var compressed = Data()
        let chunkSize = 32768
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
                    
                    status = deflate(&stream, stream.avail_in == 0 ? Z_FINISH : Z_NO_FLUSH)
                    let bytesWritten = chunkSize - Int(stream.avail_out)
                    if bytesWritten > 0, let base = outBuf.baseAddress {
                        compressed.append(base, count: bytesWritten)
                    }
                }
            }
            guard status == Z_STREAM_END else {
                throw ZipError.zlibError(code: status, message: "deflate stream did not finish cleanly")
            }
        }
        return compressed
        #else
        return data
        #endif
    }
    
    /// Decompresses raw DEFLATE (-MAX_WBITS) data from a PKZip archive.
    public static func inflateRaw(_ data: Data, maxOutputBytes: Int = .max) throws -> Data {
        guard !data.isEmpty else { return Data() }
        #if canImport(zlib)
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw ZipError.zlibError(code: initStatus, message: "inflateInit2 failed")
        }
        defer { inflateEnd(&stream) }
        
        var decompressed = Data()
        let chunkSize = 32768
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
                    
                    status = inflate(&stream, Z_NO_FLUSH)
                    let bytesWritten = chunkSize - Int(stream.avail_out)
                    if bytesWritten > 0, let base = outBuf.baseAddress {
                        decompressed.append(base, count: bytesWritten)
                    }
                }
                if decompressed.count > maxOutputBytes {
                    throw ZipError.sizeLimitExceeded
                }
            }
            guard status == Z_STREAM_END else {
                throw ZipError.zlibError(code: status, message: "inflate stream did not finish cleanly")
            }
        }
        return decompressed
        #else
        return data
        #endif
    }
    
    // MARK: - Packaging / Encoder
    
    /// Encodes a list of `Entry` items into a fully compliant standard PKZip `.zip` / `.dosar` archive byte buffer.
    /// A plain zip describes at most 65,535 files and 4 GB; anything more is
    /// refused with `tooLargeToWrite` instead of being written wrong.
    public static func createArchive(entries: [Entry]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else { throw ZipError.tooLargeToWrite }
        var archiveData = Data()
        var centralDirectoryData = Data()
        
        struct Record {
            let path: String
            let uncompressedSize: UInt32
            let compressedSize: UInt32
            let crc: UInt32
            let compressionMethod: UInt16
            let dosTime: UInt16
            let dosDate: UInt16
            let localHeaderOffset: UInt32
        }
        
        var records: [Record] = []
        
        for entry in entries {
            guard isSafeEntryPath(entry.path) else {
                throw ZipError.unsafeEntryPath(path: entry.path)
            }
            
            let rawData = entry.data
            let pathBytes = Array(entry.path.utf8)
            guard rawData.count <= Int(UInt32.max), pathBytes.count <= Int(UInt16.max),
                  archiveData.count <= Int(UInt32.max) else { throw ZipError.tooLargeToWrite }
            let crc = computeCRC32(rawData)
            let uncompressedSize = UInt32(rawData.count)
            
            let compressedData = try deflateRaw(rawData)
            // Use DEFLATE (8) only if it actually reduces size and data is not empty; otherwise STORE (0)
            let useCompression = compressedData.count < rawData.count && !rawData.isEmpty
            let payload = useCompression ? compressedData : rawData
            let compressionMethod: UInt16 = useCompression ? 8 : 0
            let compressedSize = UInt32(payload.count)
            
            let (dosTime, dosDate) = dosDateTime(from: entry.modifiedDate)
            let localHeaderOffset = UInt32(archiveData.count)
            
            // 1. Local File Header
            archiveData.appendUInt32LE(0x04034b50) // Local file header signature
            archiveData.appendUInt16LE(20)          // Version needed: 2.0
            archiveData.appendUInt16LE(0x0800)      // General purpose bit flag: UTF-8 encoding (bit 11)
            archiveData.appendUInt16LE(compressionMethod)
            archiveData.appendUInt16LE(dosTime)
            archiveData.appendUInt16LE(dosDate)
            archiveData.appendUInt32LE(crc)
            archiveData.appendUInt32LE(compressedSize)
            archiveData.appendUInt32LE(uncompressedSize)
            archiveData.appendUInt16LE(UInt16(pathBytes.count))
            archiveData.appendUInt16LE(0)           // Extra field length
            archiveData.append(contentsOf: pathBytes)
            archiveData.append(payload)
            
            records.append(Record(
                path: entry.path,
                uncompressedSize: uncompressedSize,
                compressedSize: compressedSize,
                crc: crc,
                compressionMethod: compressionMethod,
                dosTime: dosTime,
                dosDate: dosDate,
                localHeaderOffset: localHeaderOffset
            ))
        }
        
        // 2. Central Directory
        guard archiveData.count <= Int(UInt32.max) else { throw ZipError.tooLargeToWrite }
        let centralDirectoryOffset = UInt32(archiveData.count)
        for record in records {
            let pathBytes = Array(record.path.utf8)
            centralDirectoryData.appendUInt32LE(0x02014b50) // Central directory header signature
            centralDirectoryData.appendUInt16LE(0x0314)     // Version made by: UNIX (0x03), PKZip 2.0 (0x14)
            centralDirectoryData.appendUInt16LE(20)         // Version needed: 2.0
            centralDirectoryData.appendUInt16LE(0x0800)     // UTF-8 encoding flag
            centralDirectoryData.appendUInt16LE(record.compressionMethod)
            centralDirectoryData.appendUInt16LE(record.dosTime)
            centralDirectoryData.appendUInt16LE(record.dosDate)
            centralDirectoryData.appendUInt32LE(record.crc)
            centralDirectoryData.appendUInt32LE(record.compressedSize)
            centralDirectoryData.appendUInt32LE(record.uncompressedSize)
            centralDirectoryData.appendUInt16LE(UInt16(pathBytes.count))
            centralDirectoryData.appendUInt16LE(0)          // Extra field length
            centralDirectoryData.appendUInt16LE(0)          // File comment length
            centralDirectoryData.appendUInt16LE(0)          // Disk number start
            centralDirectoryData.appendUInt16LE(0)          // Internal file attributes
            centralDirectoryData.appendUInt32LE(0o100644 << 16) // External file attributes: regular file rw-r--r--
            centralDirectoryData.appendUInt32LE(record.localHeaderOffset)
            centralDirectoryData.append(contentsOf: pathBytes)
        }
        
        guard centralDirectoryData.count <= Int(UInt32.max) else { throw ZipError.tooLargeToWrite }
        let centralDirectorySize = UInt32(centralDirectoryData.count)
        archiveData.append(centralDirectoryData)
        
        // 3. End of Central Directory (EOCD)
        archiveData.appendUInt32LE(0x06054b50) // EOCD signature
        archiveData.appendUInt16LE(0)          // Disk number
        archiveData.appendUInt16LE(0)          // Start disk
        archiveData.appendUInt16LE(UInt16(records.count)) // Entries on this disk
        archiveData.appendUInt16LE(UInt16(records.count)) // Total entries
        archiveData.appendUInt32LE(centralDirectorySize)
        archiveData.appendUInt32LE(centralDirectoryOffset)
        archiveData.appendUInt16LE(0)          // Comment length
        
        return archiveData
    }
    
    // MARK: - Unpackaging / Decoder
    
    /// Unpacks a PKZip `.zip` / `.dosar` archive byte buffer and returns all contained entries.
    ///
    /// Offsets in the archive count from the data's own start, so a slice of a
    /// bigger buffer reads the same as a copy of it.
    public static func unpackArchive(_ archiveData: Data, limits: Limits = .standard) throws -> [Entry] {
        guard archiveData.count >= 22 else { throw ZipError.invalidZipArchive }
        let base = archiveData.startIndex
        
        // Step 1: Locate End of Central Directory Record (EOCD)
        // Search backwards for 0x06054b50
        var eocdOffset: Int?
        let maxSearch = max(0, archiveData.count - 65557)
        for i in stride(from: archiveData.count - 22, through: maxSearch, by: -1) {
            if readUInt32LE(archiveData, at: i) == 0x06054b50 {
                eocdOffset = i
                break
            }
        }
        
        guard let eocd = eocdOffset else {
            throw ZipError.endOfCentralDirectoryNotFound
        }
        
        // A zip64 archive marks its counts and offsets with all ones; it is never
        // one this app wrote, and its real values live elsewhere.
        let totalEntries = Int(readUInt16LE(archiveData, at: eocd + 10))
        guard totalEntries != Int(UInt16.max),
              readUInt32LE(archiveData, at: eocd + 12) != UInt32.max,
              readUInt32LE(archiveData, at: eocd + 16) != UInt32.max else { throw ZipError.sizeLimitExceeded }
        let cdSize = Int(readUInt32LE(archiveData, at: eocd + 12))
        let cdOffset = Int(readUInt32LE(archiveData, at: eocd + 16))
        
        guard cdOffset + cdSize <= archiveData.count else {
            throw ZipError.invalidZipArchive
        }
        
        guard totalEntries <= limits.maxEntries else { throw ZipError.sizeLimitExceeded }

        var currentCD = cdOffset
        var entries: [Entry] = []
        var seenPaths: Set<String> = []
        var totalBytes = 0

        for _ in 0..<totalEntries {
            guard currentCD + 46 <= archiveData.count else { throw ZipError.invalidZipArchive }
            let sig = readUInt32LE(archiveData, at: currentCD)
            guard sig == 0x02014b50 else { throw ZipError.invalidZipArchive }
            
            let method = readUInt16LE(archiveData, at: currentCD + 10)
            let dosTime = readUInt16LE(archiveData, at: currentCD + 12)
            let dosDate = readUInt16LE(archiveData, at: currentCD + 14)
            let crc = readUInt32LE(archiveData, at: currentCD + 16)
            let compSize = Int(readUInt32LE(archiveData, at: currentCD + 20))
            let uncompSize = Int(readUInt32LE(archiveData, at: currentCD + 24))
            let nameLen = Int(readUInt16LE(archiveData, at: currentCD + 28))
            let extraLen = Int(readUInt16LE(archiveData, at: currentCD + 30))
            let commentLen = Int(readUInt16LE(archiveData, at: currentCD + 32))
            let localHeaderOffset = Int(readUInt32LE(archiveData, at: currentCD + 42))
            
            let nameStart = currentCD + 46
            guard nameStart + nameLen <= archiveData.count else { throw ZipError.invalidZipArchive }
            let nameData = archiveData.subdata(in: (base + nameStart)..<(base + nameStart + nameLen))
            let path = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            
            guard isSafeEntryPath(path) else {
                throw ZipError.unsafeEntryPath(path: path)
            }

            // Skip directory entries ending with "/"
            if !path.hasSuffix("/") {
                guard seenPaths.insert(path).inserted else { throw ZipError.duplicateEntry(path: path) }
                guard uncompSize <= limits.maxEntryBytes, totalBytes + uncompSize <= limits.maxTotalBytes else {
                    throw ZipError.sizeLimitExceeded
                }
                totalBytes += uncompSize
                // Read from Local File Header
                guard localHeaderOffset + 30 <= archiveData.count else { throw ZipError.invalidZipArchive }
                let localSig = readUInt32LE(archiveData, at: localHeaderOffset)
                guard localSig == 0x04034b50 else { throw ZipError.invalidZipArchive }
                let localNameLen = Int(readUInt16LE(archiveData, at: localHeaderOffset + 26))
                let localExtraLen = Int(readUInt16LE(archiveData, at: localHeaderOffset + 28))
                
                let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
                guard dataStart + compSize <= archiveData.count else { throw ZipError.invalidZipArchive }
                let rawPayload = archiveData.subdata(in: (base + dataStart)..<(base + dataStart + compSize))
                
                let extractedData: Data
                if method == 0 {
                    extractedData = rawPayload
                } else if method == 8 {
                    extractedData = try inflateRaw(rawPayload, maxOutputBytes: uncompSize)
                } else {
                    throw ZipError.unsupportedCompressionMethod(method)
                }
                
                guard extractedData.count == uncompSize else {
                    throw ZipError.fileCorrupted(path: path)
                }
                
                let actualCRC = computeCRC32(extractedData)
                guard actualCRC == crc else {
                    throw ZipError.crcMismatch(path: path, expected: crc, actual: actualCRC)
                }
                
                let entryDate = date(fromDosTime: dosTime, date: dosDate)
                entries.append(Entry(path: path, data: extractedData, modifiedDate: entryDate))
            }
            
            currentCD += 46 + nameLen + extraLen + commentLen
        }
        
        return entries
    }
    
    // MARK: - Internal Binary Helpers
    
    private static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar.dosar
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        // A zip date runs from 1980 to 2107. The manifest keeps the real export time,
        // so a date outside that range is written as its nearest end.
        guard let rawYear = comps.year, rawYear >= 1980 else { return (0, (1 << 5) | 1) }
        guard rawYear <= 2107 else { return ((23 << 11) | (59 << 5) | 29, (127 << 9) | (12 << 5) | 31) }
        let year = rawYear
        let month = max(1, comps.month ?? 1)
        let day = max(1, comps.day ?? 1)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
    
    private static func date(fromDosTime time: UInt16, date: UInt16) -> Date {
        let day = Int(date & 0x1F)
        let month = Int((date >> 5) & 0x0F)
        let year = 1980 + Int((date >> 9) & 0x7F)
        
        let second = Int((time & 0x1F) * 2)
        let minute = Int((time >> 5) & 0x3F)
        let hour = Int((time >> 11) & 0x1F)
        
        var comps = DateComponents()
        comps.year = year
        comps.month = max(1, min(12, month))
        comps.day = max(1, min(31, day))
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return Calendar.dosar.date(from: comps) ?? Date()
    }
    
    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        return b0 | (b1 << 8)
    }
    
    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        let b0 = UInt32(data[base])
        let b1 = UInt32(data[base + 1])
        let b2 = UInt32(data[base + 2])
        let b3 = UInt32(data[base + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        let b0 = UInt8(value & 0xFF)
        let b1 = UInt8((value >> 8) & 0xFF)
        append(contentsOf: [b0, b1])
    }
    
    mutating func appendUInt32LE(_ value: UInt32) {
        let b0 = UInt8(value & 0xFF)
        let b1 = UInt8((value >> 8) & 0xFF)
        let b2 = UInt8((value >> 16) & 0xFF)
        let b3 = UInt8((value >> 24) & 0xFF)
        append(contentsOf: [b0, b1, b2, b3])
    }
}
