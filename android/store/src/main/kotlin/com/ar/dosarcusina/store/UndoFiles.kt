package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.Digests
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.MachineText
import java.io.File
import java.io.InputStream
import java.lang.ref.Cleaner
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

/**
 * The pictures and files one step took from the binder (a deleted document's pages, a deleted
 * section's photo, a photo it replaced), kept on disk only while the step's undo receipt can
 * bring them back, as the iOS app's `UndoFiles`
 * (ios/DosarCuSina/Services/Persistence/UndoFiles.swift). So "Anulează" works for a step of any
 * size, and a receipt never holds pictures in memory: what a record still has, it knows only by
 * digest.
 *
 * One folder per receipt, inside this run's folder under [root] (the app's cache folder). Each
 * file is named by its digest and read back only while its bytes still match it. The folder goes
 * as soon as the receipt goes (its toast left, or the step was taken back); what an earlier run
 * left (the app stopped while a toast showed) goes when the app next starts ([removeLeftovers]).
 */
class UndoFiles(root: File) {
    val folder: File = File(File(root, run), UUID.randomUUID().toString())

    /** What it keeps, by digest. */
    var kept: Set<String> = emptySet()
        private set

    // The folder goes with the receipt that holds this, whenever it goes.
    private val cleanup = cleaner.register(this, Removal(folder))

    /** Removes every copy and the folder now: the step was taken back, or its receipt let go. */
    fun removeAll() {
        cleanup.clean()
        kept = emptySet()
    }

    /** Keeps [file]'s bytes, known by its digest; the same bytes are kept once. */
    fun keep(file: StoredFile) {
        val digest = file.sha256.lowercase()
        if (digest in kept) return
        folder.mkdirs()
        val partial = File.createTempFile("keeping-", ".part", folder)
        try {
            file.open().use { input -> Files.copy(input, partial.toPath(), StandardCopyOption.REPLACE_EXISTING) }
            Files.move(partial.toPath(), File(folder, digest).toPath(), StandardCopyOption.ATOMIC_MOVE)
        } finally {
            partial.delete()
        }
        kept = kept + digest
    }

    /** Lets go of everything but [digests]. */
    fun keepOnly(digests: Set<String>) {
        for (digest in kept - digests) File(folder, digest).delete()
        kept = kept intersect digests
    }

    /** Every one of [digests] as kept; null when one is missing or no longer matches its digest. */
    fun files(digests: Set<String>): Map<String, StoredFile>? {
        val found = HashMap<String, StoredFile>()
        for (digest in digests) {
            val file = File(folder, digest)
            if (digest !in kept || !file.isFile || digestOf(file) != digest) return null
            found[digest] = KeptCopy(digest, file)
        }
        return found
    }

    private fun digestOf(file: File): String {
        val hasher = Digests.hasher()
        file.inputStream().use { input ->
            val buffer = ByteArray(BUFFER)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                hasher.update(buffer, 0, read)
            }
        }
        return MachineText.hex(hasher.digest())
    }

    private class Removal(private val folder: File) : Runnable {
        override fun run() {
            folder.deleteRecursively()
        }
    }

    private class KeptCopy(override val sha256: String, private val file: File) : StoredFile {
        override val size: Long get() = file.length()

        override fun open(): InputStream = file.inputStream()
    }

    companion object {
        private const val BUFFER = 64 * 1024
        private val cleaner: Cleaner = Cleaner.create()

        /** This run's folder under a root: removing an earlier run's leftovers never touches it. */
        val run: String = UUID.randomUUID().toString()

        /** Removes what earlier runs kept under [root]: their receipts are gone with them. */
        fun removeLeftovers(root: File) {
            root.listFiles().orEmpty().filter { it.name != run }.forEach { it.deleteRecursively() }
        }
    }
}
