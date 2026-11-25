package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.DosarZipEngine.Limits
import com.ar.dosarcusina.archive.DosarZipEngine.ZipError
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

// The iOS app's ZipEngineTests, ZipLimitTests and the archive cases of ValuesFromOutsideTests,
// case for case, and what streaming means here.
class DosarZipEngineTest {
    @Test
    fun `round-trips stored and compressed entries`() {
        val entries = listOf(
            Entry("manifest.json", "{\"a\":1}".repeat(500).encodeToByteArray()),
            Entry("vault/photo.jpg", noise(4_096)),
        )
        val archive = createArchive(entries)
        assertEquals(entries, unpackArchive(archive))
        val reader = DosarZipEngine.Reader(MemoryByteSource(archive))
        assertEquals(listOf(DosarZipEngine.METHOD_DEFLATE, DosarZipEngine.METHOD_STORE), reader.items.map { it.method })
    }

    @ParameterizedTest
    @ValueSource(strings = ["../x", "a/../../x", "/abs", "a\\b", "C:/x", "a//b", "./a", "", "a\u0000b"])
    fun `entry paths must stay inside the archive`(path: String) {
        assertFalse(DosarZipEngine.isSafeEntryPath(path))
        assertThrows<ZipError.UnsafeEntryPath> { createArchive(listOf(Entry(path, ByteArray(0)))) }
    }

    @Test
    fun `accepts normal paths`() {
        for (path in listOf("manifest.json", "data/assets.json", "vault/photos/a.jpg", "vault/")) {
            assertTrue(DosarZipEngine.isSafeEntryPath(path), path)
        }
    }

    @Test
    fun `a name longer than a file's name may be is refused`() {
        assertThrows<ZipError.UnsafeEntryPath> { createArchive(listOf(Entry("a".repeat(1_025), ByteArray(0)))) }
        assertEquals(1, unpackArchive(createArchive(listOf(Entry("a".repeat(1_024), ByteArray(0))))).size)
    }

    @Test
    fun `enforces size limits`() {
        val archive = createArchive(listOf(Entry("a.bin", ByteArray(10_000)), Entry("b.bin", ByteArray(10_000))))
        val tight = Limits(maxEntries = 10, maxEntryBytes = 5_000)
        assertThrows<ZipError.SizeLimitExceeded> { unpackArchive(archive, tight) }
        val few = Limits(maxEntries = 1, maxEntryBytes = 20_000)
        assertThrows<ZipError.SizeLimitExceeded> { unpackArchive(archive, few) }
        // Ten thousand zeros compress to a few bytes: past the allowance, that is too much growth.
        val wary = Limits(maxEntries = 10, maxEntryBytes = 20_000, maxExpansion = 10, expansionAllowance = 1_000)
        assertThrows<ZipError.SizeLimitExceeded> { unpackArchive(archive, wary) }
        // The writer reads the same limits: it stores such a file as it is, and the reader takes it.
        val stored = createArchive(listOf(Entry("a.bin", ByteArray(10_000))), wary)
        assertArrayEquals(ByteArray(10_000), unpackArchive(stored, wary).single().data)
    }

    @Test
    fun `a large binder fits every limit`() {
        val limits = Limits.standard
        assertEquals(8L shl 30, limits.maxUnpackedBytes)
        assertEquals(65_534, limits.maxEntries, "As many files as a plain zip counts")
        assertEquals(128L shl 20, limits.maxEntryBytes)
        assertEquals(1_024, limits.maxPathBytes)
        assertTrue(limits.admitsExpansion(stored = 120L shl 10, size = 120L shl 10), "A photo stored as it is")
        assertTrue(limits.admitsExpansion(stored = 1, size = 1L shl 20), "A small file may grow any amount")
        assertTrue(
            limits.admitsExpansion(stored = 1L shl 20, size = 200L shl 20),
            "Up to two hundred times past the first megabyte",
        )
        assertFalse(limits.admitsExpansion(stored = 1L shl 20, size = (200L shl 20) + 200))
        assertEquals(0xFFFF_FFFFL - 1, limits.maxArchiveBytes, "A plain zip's 4 GB")
        assertTrue(limits.maxUnpackedBytes >= 2 * limits.maxArchiveBytes)
    }

    @Test
    fun `a writer refuses what its reader would refuse`() {
        // One stored file of 100 bytes takes 135 bytes, its directory record 51, the end 22.
        val limits = Limits(maxEntries = 2, maxEntryBytes = 100, maxArchiveBytes = 300)
        val writer = DosarZipEngine.Writer(MemoryByteSink(), limits)
        val tooLarge = assertThrows<ZipError> { writer.add("big.bin", ByteArray(101) { 1 }, Instant.now()) }
        assertEquals(ZipError.FileTooLargeToWrite("big.bin"), tooLarge)
        writer.add("a.bin", ByteArray(100) { it.toByte() }, Instant.now())
        assertThrows<ZipError.TooLargeToWrite> {
            writer.add("b.bin", ByteArray(100) { (it + 100).toByte() }, Instant.now())
        }
        assertEquals(1, writer.count, "Nothing of a refused file is written")
    }

    @Test
    fun `detects damaged data`() {
        val archive = createArchive(listOf(Entry("a.txt", ByteArray(64) { 65 })))
        // Flip a byte inside the payload (after the 30-byte local header and the name).
        archive[30 + 5 + 2] = (archive[30 + 5 + 2].toInt() xor 0xFF).toByte()
        assertThrows<ZipError> { unpackArchive(archive) }
        assertThrows<ZipError.InvalidZipArchive> { unpackArchive(ByteArray(10)) }
    }

    @Test
    fun `refuses more files than a zip can describe`() {
        val entries = (0..0xFFFF).map { Entry("f$it", ByteArray(0)) }
        assertThrows<ZipError.TooManyFilesToWrite> { createArchive(entries) }
    }

    @Test
    fun `as many files as a writer takes are read back`() {
        // 65 535 files would mark a ZIP64 archive, which a reader refuses: the writer stops one before.
        val most = Limits.standard.maxEntries
        val entries = (0 until most).map { Entry("f$it", ByteArray(0)) }
        val zip = createArchive(entries)
        assertEquals(most, DosarZipEngine.Reader(MemoryByteSource(zip)).items.size)
        assertThrows<ZipError.TooManyFilesToWrite> { createArchive(entries + Entry("one-more", ByteArray(0))) }
    }

    @Test
    fun `dates outside what a zip can hold are written at its ends`() {
        val bucharest = ZoneId.of("Europe/Bucharest")
        val far = ZonedDateTime.of(2200, 5, 1, 0, 0, 0, 0, bucharest).toInstant()
        val early = ZonedDateTime.of(1970, 1, 1, 0, 0, 0, 0, bucharest).toInstant()
        val sink = MemoryByteSink()
        val writer = DosarZipEngine.Writer(sink, zone = bucharest)
        writer.add("far.txt", "a".encodeToByteArray(), far)
        writer.add("early.txt", "b".encodeToByteArray(), early)
        writer.finish()
        val years = DosarZipEngine.Reader(MemoryByteSource(sink.data), zone = bucharest).items
            .associate { it.path to it.modified.atZone(bucharest).year }
        assertEquals(mapOf("far.txt" to 2107, "early.txt" to 1980), years)
    }

    @Test
    fun `a date comes back to the two seconds, in the zone it was written in`() {
        val zone = ZoneId.of("Europe/Bucharest")
        val moment = Instant.parse("2026-11-25T10:41:37Z")
        val (time, date) = DosarZipEngine.dosDateTime(moment, zone)
        assertEquals(Instant.parse("2026-11-25T10:41:36Z"), DosarZipEngine.date(time, date, zone))
    }

    @Test
    fun `an archive whose files together unpack past the limit is refused before any is read, both ways`() {
        val archive = createArchive(listOf(Entry("a.bin", ByteArray(10_000)), Entry("b.bin", ByteArray(10_000))))
        val limits = Limits(maxEntries = 10, maxEntryBytes = 20_000, maxUnpackedBytes = 15_000)
        val source = CountingSource(MemoryByteSource(archive))
        assertThrows<ZipError.UnpacksTooLarge> { DosarZipEngine.Reader(source, limits) }
        // The writer refuses what its reader would.
        val writer = DosarZipEngine.Writer(MemoryByteSink(), limits)
        writer.add("a.bin", ByteArray(10_000), Instant.now())
        assertThrows<ZipError.TooLargeToWrite> { writer.add("b.bin", ByteArray(10_000), Instant.now()) }
    }

    @Test
    fun `an archive whose files claim the same bytes is refused`() {
        val archive = createArchive(listOf(Entry("a.bin", ByteArray(100) { 1 }), Entry("b.bin", ByteArray(100) { 2 })))
        assertEquals(2, unpackArchive(archive).size)
        // The second file's directory record says it starts where the first does.
        val signature = byteArrayOf(0x50, 0x4b, 0x01, 0x02)
        val first = archive.indexOf(signature)
        val second = archive.indexOf(signature, first + 1)
        for (i in 42 until 46) archive[second + i] = 0
        assertThrows<ZipError.OverlappingEntries> { unpackArchive(archive) }
    }

    @Test
    fun `two names that differ only in how an accent is written are one file, as on iOS`() {
        val composed = "acte/\u0219.txt"
        val decomposed = "acte/s\u0326.txt"
        assertThrows<ZipError.DuplicateEntry> {
            createArchive(listOf(Entry(composed, ByteArray(1)), Entry(decomposed, ByteArray(1))))
        }
        val reader = DosarZipEngine.Reader(MemoryByteSource(createArchive(listOf(Entry(decomposed, ByteArray(1))))))
        assertEquals(decomposed, reader.item(composed)?.path, "Found by either spelling")
    }

    @Test
    fun `a file is read a piece at a time, and never more of the archive at once than a piece`() {
        val stored = noise(3 shl 20)
        // Text that compresses, but not past what a file may grow: it stays compressed.
        val text = (0 until 300_000).joinToString("\n") { "Rândul $it din dosar" }.encodeToByteArray()
        val archive = createArchive(listOf(Entry("vault/pages.bin", stored), Entry("data/text.json", text)))
        val source = CountingSource(MemoryByteSource(archive))
        val reader = DosarZipEngine.Reader(source)
        for (item in reader.items) {
            val pieces = mutableListOf<Int>()
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            reader.stream(item) {
                pieces += it.size
                digest.update(it)
            }
            assertTrue(pieces.size > 1, "${item.path} came in pieces")
            assertTrue(pieces.all { it <= DosarZipEngine.PIECE_SIZE }, "${item.path}: no piece is larger than a piece")
            val expected = if (item.path == "vault/pages.bin") stored else text
            assertArrayEquals(java.security.MessageDigest.getInstance("SHA-256").digest(expected), digest.digest())
        }
        assertEquals(listOf(DosarZipEngine.METHOD_STORE, DosarZipEngine.METHOD_DEFLATE), reader.items.map { it.method })
        val inPieces = source.reads.all { (_, count) -> count <= DosarZipEngine.PIECE_SIZE }
        assertTrue(inPieces, "The archive is read a piece at a time")
    }

    @Test
    fun `a file that unpacks to more than it says is refused as it is read`() {
        val text = "Dosar cu Șină. ".repeat(1_000).encodeToByteArray()
        val archive = createArchive(listOf(Entry("a.txt", text)))
        // The directory says the file is one byte shorter than it unpacks to.
        val record = archive.indexOf(byteArrayOf(0x50, 0x4b, 0x01, 0x02))
        val size = archive.u32(record + 24) - 1
        for (i in 0 until 4) archive[record + 24 + i] = (size shr (8 * i)).toByte()
        val reader = DosarZipEngine.Reader(MemoryByteSource(archive))
        assertThrows<ZipError.SizeLimitExceeded> { reader.data(reader.items.single()) }
    }

    @Test
    fun `java's own zip reader reads what this writes, and this reads what java's writer makes`() {
        val entries = listOf(
            Entry("data/assets.json", "[{\"name\":\"VW Golf 2018\"}]".repeat(50).encodeToByteArray()),
            Entry("vault/a.bin", ByteArray(5_000) { (it % 253).toByte() }),
            Entry("acte/\u00eensemnare.txt", ByteArray(0)),
        )
        val read = mutableListOf<Pair<String, ByteArray>>()
        ZipInputStream(ByteArrayInputStream(createArchive(entries))).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                read += entry.name to zip.readBytes()
            }
        }
        assertEquals(entries.map { it.path }, read.map { it.first })
        entries.zip(read).forEach { (entry, back) -> assertArrayEquals(entry.data, back.second) }

        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            for (entry in entries) {
                zip.putNextEntry(ZipEntry(entry.path))
                zip.write(entry.data)
                zip.closeEntry()
            }
        }
        val unpacked = unpackArchive(out.toByteArray())
        assertEquals(entries.map { it.path to sha256(it.data) }, unpacked.map { it.path to sha256(it.data) })
    }

    /** A source that remembers every read: where, and how much. */
    private class CountingSource(private val inner: ArchiveByteSource) : ArchiveByteSource {
        val reads = mutableListOf<Pair<Long, Int>>()
        override val size: Long get() = inner.size

        override fun read(offset: Long, count: Int): ByteArray {
            reads += offset to count
            return inner.read(offset, count)
        }
    }
}
