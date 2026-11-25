package com.ar.dosarcusina.archive

import com.ar.dosarcusina.core.values.DosarCalendar
import java.io.ByteArrayOutputStream
import java.text.Normalizer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.zip.CRC32
import java.util.zip.DataFormatException
import java.util.zip.Deflater

/**
 * A PKZip 2.0 writer and reader, the iOS app's `DosarZipEngine`
 * (ios/DosarCuSina/Services/Archive/DosarZipEngine.swift) byte for byte where it counts: raw
 * DEFLATE or STORE entries, CRC-32, UTF-8 names, never ZIP64. It uses only `java.util.zip`'s
 * `Deflater`, `Inflater` and `CRC32`, which the JVM and Android both have.
 *
 * Both sides stream: the writer takes one file at a time and never keeps what it wrote, the
 * reader reads the directory and then one file at a time, in pieces. Both read the same
 * [Limits], so whatever this app can write, it can read back, and what the iOS app refuses,
 * this refuses. The reader checks its whole directory against them (every file's size, all of
 * them together, each file's place) before it hands out a byte, so a summary refuses what an
 * import would.
 */
object DosarZipEngine {
    /**
     * What an archive may hold, read by the writer and the reader alike: an archive this app
     * writes is one it reads back, on any phone that runs it. Memory doesn't grow with the
     * archive, since nothing holds it whole; the limits keep each file's size known before it is
     * read, and what all of them take once unpacked on the phone.
     */
    data class Limits(
        /** Files in one archive. */
        val maxEntries: Int,
        /** Bytes of one file, as it is once read back. */
        val maxEntryBytes: Long,
        /** Bytes of one file's name. */
        val maxPathBytes: Int = 1_024,
        /** How many times a compressed file may grow when read back… */
        val maxExpansion: Int = 200,
        /** …once it is bigger than this; a small file may grow any amount. */
        val expansionAllowance: Long = MEBIBYTE,
        /** Bytes of the whole archive. */
        val maxArchiveBytes: Long = UINT32_MAX - 1,
        /** Bytes of every file together, as they are once read back: what bringing it in writes. */
        val maxUnpackedBytes: Long = STANDARD_UNPACKED_BYTES,
    ) {
        /** Whether a file of [size] bytes kept as [stored] bytes may be read back. */
        fun admitsExpansion(stored: Long, size: Long): Boolean =
            size <= expansionAllowance || size / maxExpansion <= stored

        companion object {
            /**
             * The one set the app uses both ways, the iOS app's `Limits.standard`: as many files as
             * a plain zip can count (65 535 marks a ZIP64 archive, which no writer here makes),
             * 128 MB per file, a file at most 200 times its compressed size past its first
             * megabyte, a plain zip's 4 GB, and 8 GB of files once unpacked.
             */
            val standard = Limits(maxEntries = UINT16_MAX - 1, maxEntryBytes = STANDARD_ENTRY_BYTES)
        }
    }

    /**
     * What can go wrong, the iOS app's `DosarZipEngine.ZipError`, case for case. An error never
     * says a path inside the archive to the person: the path stays on it for tests and the log,
     * and the words the person reads come from the shared catalog by its kind.
     */
    sealed class ZipError : Exception() {
        data object InvalidZipArchive : ZipError()
        data object EndOfCentralDirectoryNotFound : ZipError()
        data class UnsupportedCompressionMethod(val method: Int) : ZipError()
        data class CrcMismatch(val path: String, val expected: Long, val actual: Long) : ZipError()
        data class FileCorrupted(val path: String) : ZipError()
        data class UnsafeEntryPath(val path: String) : ZipError()
        data class DuplicateEntry(val path: String) : ZipError()
        data object SizeLimitExceeded : ZipError()

        /** Its files together would take more than `maxUnpackedBytes` once unpacked. */
        data object UnpacksTooLarge : ZipError()

        /** Two files claim the same bytes of the archive, or one runs into the directory. */
        data object OverlappingEntries : ZipError()

        /** More files than one archive holds. */
        data object TooManyFilesToWrite : ZipError()

        /** More bytes than one archive holds. */
        data object TooLargeToWrite : ZipError()

        /** One file bigger than an archive may carry. */
        data class FileTooLargeToWrite(val path: String) : ZipError()

        /** A file's DEFLATE data can't be unpacked (iOS: `zlibError`, with zlib's own code). */
        data object ZlibError : ZipError()
    }

    /**
     * An entry path is accepted only if it is relative, uses `/`, and has no empty, `.` or `..`
     * components. Read by code point, it refuses at least what the iOS app, which reads by
     * character, refuses.
     */
    fun isSafeEntryPath(path: String): Boolean {
        val refused = path.isEmpty() || path.startsWith("/") || "\\" in path || "\u0000" in path || ":" in path
        if (refused) return false
        val components = path.split("/")
        val body = if (path.endsWith("/")) components.dropLast(1) else components
        return body.isNotEmpty() && body.all { it.isNotEmpty() && it != "." && it != ".." }
    }

    /**
     * A path as the iOS app compares it: Swift strings are equal when they are canonically
     * equivalent, so two names that differ only in how an accent is written are the same file.
     */
    internal fun pathKey(path: String): String = Normalizer.normalize(path, Normalizer.Form.NFC)

    // Checksums and compression

    /** IEEE 802.3 CRC-32 of [data]. */
    fun computeCRC32(data: ByteArray): Long = CRC32().apply { update(data) }.value

    /** Compresses one file with raw DEFLATE, as PKZip stores it (zlib's default level, no header). */
    fun deflateRaw(data: ByteArray): ByteArray {
        if (data.isEmpty()) return ByteArray(0)
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true)
        try {
            deflater.setInput(data)
            deflater.finish()
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(DEFLATE_BUFFER)
            while (!deflater.finished()) {
                val written = deflater.deflate(buffer)
                out.write(buffer, 0, written)
            }
            return out.toByteArray()
        } finally {
            deflater.end()
        }
    }

    /** Raw INFLATE fed a piece at a time; what comes out goes to `emit`, a piece at a time. */
    internal class Inflater : AutoCloseable {
        private val inflater = java.util.zip.Inflater(true)
        private val buffer = ByteArray(INFLATE_BUFFER)
        var finished = false
            private set

        fun feed(input: ByteArray, emit: (ByteArray) -> Unit) {
            if (input.isEmpty() || finished) return
            inflater.setInput(input)
            // Until the file's end, or until everything given is taken: more comes with the next piece.
            do {
                val written = try {
                    inflater.inflate(buffer)
                } catch (@Suppress("SwallowedException") error: DataFormatException) {
                    // zlib's own words name nothing of the archive; the kind is what matters.
                    throw ZipError.ZlibError
                }
                if (written > 0) emit(buffer.copyOf(written))
                finished = inflater.finished()
                // A preset dictionary is never part of a zip entry: zlib calls it an error too.
                ensure(finished || !inflater.needsDictionary()) { ZipError.ZlibError }
            } while (!finished && written > 0)
        }

        override fun close() = inflater.end()
    }

    // Writing

    /**
     * Writes an archive to a sink, one file at a time. Each file is checked against the limits
     * before a byte of it is written; what the writer accepts, [Reader] reads. A file is
     * compressed only when that makes it smaller and keeps it within what the reader lets a file
     * expand; otherwise it is stored as it is. Dates are written in [zone], the app's time zone ([DosarCalendar.zone]).
     */
    class Writer(
        private val sink: ArchiveByteSink,
        val limits: Limits = Limits.standard,
        private val zone: ZoneId = DosarCalendar.zone(),
    ) {
        private class Record(
            val pathBytes: ByteArray,
            val uncompressedSize: Long,
            val compressedSize: Long,
            val crc: Long,
            val compressionMethod: Int,
            val dosTime: Int,
            val dosDate: Int,
            val localHeaderOffset: Long,
        )

        private val records = mutableListOf<Record>()
        private val paths = mutableSetOf<String>()
        private var offset = 0L
        private var directoryBytes = 0L

        /** Bytes of every file written so far, as they are read back. */
        private var unpackedBytes = 0L
        private var finished = false

        /** How many files are written so far. */
        val count: Int get() = records.size

        fun add(path: String, data: ByteArray, modified: Instant) {
            check(!finished) { "An archive takes no file once finished." }
            ensure(isSafeEntryPath(path)) { ZipError.UnsafeEntryPath(path) }
            val pathBytes = path.encodeToByteArray()
            ensure(pathBytes.size <= limits.maxPathBytes) { ZipError.UnsafeEntryPath(path) }
            ensure(pathKey(path) !in paths) { ZipError.DuplicateEntry(path) }
            ensure(records.size < limits.maxEntries) { ZipError.TooManyFilesToWrite }
            ensure(data.size <= limits.maxEntryBytes) { ZipError.FileTooLargeToWrite(path) }
            // What the reader would unpack in all stays within what it unpacks.
            ensure(unpackedBytes + data.size <= limits.maxUnpackedBytes) { ZipError.TooLargeToWrite }

            val crc = computeCRC32(data)
            val compressed = deflateRaw(data)
            val useCompression = data.isNotEmpty() && compressed.size < data.size &&
                limits.admitsExpansion(stored = compressed.size.toLong(), size = data.size.toLong())
            val payload = if (useCompression) compressed else data
            val entryBytes = LOCAL_HEADER_SIZE + pathBytes.size + payload.size.toLong()
            val recordBytes = DIRECTORY_RECORD_SIZE + pathBytes.size.toLong()
            // Every offset, the directory and its end record stay inside what a plain zip describes.
            ensure(offset + entryBytes + directoryBytes + recordBytes + END_RECORD_SIZE <= limits.maxArchiveBytes) {
                ZipError.TooLargeToWrite
            }

            val (dosTime, dosDate) = dosDateTime(modified, zone)
            val record = Record(
                pathBytes = pathBytes,
                uncompressedSize = data.size.toLong(),
                compressedSize = payload.size.toLong(),
                crc = crc,
                compressionMethod = if (useCompression) METHOD_DEFLATE else METHOD_STORE,
                dosTime = dosTime,
                dosDate = dosDate,
                localHeaderOffset = offset,
            )
            sink.write(localHeader(record))
            sink.write(payload)

            offset += entryBytes
            directoryBytes += recordBytes
            unpackedBytes += data.size
            paths += pathKey(path)
            records += record
        }

        /** Writes the directory and its end record. Returns the archive's size in bytes. */
        fun finish(): Long {
            check(!finished) { "An archive is finished once." }
            finished = true
            val directory = LittleEndianWriter(directoryBytes.toInt() + END_RECORD_SIZE)
            for (record in records) directoryRecord(directory, record)
            directory.u32(END_SIGNATURE)
            directory.u16(0) // Disk number
            directory.u16(0) // Start disk
            directory.u16(records.size)
            directory.u16(records.size)
            directory.u32(directoryBytes)
            directory.u32(offset)
            directory.u16(0) // Comment length
            val bytes = directory.toByteArray()
            sink.write(bytes)
            return offset + bytes.size
        }

        private fun localHeader(record: Record): ByteArray {
            val header = LittleEndianWriter(LOCAL_HEADER_SIZE + record.pathBytes.size)
            header.u32(LOCAL_SIGNATURE)
            header.u16(VERSION_NEEDED) // Version needed: 2.0
            header.u16(UTF8_NAMES) // General purpose bit flag: UTF-8 names (bit 11)
            header.u16(record.compressionMethod)
            header.u16(record.dosTime)
            header.u16(record.dosDate)
            header.u32(record.crc)
            header.u32(record.compressedSize)
            header.u32(record.uncompressedSize)
            header.u16(record.pathBytes.size)
            header.u16(0) // Extra field length
            header.bytes(record.pathBytes)
            return header.toByteArray()
        }

        private fun directoryRecord(directory: LittleEndianWriter, record: Record) {
            directory.u32(DIRECTORY_SIGNATURE)
            directory.u16(VERSION_MADE_BY) // Version made by: UNIX (0x03), PKZip 2.0 (0x14)
            directory.u16(VERSION_NEEDED) // Version needed: 2.0
            directory.u16(UTF8_NAMES) // UTF-8 names
            directory.u16(record.compressionMethod)
            directory.u16(record.dosTime)
            directory.u16(record.dosDate)
            directory.u32(record.crc)
            directory.u32(record.compressedSize)
            directory.u32(record.uncompressedSize)
            directory.u16(record.pathBytes.size)
            directory.u16(0) // Extra field length
            directory.u16(0) // File comment length
            directory.u16(0) // Disk number start
            directory.u16(0) // Internal file attributes
            directory.u32(REGULAR_FILE_ATTRIBUTES) // External attributes: regular file rw-r--r--
            directory.u32(record.localHeaderOffset)
            directory.bytes(record.pathBytes)
        }
    }

    // Reading

    /**
     * Reads an archive's directory, then each file on request, a piece at a time. Every file is
     * checked against the limits before any of it is read. Dates are read in [zone], the app's time zone
     * ([DosarCalendar.zone]).
     */
    class Reader(
        private val source: ArchiveByteSource,
        val limits: Limits = Limits.standard,
        zone: ZoneId = DosarCalendar.zone(),
    ) {
        /** One file, as the directory describes it. */
        @ConsistentCopyVisibility
        data class Item internal constructor(
            val path: String,
            val method: Int,
            val crc: Long,
            val compressedSize: Long,
            val size: Long,
            val modified: Instant,
            internal val localHeaderOffset: Long,
            /** Where the next file's bytes (or the directory) begin: this one's never reach past it. */
            internal val spanEnd: Long,
        )

        /** The archive's files, in the directory's order (folders left out). */
        val items: List<Item>
        private val indexByPath: Map<String, Int>

        init {
            val directory = DirectoryReader(source, limits, zone)
            items = directory.items
            indexByPath = items.withIndex().associate { (index, item) -> pathKey(item.path) to index }
        }

        fun item(path: String): Item? = indexByPath[pathKey(path)]?.let { items[it] }

        /**
         * One file, whole. For the small files an archive describes itself with; its size is
         * already within `maxEntryBytes`.
         */
        fun data(item: Item): ByteArray {
            val out = ByteArrayOutputStream(item.size.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
            stream(item) { out.write(it) }
            return out.toByteArray()
        }

        /**
         * One file a piece at a time, checked against its size and CRC as it goes; a file that
         * turns out longer or shorter than it says, or changed, throws.
         */
        fun stream(item: Item, emit: (ByteArray) -> Unit) {
            val header = source.read(item.localHeaderOffset, LOCAL_HEADER_SIZE)
            ensure(header.u32(0) == LOCAL_SIGNATURE) { ZipError.InvalidZipArchive }
            val dataStart = item.localHeaderOffset + LOCAL_HEADER_SIZE +
                header.u16(LOCAL_NAME_LENGTH) + header.u16(LOCAL_EXTRA_LENGTH)
            ensure(dataStart + item.compressedSize <= source.size) { ZipError.InvalidZipArchive }
            // Its own header may say more than the directory did: still never into the next file.
            ensure(dataStart + item.compressedSize <= item.spanEnd) { ZipError.OverlappingEntries }

            val tally = Tally(item.size)
            val cursor = PieceCursor(source, dataStart, dataStart + item.compressedSize)
            val count: (ByteArray) -> Unit = { piece ->
                tally.count(piece)
                emit(piece)
            }
            when (item.method) {
                METHOD_STORE -> while (cursor.remaining > 0) count(cursor.nextPiece())
                METHOD_DEFLATE -> Inflater().use { inflater ->
                    while (cursor.remaining > 0 && !inflater.finished) inflater.feed(cursor.nextPiece(), count)
                    ensure(inflater.finished || item.size == 0L) { ZipError.FileCorrupted(item.path) }
                }
                else -> throw ZipError.UnsupportedCompressionMethod(item.method)
            }
            ensure(tally.produced == item.size) { ZipError.FileCorrupted(item.path) }
            ensure(tally.crc == item.crc) { ZipError.CrcMismatch(item.path, item.crc, tally.crc) }
        }

        /** What a file gave so far: never more than it said, and its CRC. */
        private class Tally(private val size: Long) {
            private val checksum = CRC32()
            var produced = 0L
                private set
            val crc: Long get() = checksum.value

            fun count(piece: ByteArray) {
                produced += piece.size
                ensure(produced <= size) { ZipError.SizeLimitExceeded }
                checksum.update(piece)
            }
        }
    }

    /** The directory of an archive, read and checked whole before any file is. */
    private class DirectoryReader(
        private val source: ArchiveByteSource,
        private val limits: Limits,
        private val zone: ZoneId,
    ) {
        /** Each file as the directory describes it, before its place is checked. */
        private class Listed(
            val path: String,
            val method: Int,
            val crc: Long,
            val compressedSize: Long,
            val size: Long,
            val modified: Instant,
            val localHeaderOffset: Long,
            /** The least the file takes: its header, its name and its data. */
            val leastEnd: Long,
            val isFolder: Boolean,
        )

        private val seen = mutableSetOf<String>()
        private var unpacked = 0L
        val items: List<Reader.Item>

        init {
            val size = source.size
            ensure(size >= END_RECORD_SIZE) { ZipError.InvalidZipArchive }
            ensure(size <= limits.maxArchiveBytes) { ZipError.SizeLimitExceeded }

            // The end of central directory record, searched backwards over its longest comment.
            val tailStart = maxOf(0L, size - END_RECORD_SIZE - MAX_COMMENT)
            val tail = source.read(tailStart, (size - tailStart).toInt())
            val eocd = (tail.size - END_RECORD_SIZE downTo 0).firstOrNull { tail.u32(it) == END_SIGNATURE }
                ?: throw ZipError.EndOfCentralDirectoryNotFound

            // A zip64 archive marks its counts and offsets with all ones; no writer here makes one.
            val totalEntries = tail.u16(eocd + END_TOTAL_ENTRIES)
            val directorySize = tail.u32(eocd + END_DIRECTORY_SIZE)
            val directoryOffset = tail.u32(eocd + END_DIRECTORY_OFFSET)
            val zip64 = totalEntries == UINT16_MAX || directorySize == UINT32_MAX || directoryOffset == UINT32_MAX
            ensure(!zip64) { ZipError.SizeLimitExceeded }
            ensure(directoryOffset + directorySize <= tailStart + eocd) { ZipError.InvalidZipArchive }
            ensure(totalEntries <= limits.maxEntries) { ZipError.SizeLimitExceeded }

            val cursor = PieceCursor(source, directoryOffset, directoryOffset + directorySize)
            val listed = List(totalEntries) { listing(cursor, directoryOffset) }
            items = placed(listed, directoryOffset)
        }

        private fun listing(cursor: PieceCursor, directoryOffset: Long): Listed {
            val fixed = cursor.take(DIRECTORY_RECORD_SIZE)
            ensure(fixed.u32(0) == DIRECTORY_SIGNATURE) { ZipError.InvalidZipArchive }
            val method = fixed.u16(RECORD_METHOD)
            val compressedSize = fixed.u32(RECORD_COMPRESSED_SIZE)
            val uncompressedSize = fixed.u32(RECORD_SIZE)
            val nameLength = fixed.u16(RECORD_NAME_LENGTH)
            val localHeaderOffset = fixed.u32(RECORD_LOCAL_HEADER_OFFSET)
            ensure(nameLength <= limits.maxPathBytes) { ZipError.SizeLimitExceeded }
            val nameData = cursor.take(nameLength)
            cursor.skip(fixed.u16(RECORD_EXTRA_LENGTH).toLong() + fixed.u16(RECORD_COMMENT_LENGTH))
            // Not UTF-8: read with replacement characters, as the iOS app does.
            val path = nameData.decodeToString()
            ensure(isSafeEntryPath(path)) { ZipError.UnsafeEntryPath(path) }
            ensure(localHeaderOffset < directoryOffset) { ZipError.InvalidZipArchive }
            val isFolder = path.endsWith("/")
            if (!isFolder) {
                ensure(seen.add(pathKey(path))) { ZipError.DuplicateEntry(path) }
                ensure(uncompressedSize <= limits.maxEntryBytes) { ZipError.SizeLimitExceeded }
                if (method == METHOD_STORE) {
                    ensure(compressedSize == uncompressedSize) { ZipError.FileCorrupted(path) }
                } else {
                    ensure(limits.admitsExpansion(compressedSize, uncompressedSize)) { ZipError.SizeLimitExceeded }
                }
                unpacked += uncompressedSize
                ensure(unpacked <= limits.maxUnpackedBytes) { ZipError.UnpacksTooLarge }
            }
            return Listed(
                path = path,
                method = method,
                crc = fixed.u32(RECORD_CRC),
                compressedSize = compressedSize,
                size = uncompressedSize,
                modified = date(fixed.u16(RECORD_TIME), fixed.u16(RECORD_DATE), zone),
                localHeaderOffset = localHeaderOffset,
                leastEnd = localHeaderOffset + LOCAL_HEADER_SIZE + nameLength + compressedSize,
                isFolder = isFolder,
            )
        }

        /**
         * Every file, folders too, keeps to its own bytes: in the order they lie in the archive,
         * each begins where the one before it has ended, and the last ends before the directory. A
         * file's bytes are read only up to where the next one begins.
         */
        private fun placed(listed: List<Listed>, directoryOffset: Long): List<Reader.Item> {
            val byPlace = listed.indices.sortedBy { listed[it].localHeaderOffset }
            val spanEnds = LongArray(listed.size) { directoryOffset }
            for ((position, current) in byPlace.withIndex()) {
                val next = byPlace.getOrNull(position + 1)
                val end = if (next != null) listed[next].localHeaderOffset else directoryOffset
                ensure(listed[current].leastEnd <= end) { ZipError.OverlappingEntries }
                spanEnds[current] = end
            }
            return listed.withIndex().filter { !it.value.isFolder }.map { (position, entry) ->
                Reader.Item(
                    path = entry.path,
                    method = entry.method,
                    crc = entry.crc,
                    compressedSize = entry.compressedSize,
                    size = entry.size,
                    modified = entry.modified,
                    localHeaderOffset = entry.localHeaderOffset,
                    spanEnd = spanEnds[position],
                )
            }
        }
    }

    /** Reads a range of a source in order, holding at most one piece of it. */
    internal class PieceCursor(private val source: ArchiveByteSource, start: Long, private val end: Long) {
        private var position = start
        private var window = ByteArray(0)
        private var windowStart = start

        val remaining: Long get() = end - position

        fun take(count: Int): ByteArray {
            ensure(count >= 0 && count <= remaining) { ZipError.InvalidZipArchive }
            if (position + count > windowStart + window.size) {
                // A new window from here: at least a piece, or the whole request when it is longer.
                windowStart = position
                window = source.read(position, minOf(maxOf(count, PIECE_SIZE).toLong(), remaining).toInt())
            }
            val from = (position - windowStart).toInt()
            position += count
            return window.copyOfRange(from, from + count)
        }

        /** The next piece of the range, or what is left of it. */
        fun nextPiece(): ByteArray = take(minOf(PIECE_SIZE.toLong(), remaining).toInt())

        fun skip(count: Long) {
            ensure(count >= 0 && count <= remaining) { ZipError.InvalidZipArchive }
            position += count
        }
    }

    // Dates

    /**
     * A moment as a zip's date and time, in [zone]. A zip date runs from 1980 to 2107. The
     * manifest keeps the real export time, so a date outside that range is written as its
     * nearest end.
     */
    internal fun dosDateTime(moment: Instant, zone: ZoneId): Pair<Int, Int> {
        val local = moment.atZone(zone)
        return when {
            local.year < FIRST_DOS_YEAR -> 0 to ((1 shl DOS_MONTH_SHIFT) or 1)
            local.year > LAST_DOS_YEAR -> LAST_DOS_TIME to LAST_DOS_DATE
            else -> {
                val time = (local.hour shl DOS_HOUR_SHIFT) or (local.minute shl DOS_MINUTE_SHIFT) or (local.second / 2)
                val date = ((local.year - FIRST_DOS_YEAR) shl DOS_YEAR_SHIFT) or
                    (local.monthValue shl DOS_MONTH_SHIFT) or local.dayOfMonth
                time to date
            }
        }
    }

    /** A zip's date and time as a moment in [zone]; days and hours past their end run on, as on iOS. */
    internal fun date(time: Int, date: Int, zone: ZoneId): Instant {
        val year = FIRST_DOS_YEAR + ((date shr DOS_YEAR_SHIFT) and DOS_YEAR_MASK)
        val month = ((date shr DOS_MONTH_SHIFT) and DOS_MONTH_MASK).coerceIn(1, MONTHS)
        val day = (date and DOS_DAY_MASK).coerceIn(1, LONGEST_MONTH)
        val local = LocalDate.of(year, month, 1).atStartOfDay()
            .plusDays(day - 1L)
            .plusHours(((time shr DOS_HOUR_SHIFT) and DOS_HOUR_MASK).toLong())
            .plusMinutes(((time shr DOS_MINUTE_SHIFT) and DOS_MINUTE_MASK).toLong())
            .plusSeconds((time and DOS_SECONDS_MASK) * 2L)
        return ZonedDateTime.of(local, zone).toInstant()
    }

    // The layout (PKWARE's APPNOTE.TXT, sections 4.3.7, 4.3.12 and 4.3.16).

    internal const val UINT16_MAX = 0xFFFF
    internal const val UINT32_MAX = 0xFFFF_FFFFL
    internal const val LOCAL_SIGNATURE = 0x04034b50L
    internal const val DIRECTORY_SIGNATURE = 0x02014b50L
    internal const val END_SIGNATURE = 0x06054b50L
    internal const val LOCAL_HEADER_SIZE = 30
    internal const val DIRECTORY_RECORD_SIZE = 46
    internal const val END_RECORD_SIZE = 22
    private const val MAX_COMMENT = 0xFFFF
    internal const val METHOD_STORE = 0
    internal const val METHOD_DEFLATE = 8
    private const val VERSION_NEEDED = 20
    private const val VERSION_MADE_BY = 0x0314
    private const val UTF8_NAMES = 0x0800
    private const val REGULAR_FILE_ATTRIBUTES = 0x81A4_0000L // 0o100644 << 16

    private const val LOCAL_NAME_LENGTH = 26
    private const val LOCAL_EXTRA_LENGTH = 28
    private const val RECORD_METHOD = 10
    private const val RECORD_TIME = 12
    private const val RECORD_DATE = 14
    private const val RECORD_CRC = 16
    private const val RECORD_COMPRESSED_SIZE = 20
    private const val RECORD_SIZE = 24
    private const val RECORD_NAME_LENGTH = 28
    private const val RECORD_EXTRA_LENGTH = 30
    private const val RECORD_COMMENT_LENGTH = 32
    private const val RECORD_LOCAL_HEADER_OFFSET = 42
    private const val END_TOTAL_ENTRIES = 10
    private const val END_DIRECTORY_SIZE = 12
    private const val END_DIRECTORY_OFFSET = 16

    private const val MEBIBYTE = 1L shl 20
    private const val STANDARD_ENTRY_BYTES = 128 * MEBIBYTE
    private const val STANDARD_UNPACKED_BYTES = 8L shl 30

    /** How much of a file is read at once. */
    internal const val PIECE_SIZE = 1 shl 20
    private const val DEFLATE_BUFFER = 1 shl 16
    private const val INFLATE_BUFFER = 1 shl 18

    private const val FIRST_DOS_YEAR = 1980
    private const val LAST_DOS_YEAR = 2107
    private const val DOS_YEAR_SHIFT = 9
    private const val DOS_MONTH_SHIFT = 5
    private const val DOS_HOUR_SHIFT = 11
    private const val DOS_MINUTE_SHIFT = 5
    private const val DOS_YEAR_MASK = 0x7F
    private const val DOS_MONTH_MASK = 0x0F
    private const val DOS_DAY_MASK = 0x1F
    private const val DOS_HOUR_MASK = 0x1F
    private const val DOS_MINUTE_MASK = 0x3F
    private const val DOS_SECONDS_MASK = 0x1F
    private const val MONTHS = 12
    private const val LONGEST_MONTH = 31

    /** 23:59:58, the last time a zip holds. */
    private const val LAST_DOS_TIME = (23 shl DOS_HOUR_SHIFT) or (59 shl DOS_MINUTE_SHIFT) or 29

    /** 31 December 2107, the last day a zip holds. */
    private const val LAST_DOS_DATE =
        ((LAST_DOS_YEAR - FIRST_DOS_YEAR) shl DOS_YEAR_SHIFT) or (MONTHS shl DOS_MONTH_SHIFT) or LONGEST_MONTH
}

/** Little-endian bytes appended one field after another. */
internal class LittleEndianWriter(capacity: Int) {
    private val out = ByteArrayOutputStream(capacity)

    fun u16(value: Int) {
        out.write(value and BYTE)
        out.write((value shr BYTE_BITS) and BYTE)
    }

    fun u32(value: Long) {
        for (shift in 0 until U32_BITS step BYTE_BITS) out.write(((value shr shift) and BYTE.toLong()).toInt())
    }

    fun bytes(value: ByteArray) = out.write(value)

    fun toByteArray(): ByteArray = out.toByteArray()
}

/** A little-endian 16-bit field at [offset]. */
internal fun ByteArray.u16(offset: Int): Int =
    (this[offset].toInt() and BYTE) or ((this[offset + 1].toInt() and BYTE) shl BYTE_BITS)

/** A little-endian 32-bit field at [offset], as a non-negative number. */
internal fun ByteArray.u32(offset: Int): Long =
    (0 until Int.SIZE_BYTES).fold(0L) { value, byte ->
        value or ((this[offset + byte].toLong() and BYTE.toLong()) shl (byte * BYTE_BITS))
    }

private const val BYTE = 0xFF
private const val BYTE_BITS = 8
private const val U32_BITS = 32
