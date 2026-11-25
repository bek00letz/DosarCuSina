package com.ar.dosarcusina.archive

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/**
 * Each app reads the other's bytes: the iOS-made archives in shared/test-vectors/archive open
 * here with what they hold, the Android-made ones beside them still open (the iOS tests open
 * them too), and both apps refuse the same crafted archives with the same kind of error.
 *
 * `./gradlew :archive:test -PwriteArchiveVectors` writes the Android-made files, the listing and
 * the refused cases again; commit them, then run the iOS tests' ArchiveVectorsTests.
 */
class ArchiveVectorsTest {
    private val directory = ArchiveVectors.directory

    @Test
    fun `the listing is what the entries are`() {
        if (ArchiveVectors.writes) ArchiveVectors.contents.writeText(ArchiveVectors.listing())
        assertEquals(ArchiveVectors.listing(), committed(ArchiveVectors.contents).readText())
    }

    @Test
    fun `the archives the iOS app made open with everything in them`() {
        ArchiveFileSource(committed(directory.resolve("ios-plain.zip"))).use { assertHoldsTheVector(it) }
        assertProtectedVector(committed(directory.resolve("ios-password.dosar")))
    }

    @Test
    fun `the archives this app made still open with everything in them`() {
        val plain = directory.resolve("android-plain.zip")
        val protected = directory.resolve("android-password.dosar")
        if (ArchiveVectors.writes) {
            write(plain) { it }
            write(protected) { file -> ArchiveEncryption.EncryptingSink(file, ArchiveVectors.PASSWORD) }
        }
        ArchiveFileSource(committed(plain)).use { assertHoldsTheVector(it) }
        assertProtectedVector(committed(protected))
    }

    @Test
    fun `both apps refuse the same archives with the same kind of error`() {
        val cases = RefusedArchives.all()
        if (ArchiveVectors.writes) {
            val folder = directory.resolve("refused").apply { mkdirs() }
            folder.listFiles()?.forEach { it.delete() }
            for (case in cases) folder.resolve(case.file).writeBytes(case.bytes)
            ArchiveVectors.refused.writeText(
                "file\tkind\twhat it is\n" + cases.joinToString("") { "${it.file}\t${it.kind}\t${it.behaviour}\n" },
            )
        }
        val listed = committed(ArchiveVectors.refused).readLines().drop(1)
            .filter { it.isNotBlank() }
            .map { it.split("\t") }
        val made = cases.map { listOf(it.file, it.kind, it.behaviour) }
        assertEquals(made, listed, "refused.tsv is the cases this test makes")
        for ((file, kind) in listed) {
            val bytes = committed(directory.resolve("refused/$file")).readBytes()
            assertEquals(kind, refusal(bytes), file)
        }
    }

    // What every vector holds

    private fun assertHoldsTheVector(source: ArchiveByteSource) {
        val reader = DosarZipEngine.Reader(source)
        val expected = ArchiveVectors.listing().lines().filter { it.isNotEmpty() }.map { it.split("  ", limit = 2) }
        assertEquals(expected.map { it[1] }, reader.items.map { it.path }, "Every file, in order, the folder left out")
        for ((hash, path) in expected) {
            val item = requireNotNull(reader.item(path))
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            reader.stream(item) { digest.update(it) }
            assertEquals(hash, java.util.HexFormat.of().formatHex(digest.digest()), path)
        }
        assertEquals(DosarZipEngine.METHOD_DEFLATE, reader.item("text/repeated.txt")?.method, "A compressed file")
        assertEquals(DosarZipEngine.METHOD_STORE, reader.item("vault/pagini.bin")?.method, "A stored file")
    }

    /**
     * A protected vector opens with its password (written in either form), holds the vector, is
     * written as the app writes one, and refuses every change the iOS tests try.
     */
    private fun assertProtectedVector(file: File) {
        val sealed = file.readBytes()
        assertEquals("DOSARENC", sealed.copyOf(8).decodeToString())
        assertEquals(ArchiveEncryption.DEFAULT_ITERATIONS, sealed.bigEndian(10), "The rounds the app writes")
        val chunk = ArchiveEncryption.DEFAULT_CHUNK_SIZE
        assertEquals(chunk.toLong(), sealed.bigEndian(30), "The chunk size the app writes")
        val oneChunk = ArchiveEncryption.HEADER_SIZE + chunk + ArchiveEncryption.TAG_SIZE
        assertTrue(sealed.size > oneChunk, "More than one chunk")

        ArchiveFileSource(file).use { source ->
            ArchiveOpening.opened(source, ArchiveVectors.PASSWORD) { assertHoldsTheVector(it) }
            // The same password typed with its letter in two characters.
            ArchiveOpening.opened(source, "parolă-exemplu") { DosarZipEngine.Reader(it) }
            fun opening(password: String?) = assertThrows<ArchiveError> { ArchiveOpening.opened(source, password) {} }
            assertEquals(ArchiveError.NeedsPassword, opening(null))
            assertEquals(ArchiveError.NoPasswordTyped, opening(""))
            assertEquals(ArchiveError.WrongPassword, opening("alta-parola"))
        }
        fun refusedAs(changed: ByteArray): ArchiveError = assertThrows<ArchiveError> {
            ArchiveOpening.opened(MemoryByteSource(changed), ArchiveVectors.PASSWORD) { plain ->
                val reader = DosarZipEngine.Reader(plain)
                reader.items.forEach { item -> reader.stream(item) {} }
            }
        }
        val inFirstChunk = ArchiveEncryption.HEADER_SIZE + 10
        val firstChunk = sealed.copyOf().also { it[inFirstChunk] = (it[inFirstChunk].toInt() xor 1).toByte() }
        assertEquals(ArchiveError.WrongPassword, refusedAs(firstChunk), "A byte of the first chunk changed")
        val cut = sealed.copyOf(ArchiveEncryption.HEADER_SIZE + chunk + ArchiveEncryption.TAG_SIZE)
        assertEquals(ArchiveError.WrongPassword, refusedAs(cut), "Cut after its first chunk")
        val noRounds = sealed.copyOf().also { it.fill(0, 10, 14) }
        assertEquals(ArchiveError.NotADossier, refusedAs(noRounds), "A header that asks for no rounds")
        val newerVersion = sealed.copyOf().also { it[8] = 2 }
        assertEquals(ArchiveError.NotADossier, refusedAs(newerVersion), "A version this app doesn't know")
    }

    private fun write(file: File, sealing: (ArchiveByteSink) -> ArchiveByteSink) {
        file.delete()
        ArchiveFileSink(file).use { fileSink ->
            val sink = sealing(fileSink)
            val writer = DosarZipEngine.Writer(sink)
            for (entry in ArchiveVectors.entries()) writer.add(entry.path, entry.data, entry.modified)
            writer.finish()
            (sink as? ArchiveEncryption.EncryptingSink)?.finish()
        }
    }

    private fun committed(file: File): File {
        if (!file.isFile) {
            fail<Unit>("${file.name} isn't in shared/test-vectors/archive. Its README says how each file is made.")
        }
        return file
    }

    private fun ByteArray.bigEndian(at: Int): Long =
        (0 until 4).fold(0L) { value, i -> (value shl 8) or (this[at + i].toLong() and 0xFF) }
}
