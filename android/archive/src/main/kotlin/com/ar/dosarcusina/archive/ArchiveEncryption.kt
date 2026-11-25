package com.ar.dosarcusina.archive

import java.nio.ByteBuffer
import java.security.GeneralSecurityException
import java.security.SecureRandom
import java.text.Normalizer
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * A password-protected `.dosar`: the plain archive, encrypted with a key made from the person's
 * password, the iOS app's `ArchiveEncryption`
 * (ios/DosarCuSina/Services/Archive/ArchiveEncryption.swift) byte for byte. Nothing of the
 * household can be read without it, and the password itself is never stored anywhere. It uses
 * only `javax.crypto` and `java.text.Normalizer`, which the JVM and Android both have.
 *
 * The layout, as shared/schemas/dosar-v3.md describes it (integers big-endian):
 *
 *     header  "DOSARENC" (8 bytes) · version 1 (1 byte) · key derivation 1 = PBKDF2-HMAC-SHA256 (1 byte)
 *             · iterations (4 bytes) · salt (16 bytes) · chunk size (4 bytes) · nonce prefix (8 bytes)
 *     body    the plain archive in chunks of `chunk size` bytes (the last one may be shorter), each
 *             encrypted with AES-256-GCM and followed by its 16-byte tag
 *
 * Chunk `i` uses the nonce `prefix ‖ i` (4 bytes) and authenticates the whole header plus one
 * byte, 1 for the last chunk and 0 for the others, so chunks can't be reordered, dropped or cut
 * off without the archive refusing to open.
 *
 * Both sides stream: [EncryptingSink] seals a chunk as soon as the next byte shows it isn't the
 * last, and [DecryptingSource] opens only the chunks a read needs, so neither holds more than a
 * chunk or two, whatever the archive's size.
 */
object ArchiveEncryption {
    /** `DOSARENC`, which tells a protected archive from a zip. */
    val magic: ByteArray get() = MAGIC.copyOf()
    internal const val VERSION: Byte = 1
    internal const val PBKDF2_SHA256: Byte = 1

    /** Slow enough to make guessing expensive, quick enough on a phone. */
    const val DEFAULT_ITERATIONS: Long = 600_000

    /**
     * The rounds a protected archive may ask for, written and read alike: the iOS app's
     * `acceptedIterations`, leaving room for one step up.
     */
    val acceptedIterations: LongRange = 1L..1_000_000L
    const val DEFAULT_CHUNK_SIZE: Int = 1 shl 20

    /** The chunk sizes written and read: a reader never holds more than two chunks. */
    val acceptedChunkSizes: IntRange = 1..(16 shl 20)
    internal const val SALT_SIZE = 16
    internal const val NONCE_PREFIX_SIZE = 8
    internal const val TAG_SIZE = 16
    internal const val HEADER_SIZE = 8 + 1 + 1 + 4 + SALT_SIZE + 4 + NONCE_PREFIX_SIZE

    /** The most chunks one archive has: a chunk's place is four bytes of its nonce. */
    internal const val MAX_CHUNKS = DosarZipEngine.UINT32_MAX + 1

    /** Passwords shorter than this are refused when exporting. */
    const val MINIMUM_PASSWORD_LENGTH: Int = 8

    private val MAGIC = "DOSARENC".encodeToByteArray()
    private const val KEY_SIZE = 32
    private const val TAG_BITS = TAG_SIZE * 8
    private const val ITERATIONS_AT = 10
    private const val SALT_AT = ITERATIONS_AT + 4
    private const val CHUNK_SIZE_AT = SALT_AT + SALT_SIZE
    private const val PREFIX_AT = CHUNK_SIZE_AT + 4

    /** What can go wrong opening one, the iOS app's `ArchiveEncryption.Failure`. */
    sealed class Failure : Exception() {
        /** The password doesn't open this archive (or the archive was changed after it was made). */
        data object WrongPassword : Failure()

        /** The file says it is protected but can't be read as such. */
        data object Damaged : Failure()
    }

    /** Whether the source is a password-protected archive. */
    fun isEncrypted(source: ArchiveByteSource): Boolean =
        source.size >= MAGIC.size && source.read(0, MAGIC.size).contentEquals(MAGIC)

    // Writing

    /**
     * Seals what it is given in chunks and passes them on. Call [finish] once, after the last
     * byte: it seals the last chunk, which may be shorter or even empty.
     */
    class EncryptingSink(
        private val inner: ArchiveByteSink,
        password: String,
        iterations: Long = DEFAULT_ITERATIONS,
        private val chunkSize: Int = DEFAULT_CHUNK_SIZE,
    ) : ArchiveByteSink {
        private val header: ByteArray
        private val prefix: ByteArray
        private val key: SecretKeySpec
        private val pending = ByteArray(chunkSize)
        private var filled = 0
        private var index = 0L
        private var finished = false

        init {
            require(iterations in acceptedIterations) { "Write only rounds a reader accepts." }
            require(chunkSize in acceptedChunkSizes) { "Write only chunk sizes a reader accepts." }
            val salt = randomBytes(SALT_SIZE)
            prefix = randomBytes(NONCE_PREFIX_SIZE)
            header = MAGIC + byteArrayOf(VERSION, PBKDF2_SHA256) + bigEndian(iterations) + salt +
                bigEndian(chunkSize.toLong()) + prefix
            key = deriveKey(password, salt, iterations)
            inner.write(header)
        }

        override fun write(data: ByteArray) {
            check(!finished) { "Nothing is written after the last chunk." }
            var at = 0
            while (at < data.size) {
                // A chunk is sealed once a byte after it arrives: then it can't be the last one.
                if (filled == chunkSize) {
                    seal(pending, isLast = false)
                    filled = 0
                }
                val take = minOf(chunkSize - filled, data.size - at)
                data.copyInto(pending, filled, at, at + take)
                filled += take
                at += take
            }
        }

        fun finish() {
            check(!finished) { "An archive is finished once." }
            finished = true
            seal(pending.copyOf(filled), isLast = true)
        }

        private fun seal(chunk: ByteArray, isLast: Boolean) {
            // More chunks than a nonce can count: more than one protected archive holds.
            ensure(index < MAX_CHUNKS) { DosarZipEngine.ZipError.TooLargeToWrite }
            val cipher = Cipher.getInstance(AES_GCM)
            cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce(prefix, index)))
            cipher.updateAAD(header + byteArrayOf(if (isLast) 1 else 0))
            index += 1
            // Java writes the tag after the ciphertext, as the format keeps it.
            inner.write(cipher.doFinal(chunk))
        }
    }

    // Reading

    /**
     * The plain archive inside a protected one, opened a chunk at a time where it is read.
     * Opening checks the password on the last chunk, so a wrong one fails at once; every chunk
     * read afterwards is checked too, and its place: one changed, moved or cut off fails.
     */
    class DecryptingSource(private val inner: ArchiveByteSource, password: String) : ArchiveByteSource {
        private val header: ByteArray
        private val prefix: ByteArray
        private val chunkSize: Int
        private val chunkCount: Long
        private val body: Long
        private val key: SecretKeySpec

        /** The plain archive's size. */
        override val size: Long

        /** The last two chunks opened, by index: a read across a chunk's end needs both. */
        private val opened = ArrayDeque<Pair<Long, ByteArray>>()

        init {
            ensure(inner.size >= HEADER_SIZE + TAG_SIZE) { Failure.Damaged }
            header = inner.read(0, HEADER_SIZE)
            ensure(header.copyOf(MAGIC.size).contentEquals(MAGIC)) { Failure.Damaged }
            ensure(header[MAGIC.size] == VERSION && header[MAGIC.size + 1] == PBKDF2_SHA256) { Failure.Damaged }
            val iterations = header.u32BigEndian(ITERATIONS_AT)
            val salt = header.copyOfRange(SALT_AT, SALT_AT + SALT_SIZE)
            val chunkSize = header.u32BigEndian(CHUNK_SIZE_AT)
            prefix = header.copyOfRange(PREFIX_AT, PREFIX_AT + NONCE_PREFIX_SIZE)
            ensure(iterations in acceptedIterations && chunkSize in acceptedChunkSizes.first..acceptedChunkSizes.last) {
                Failure.Damaged
            }
            this.chunkSize = chunkSize.toInt()

            body = inner.size - HEADER_SIZE
            val sealedChunk = chunkSize + TAG_SIZE
            chunkCount = (body + sealedChunk - 1) / sealedChunk
            ensure(body - (chunkCount - 1) * sealedChunk >= TAG_SIZE) { Failure.Damaged }
            // More chunks than a nonce can count: larger than any protected archive can be.
            ensure(chunkCount <= MAX_CHUNKS) { DosarZipEngine.ZipError.SizeLimitExceeded }
            size = body - chunkCount * TAG_SIZE
            key = deriveKey(password, salt, iterations)
            chunk(chunkCount - 1)
        }

        override fun read(offset: Long, count: Int): ByteArray {
            ensure(offset >= 0 && count >= 0 && count <= size - offset) { DosarZipEngine.ZipError.InvalidZipArchive }
            val result = ByteArray(count)
            var position = offset
            while (position < offset + count) {
                val index = position / chunkSize
                val plain = chunk(index)
                val from = (position - index * chunkSize).toInt()
                val take = minOf(plain.size - from, (offset + count - position).toInt())
                ensure(take > 0) { Failure.Damaged }
                plain.copyInto(result, (position - offset).toInt(), from, from + take)
                position += take
            }
            return result
        }

        private fun chunk(index: Long): ByteArray {
            opened.firstOrNull { it.first == index }?.let { return it.second }
            val sealedChunk = chunkSize.toLong() + TAG_SIZE
            val start = HEADER_SIZE + index * sealedChunk
            val length = minOf(sealedChunk, body - index * sealedChunk).toInt()
            val sealed = inner.read(start, length)
            val plain = try {
                val cipher = Cipher.getInstance(AES_GCM)
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce(prefix, index)))
                cipher.updateAAD(header + byteArrayOf(if (index == chunkCount - 1) 1 else 0))
                cipher.doFinal(sealed)
            } catch (@Suppress("SwallowedException") error: GeneralSecurityException) {
                // The tag doesn't match: the key is another one, or the chunk was changed or moved.
                throw Failure.WrongPassword
            }
            opened.addLast(index to plain)
            if (opened.size > 2) opened.removeFirst()
            return plain
        }
    }

    // Pieces

    /**
     * PBKDF2-HMAC-SHA256 of the password (UTF-8 of its normalization form C) with [salt] and
     * [iterations], one 32-byte block, worked out here with `Mac` so the bytes are exactly the
     * format's on every Android: a provider's own PBKDF2 may turn the password into bytes
     * another way.
     */
    internal fun deriveKey(password: String, salt: ByteArray, iterations: Long): SecretKeySpec {
        val passwordBytes = Normalizer.normalize(password, Normalizer.Form.NFC).encodeToByteArray()
        val mac = Mac.getInstance(HMAC_SHA256)
        // HMAC pads a short key with zeros, so an empty one is the single zero byte, which
        // `SecretKeySpec` takes; it refuses an empty one.
        mac.init(SecretKeySpec(if (passwordBytes.isEmpty()) byteArrayOf(0) else passwordBytes, HMAC_SHA256))
        var block = mac.doFinal(salt + bigEndian(1))
        val derived = block.copyOf()
        var round = 1L
        while (round < iterations) {
            block = mac.doFinal(block)
            for (i in derived.indices) derived[i] = (derived[i].toInt() xor block[i].toInt()).toByte()
            round += 1
        }
        check(derived.size == KEY_SIZE)
        return SecretKeySpec(derived, "AES")
    }

    private fun nonce(prefix: ByteArray, index: Long): ByteArray {
        ensure(index in 0..DosarZipEngine.UINT32_MAX) { Failure.Damaged }
        return prefix + bigEndian(index)
    }

    /** [count] random bytes, for a salt and a nonce prefix. */
    private fun randomBytes(count: Int): ByteArray = ByteArray(count).also { SecureRandom().nextBytes(it) }

    private const val AES_GCM = "AES/GCM/NoPadding"
    private const val HMAC_SHA256 = "HmacSHA256"
}

/** Four big-endian bytes of [value]. */
private fun bigEndian(value: Long): ByteArray = ByteBuffer.allocate(Int.SIZE_BYTES).putInt(value.toInt()).array()

/** A big-endian 32-bit field at [offset], as a non-negative number. */
private fun ByteArray.u32BigEndian(offset: Int): Long =
    ByteBuffer.wrap(this, offset, Int.SIZE_BYTES).int.toLong() and DosarZipEngine.UINT32_MAX
