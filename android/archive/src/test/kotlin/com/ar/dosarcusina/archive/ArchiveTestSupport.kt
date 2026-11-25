package com.ar.dosarcusina.archive

import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.util.HexFormat

// Small archives built and taken apart in memory, for tests only, as the iOS tests'
// Support/ArchiveInMemory.swift: through the same writer, reader and sealer, with the bytes in
// memory.

/** Bytes kept in memory, read at any place. */
class MemoryByteSource(private val data: ByteArray) : ArchiveByteSource {
    override val size: Long get() = data.size.toLong()

    override fun read(offset: Long, count: Int): ByteArray {
        if (offset < 0 || count < 0 || count > size - offset) throw DosarZipEngine.ZipError.InvalidZipArchive
        return data.copyOfRange(offset.toInt(), offset.toInt() + count)
    }
}

/** Bytes written, kept in memory. */
class MemoryByteSink : ArchiveByteSink {
    private val out = java.io.ByteArrayOutputStream()

    /** The largest piece written at once. */
    var largestWrite = 0
        private set

    val data: ByteArray get() = out.toByteArray()

    override fun write(data: ByteArray) {
        largestWrite = maxOf(largestWrite, data.size)
        out.write(data)
    }
}

/** One file of a hand-made archive. */
data class Entry(val path: String, val data: ByteArray, val modified: Instant = Instant.parse("2026-11-25T10:00:00Z")) {
    override fun equals(other: Any?): Boolean =
        other is Entry && other.path == path && other.data.contentEquals(data) && other.modified == modified

    override fun hashCode(): Int = path.hashCode()
}

val testZone: ZoneOffset = ZoneOffset.UTC

fun createArchive(entries: List<Entry>, limits: DosarZipEngine.Limits = DosarZipEngine.Limits.standard): ByteArray {
    val sink = MemoryByteSink()
    val writer = DosarZipEngine.Writer(sink, limits, testZone)
    for (entry in entries) writer.add(entry.path, entry.data, entry.modified)
    writer.finish()
    return sink.data
}

fun unpackArchive(data: ByteArray, limits: DosarZipEngine.Limits = DosarZipEngine.Limits.standard): List<Entry> {
    val reader = DosarZipEngine.Reader(MemoryByteSource(data), limits, testZone)
    return reader.items.map { Entry(it.path, reader.data(it), it.modified) }
}

fun encrypt(
    plain: ByteArray,
    password: String,
    iterations: Long = ArchiveEncryption.DEFAULT_ITERATIONS,
    chunkSize: Int = ArchiveEncryption.DEFAULT_CHUNK_SIZE,
): ByteArray {
    val sink = MemoryByteSink()
    val sealed = ArchiveEncryption.EncryptingSink(sink, password, iterations, chunkSize)
    sealed.write(plain)
    sealed.finish()
    return sink.data
}

fun decrypt(data: ByteArray, password: String): ByteArray {
    val source = ArchiveEncryption.DecryptingSource(MemoryByteSource(data), password)
    return source.read(0, source.size.toInt())
}

fun sha256(data: ByteArray): String =
    HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data))

fun ByteArray.indexOf(pattern: ByteArray, from: Int = 0): Int =
    (from..size - pattern.size).firstOrNull { start -> pattern.indices.all { this[start + it] == pattern[it] } } ?: -1

/** The kind of a zip error, as the iOS app names its case (`overlappingEntries`). */
val DosarZipEngine.ZipError.kind: String
    get() = this::class.simpleName.orEmpty().replaceFirstChar { it.lowercaseChar() }

/** Whether reading [data] whole, every file to its end, is refused, and with which kind. */
fun refusal(data: ByteArray): String? = try {
    val reader = DosarZipEngine.Reader(MemoryByteSource(data), zone = testZone)
    for (item in reader.items) reader.stream(item) {}
    null
} catch (error: DosarZipEngine.ZipError) {
    error.kind
}

/** [size] bytes that don't compress, the same every time: the SHA-256 of "0", of "1", … one after another. */
fun noise(size: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream(size + 32)
    var block = 0
    while (out.size() < size) out.write(MessageDigest.getInstance("SHA-256").digest("${block++}".encodeToByteArray()))
    return out.toByteArray().copyOf(size)
}
