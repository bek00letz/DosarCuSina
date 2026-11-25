package com.ar.dosarcusina.archive

import java.io.Closeable
import java.io.File
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption

// The iOS app's ArchiveByteSource, ArchiveByteSink, ArchiveFileSource and ArchiveFileSink
// (ios/DosarCuSina/Services/Archive/DosarZipEngine.swift), the same way.

/**
 * Where an archive is read from, a piece at a time and at any place: a file on disk, or a
 * password-protected one opened chunk by chunk ([ArchiveEncryption.DecryptingSource]).
 * Nothing reads a whole archive into memory.
 */
interface ArchiveByteSource {
    /** How many bytes there are. */
    val size: Long

    /** [count] bytes from [offset], exactly; anything outside the source throws. */
    fun read(offset: Long, count: Int): ByteArray
}

/**
 * Where an archive is written, a piece after another: a file, or a password-protected one
 * sealed chunk by chunk ([ArchiveEncryption.EncryptingSink]).
 */
fun interface ArchiveByteSink {
    fun write(data: ByteArray)
}

/** A file read where it lies. */
class ArchiveFileSource(file: File) : ArchiveByteSource, Closeable {
    private val channel: FileChannel = FileChannel.open(file.toPath(), StandardOpenOption.READ)
    override val size: Long = channel.size()

    override fun read(offset: Long, count: Int): ByteArray {
        ensure(offset >= 0 && count >= 0 && count <= size - offset) { DosarZipEngine.ZipError.InvalidZipArchive }
        val buffer = ByteBuffer.allocate(count)
        var position = offset
        while (buffer.hasRemaining()) {
            val read = channel.read(buffer, position)
            // The file is shorter than it was when it was opened.
            ensure(read > 0) { DosarZipEngine.ZipError.InvalidZipArchive }
            position += read
        }
        return buffer.array()
    }

    override fun close() = channel.close()
}

/**
 * A new file, written a piece after another. It must not exist yet. An app's own files on
 * Android are its own, closed to every other app, so there is no protection to choose as iOS
 * does for a locked phone.
 */
class ArchiveFileSink(file: File) : ArchiveByteSink, Closeable {
    private val channel: FileChannel =
        FileChannel.open(file.toPath(), StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)
    private var closed = false

    override fun write(data: ByteArray) {
        if (data.isEmpty()) return
        val buffer = ByteBuffer.wrap(data)
        while (buffer.hasRemaining()) channel.write(buffer)
    }

    /** Everything written is on disk. */
    override fun close() {
        if (closed) return
        closed = true
        channel.use { it.force(true) }
    }
}

/** Throws what [error] makes unless [condition] holds: Swift's `guard … else { throw … }`. */
internal inline fun ensure(condition: Boolean, error: () -> Exception) {
    if (!condition) throw error()
}
