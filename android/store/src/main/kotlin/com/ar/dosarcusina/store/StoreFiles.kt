package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.Digests
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.MachineText
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The pictures and files the database names, kept beside it in one folder, each under its
 * SHA-256 digest: the iOS store's `.externalStorage` (a section's photo, a document's original,
 * its thumbnail and its pages). A column holds the digest; the bytes are here once, however
 * many records name them, and a file never changes once it is kept.
 */
class StoreFiles(val folder: File) {
    init {
        folder.mkdirs()
    }

    /**
     * Keeps [file] and gives its digest: copied in a piece at a time, checked against the digest
     * it says it has, and only then put under that name, so a file half copied never shows.
     * A file already kept is not copied again.
     */
    fun keep(file: StoredFile): String {
        val digest = file.sha256.lowercase()
        require(isDigest(digest)) { "A kept file is named by its SHA-256 digest" }
        val target = File(folder, digest)
        if (target.isFile) return digest
        val partial = File.createTempFile("keeping-", ".part", folder)
        try {
            val copied = file.open().use { input -> partial.outputStream().use { output -> copy(input, output) } }
            if (copied != digest) throw IOException("A file's bytes don't match its digest")
            Files.move(
                partial.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } finally {
            partial.delete()
        }
        return digest
    }

    /** The kept file named [digest]. */
    fun file(digest: String): StoredFile = KeptFile(digest.lowercase(), File(folder, digest.lowercase()))

    /**
     * Removes every kept file not in [named], and anything a copy left half done: what no record
     * names any more. Run only while nothing else writes the store (the store's write lock).
     */
    fun keepOnly(named: Set<String>) {
        val keep = named.map(String::lowercase).toSet()
        folder.listFiles().orEmpty().filter { it.isFile && it.name !in keep }.forEach { it.delete() }
    }

    /** Copies [input] to [output] a piece at a time, and gives the digest of what it copied. */
    private fun copy(input: InputStream, output: OutputStream): String {
        val hasher = Digests.hasher()
        val buffer = ByteArray(BUFFER)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            hasher.update(buffer, 0, read)
            output.write(buffer, 0, read)
        }
        return MachineText.hex(hasher.digest())
    }

    private fun isDigest(text: String): Boolean =
        text.length == DIGEST_LENGTH && text.all { it in '0'..'9' || it in 'a'..'f' }

    private companion object {
        const val BUFFER = 64 * 1024
        const val DIGEST_LENGTH = 64
    }
}

/** A file the store keeps: the same file as another with the same digest. */
private class KeptFile(override val sha256: String, private val file: File) : StoredFile {
    override val size: Long get() = file.length()

    override fun open(): InputStream = file.inputStream()

    override fun equals(other: Any?): Boolean = other is KeptFile && other.sha256 == sha256

    override fun hashCode(): Int = sha256.hashCode()

    override fun toString(): String = "KeptFile($sha256)"
}
