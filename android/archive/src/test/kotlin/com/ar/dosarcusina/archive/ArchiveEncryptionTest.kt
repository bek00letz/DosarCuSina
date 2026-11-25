package com.ar.dosarcusina.archive

import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.util.HexFormat
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

// The iOS app's ArchiveEncryptionTests ("Password-protected backups"), the protected cases of
// ValuesFromOutsideTests and the opening rule of DossierArchiveReader, case for case.
class ArchiveEncryptionTest {
    private val plain = ByteArray(5_000) { (it % 251).toByte() }
    private val password = "parola-exemplu"

    @Test
    fun `opens only with its password`() {
        val sealed = encrypt(plain, password, iterations = 1_000, chunkSize = 1_024)
        assertTrue(ArchiveEncryption.isEncrypted(MemoryByteSource(sealed)))
        assertFalse(ArchiveEncryption.isEncrypted(MemoryByteSource(plain)))
        assertEquals(-1, sealed.indexOf(plain.copyOf(64)))
        assertArrayEquals(plain, decrypt(sealed, password))
        assertThrows<ArchiveEncryption.Failure.WrongPassword> { decrypt(sealed, "alta-parola") }
    }

    @Test
    fun `refuses any change, reordering or cut`() {
        val sealed = encrypt(plain, password, iterations = 1_000, chunkSize = 1_024)
        val flipped = sealed.copyOf().also { it[it.size - 30] = (it[it.size - 30].toInt() xor 1).toByte() }
        assertThrows<ArchiveEncryption.Failure.WrongPassword> { decrypt(flipped, password) }

        val chunk = 1_024 + ArchiveEncryption.TAG_SIZE
        val cut = sealed.copyOf(ArchiveEncryption.HEADER_SIZE + 2 * chunk)
        assertThrows<ArchiveEncryption.Failure.WrongPassword> { decrypt(cut, password) }

        // Two chunks swapped: each is opened at its place, so both fail.
        val swapped = sealed.copyOf()
        val first = ArchiveEncryption.HEADER_SIZE
        sealed.copyInto(swapped, first, first + chunk, first + 2 * chunk)
        sealed.copyInto(swapped, first + chunk, first, first + chunk)
        val source = ArchiveEncryption.DecryptingSource(MemoryByteSource(swapped), password)
        assertThrows<ArchiveEncryption.Failure.WrongPassword> { source.read(0, 10) }

        val header = sealed.copyOf().also { it[8 + 2] = (it[8 + 2].toInt() xor 1).toByte() } // iterations
        assertThrows<Exception> { decrypt(header, password) }
    }

    @Test
    fun `empty and exact chunk sizes round-trip`() {
        for (size in listOf(0, 1, 1_024, 2_048, 2_049)) {
            val data = ByteArray(size) { 7 }
            val sealed = encrypt(data, password, iterations = 1_000, chunkSize = 1_024)
            assertArrayEquals(data, decrypt(sealed, password), "$size bytes")
            val chunks = maxOf(1, (size + 1_023) / 1_024)
            assertEquals(ArchiveEncryption.HEADER_SIZE + size + chunks * ArchiveEncryption.TAG_SIZE, sealed.size)
        }
    }

    @Test
    fun `written in pieces, read anywhere`() {
        val data = ByteArray(10_000) { (it * 7).toByte() }
        val sink = MemoryByteSink()
        val sealing = ArchiveEncryption.EncryptingSink(sink, password, iterations = 1_000, chunkSize = 1_024)
        var at = 0
        for (piece in listOf(1, 1_023, 1, 3_000, 0, 4_975, 1_000)) {
            sealing.write(data.copyOfRange(at, at + piece))
            at += piece
        }
        sealing.finish()
        assertEquals(1_024 + ArchiveEncryption.TAG_SIZE, sink.largestWrite, "A sealed chunk at a time")
        val source = ArchiveEncryption.DecryptingSource(MemoryByteSource(sink.data), password)
        assertEquals(data.size.toLong(), source.size)
        for ((offset, count) in listOf(0 to 10, 1_020 to 10, 5_000 to 3_000, 9_990 to 10, 0 to 10_000)) {
            assertArrayEquals(data.copyOfRange(offset, offset + count), source.read(offset.toLong(), count))
        }
        assertThrows<DosarZipEngine.ZipError.InvalidZipArchive> { source.read(9_995, 10) }
    }

    @Test
    fun `the password is read in its composed form`() {
        val composed = "parolă-exemplu"
        val decomposed = "parolă-exemplu"
        val sealed = encrypt(plain, decomposed, iterations = 1_000, chunkSize = 1_024)
        assertArrayEquals(plain, decrypt(sealed, composed))
    }

    @Test
    fun `the key is PBKDF2-HMAC-SHA256 of the password's UTF-8`() {
        // RFC 7914, section 11: P = "passwd", S = "salt", c = 1; the first 32 bytes.
        val rfc = ArchiveEncryption.deriveKey("passwd", "salt".encodeToByteArray(), 1).encoded
        assertEquals("55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc", HexFormat.of().formatHex(rfc))
        // The JVM's own PBKDF2, which turns the password into UTF-8 too, agrees.
        val salt = ByteArray(16) { it.toByte() }
        val jvm = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(PBEKeySpec("parolă-exemplu".toCharArray(), salt, 1_000, 256)).encoded
        assertArrayEquals(jvm, ArchiveEncryption.deriveKey("parolă-exemplu", salt, 1_000).encoded)
        // An empty password is a key too (no backup is protected with one).
        assertEquals(32, ArchiveEncryption.deriveKey("", salt, 1).encoded.size)
    }

    @Test
    fun `a header outside what a reader accepts is damaged`() {
        val sealed = encrypt(plain, password, iterations = 1_000, chunkSize = 1_024)
        fun patched(at: Int, vararg bytes: Int) = sealed.copyOf().also { copy ->
            bytes.forEachIndexed { i, b -> copy[at + i] = b.toByte() }
        }
        val cases = listOf(
            patched(8, 2), // version 2
            patched(9, 2), // another key derivation
            patched(10, 0, 0, 0, 0), // no rounds
            patched(10, 0, 0x0F, 0x42, 0x41), // 1 000 001 rounds
            patched(30, 0, 0, 0, 0), // chunks of no bytes
            patched(30, 0x01, 0, 0, 1), // chunks past 16 MiB
            sealed.copyOf(ArchiveEncryption.HEADER_SIZE + ArchiveEncryption.TAG_SIZE - 1), // shorter than one tag
        )
        for (case in cases) assertThrows<ArchiveEncryption.Failure.Damaged> { decrypt(case, password) }
    }

    @Test
    fun `a protected archive with more chunks than can be counted is refused, never a stop`() {
        // Version 1, PBKDF2, one round, a salt of zeros, chunks of one byte, a prefix of zeros.
        val header = ArchiveEncryption.magic + byteArrayOf(1, 1, 0, 0, 0, 1) + ByteArray(16) +
            byteArrayOf(0, 0, 0, 1) + ByteArray(8)
        val sealedChunk = 1L + ArchiveEncryption.TAG_SIZE
        val source = object : ArchiveByteSource {
            override val size = ArchiveEncryption.HEADER_SIZE + sealedChunk * (ArchiveEncryption.MAX_CHUNKS + 1)

            override fun read(offset: Long, count: Int): ByteArray =
                if (offset == 0L) header.copyOf(count) else ByteArray(count)
        }
        assertThrows<DosarZipEngine.ZipError.SizeLimitExceeded> { ArchiveEncryption.DecryptingSource(source, password) }
    }

    @Test
    fun `a protected archive asks for its password, and nothing typed is never a damaged file`() {
        val zip = createArchive(listOf(Entry("a.txt", "Dosar".encodeToByteArray())))
        val sealed = MemoryByteSource(encrypt(zip, password, iterations = 1_000, chunkSize = 1_024))
        fun paths(source: ArchiveByteSource, password: String?) =
            ArchiveOpening.opened(source, password) { plain -> DosarZipEngine.Reader(plain).items.map { it.path } }

        assertEquals(listOf("a.txt"), paths(MemoryByteSource(zip), null), "A plain archive needs none")
        assertEquals(listOf("a.txt"), paths(MemoryByteSource(zip), "ignored"))
        assertEquals(listOf("a.txt"), paths(sealed, password))
        assertEquals(ArchiveError.NeedsPassword, assertThrows<ArchiveError> { paths(sealed, null) })
        assertEquals(ArchiveError.NoPasswordTyped, assertThrows<ArchiveError> { paths(sealed, "") })
        assertEquals(ArchiveError.WrongPassword, assertThrows<ArchiveError> { paths(sealed, "alta-parola") })
        val damaged = encrypt(zip, password, iterations = 1_000, chunkSize = 1_024).also { it[8] = 9 }
        val damagedError = assertThrows<ArchiveError> { paths(MemoryByteSource(damaged), password) }
        assertEquals(ArchiveError.NotADossier, damagedError)
    }

    @Test
    fun `a chunk changed after opening fails as a wrong password where it is read`() {
        val zip = createArchive(listOf(Entry("vault/a.bin", ByteArray(5_000) { (it % 249).toByte() })))
        val sealed = encrypt(zip, password, iterations = 1_000, chunkSize = 1_024)
        val at = ArchiveEncryption.HEADER_SIZE + 100
        sealed[at] = (sealed[at].toInt() xor 1).toByte()
        val error = assertThrows<ArchiveError> {
            ArchiveOpening.opened(MemoryByteSource(sealed), password) { plain ->
                val reader = DosarZipEngine.Reader(plain)
                reader.items.forEach { reader.data(it) }
            }
        }
        assertEquals(ArchiveError.WrongPassword, error)
    }
}
