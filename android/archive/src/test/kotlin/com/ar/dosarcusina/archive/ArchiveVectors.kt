package com.ar.dosarcusina.archive

import java.io.File
import java.security.MessageDigest
import java.time.Instant

/**
 * The archives both apps check each other with, in shared/test-vectors/archive (its README says
 * what each file is). The iOS tests' ArchiveVectorsTests.swift makes the same entries the same
 * way: what is described here is described there, and `contents.sha256` holds both to it.
 */
object ArchiveVectors {
    val directory: File =
        File(requireNotNull(System.getProperty("dosar.shared")) { "dosar.shared is set by the build" })
            .resolve("test-vectors/archive")

    /** Whether this run writes the Android-made files and the refused cases again (`-PwriteArchiveVectors`). */
    val writes: Boolean = System.getProperty("dosar.writeArchiveVectors") == "1"

    /** The placeholder password of the protected files, with a letter outside ASCII. */
    const val PASSWORD = "parolă-exemplu"

    /** When every entry says it was written; entry times are local to the writer and never compared. */
    val written: Instant = Instant.parse("2026-11-25T10:00:00Z")

    /** The listing of what every vector holds: `<sha256>  <path>`, in the directory's order, folders left out. */
    val contents: File get() = directory.resolve("contents.sha256")

    /** The refused cases: `<file>\t<kind>\t<what it is>`, the kind as the iOS app names its error. */
    val refused: File get() = directory.resolve("refused.tsv")

    /** The entries every vector holds, in the order they are written: a folder among them. */
    fun entries(): List<Entry> = listOf(
        Entry("text/repeated.txt", "Dosar cu Șină, vector de test.\n".repeat(200).encodeToByteArray(), written),
        Entry("text/empty.txt", ByteArray(0), written),
        Entry("acte/", ByteArray(0), written),
        Entry(
            "acte/însemnare-ș.txt",
            "Însemnare de probă: ș, ț, ă, î, â.\n".encodeToByteArray(),
            written,
        ),
        Entry("vault/pagini.bin", pages(), written),
    )

    /** What a reader lists of [entries]: `<sha256>  <path>` lines. */
    fun listing(): String = entries().filterNot { it.path.endsWith("/") }
        .joinToString("") { "${sha256(it.data)}  ${it.path}\n" }

    /** 1 100 000 bytes: the SHA-256 of "pagina-0", of "pagina-1", and so on, one after another. */
    private fun pages(): ByteArray {
        val size = 1_100_000
        val out = java.io.ByteArrayOutputStream(size)
        var block = 0
        while (out.size() < size) {
            out.write(MessageDigest.getInstance("SHA-256").digest("pagina-$block".encodeToByteArray()))
            block += 1
        }
        return out.toByteArray().copyOf(size)
    }
}
