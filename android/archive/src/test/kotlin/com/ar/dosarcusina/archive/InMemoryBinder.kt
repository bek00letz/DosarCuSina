package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.ArchiveTarget
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.v3.MemoryFile
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.time.Instant

/**
 * A binder kept in memory, for the tests: the archive target Phase 2's Room store will be. It
 * writes an import's changes everything or nothing, copies every file in as it writes it (so a
 * record never points at the import's staging folder once it is in), and keeps the locks.
 */
class InMemoryBinder(initial: Binder = Binder()) : ArchiveTarget {
    var binder: Binder = initial
        private set

    /** How many times an import wrote. */
    var applied = 0
        private set

    /** Fails the next write half way, to show that nothing of it stays. */
    var failsNextWrite = false

    override fun snapshot(): Binder = binder

    override fun apply(changes: BinderChanges) {
        val written = changes.written
        val removed = changes.removed
        fun <K, R> merged(current: List<R>, incoming: List<R>, out: Set<K>, key: (R) -> K): List<R> {
            val byKey = LinkedHashMap<K, R>()
            for (record in current) if (key(record) !in out) byKey[key(record)] = record
            for (record in incoming) byKey[key(record)] = record
            return byKey.values.toList()
        }
        val next = Binder(
            templates = merged(binder.templates, written.templates, removed.templates) { it.key },
            assets = merged(binder.assets, written.assets.map {
                it.copy(photo = it.photo?.let(::copied))
            }, removed.assets) { it.id },
            obligations = merged(binder.obligations, written.obligations, removed.obligations) { it.id },
            historyEntries = merged(binder.historyEntries, written.historyEntries, removed.historyEntries) { it.id },
            serviceItems = merged(binder.serviceItems, written.serviceItems, removed.serviceItems) { it.id },
            providers = merged(binder.providers, written.providers, removed.providers) { it.id },
            measurements = merged(binder.measurements, written.measurements, removed.measurements) { it.id },
            attachments = merged(
                binder.attachments,
                written.attachments.map {
                    it.copy(
                        file = it.file?.let(::copied),
                        pages = it.pages.map(::copied),
                        thumbnail = it.thumbnail?.let(::copied),
                    )
                },
                removed.attachments,
            ) { it.id },
            issuerLessons = merged(binder.issuerLessons, written.issuerLessons, removed.issuerLessons) { it.id },
            locks = (binder.locks + changes.locks).filterKeys { it !in removed.templates },
        )
        if (failsNextWrite) {
            failsNextWrite = false
            error("The store failed half way")
        }
        binder = next
        applied += 1
    }

    /** A file's bytes, now the binder's own. */
    private fun copied(file: StoredFile): StoredFile = file as? MemoryFile
        ?: MemoryFile(file.open().use { it.readAllBytes() })
}

/** `shared/`, where the format's fixtures and test vectors are. */
val sharedFolder: File get() = File(System.getProperty("dosar.shared") ?: "../../shared")

/** A fixture folder of `shared/fixtures`, zipped the way any platform would, with [edit] applied to its files first. */
fun fixtureArchive(relativePath: String, edit: (MutableMap<String, ByteArray>) -> Unit = {}): ByteArray {
    val base = File(sharedFolder, "fixtures/$relativePath")
    val files = sortedMapOf<String, ByteArray>()
    base.walkTopDown().filter(File::isFile).forEach {
        files[it.relativeTo(base).invariantSeparatorsPath] = it.readBytes()
    }
    edit(files)
    return createArchive(files.map { (path, data) -> Entry(path, data) })
}

/** Rewrites a hand-made archive's manifest checksum for [path] after an edit. */
fun MutableMap<String, ByteArray>.rechecksum(path: String) {
    val manifest = MachineText.parse(getValue("manifest.json").decodeToString()) as JsonObject
    val checksums = (manifest["checksums"] as JsonObject).toMutableMap()
    checksums[path] = JsonPrimitive(sha256(getValue(path)))
    val updated = JsonObject(manifest + ("checksums" to JsonObject(checksums)))
    this["manifest.json"] = MachineText.json(updated).encodeToByteArray()
}

/** A moment, in the tests' own words. */
fun moment(text: String): Instant = Instant.parse(text)
