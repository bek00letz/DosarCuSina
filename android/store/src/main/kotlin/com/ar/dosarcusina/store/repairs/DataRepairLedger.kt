package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * What the owner chose to leave as it is ("Lasă așa"), and what the calm prompt already announced,
 * by finding id, as the iOS app's `DataRepairLedger`. Kept on this phone, never in the binder: a
 * repair is about this phone's data.
 *
 * It lives in a small file beside the store ([forStore]), as this phone's lock choices do, written
 * whole or not at all; a store kept in memory has one of its own ([file] null), gone with it. A file
 * that can't be read reads as empty: the list then shows what was put away again, never less.
 */
class DataRepairLedger(
    /** Where it is kept; none for a store in memory. */
    val file: File?,
) {
    private val mutex = Any()
    private var memory = Kept(emptySet(), emptySet())

    /** The findings left as they are. */
    val dismissed: Set<String> get() = synchronized(mutex) { read().dismissed }

    /** The findings the prompt announced. */
    val announced: Set<String> get() = synchronized(mutex) { read().announced }

    /** Remembers [ids] as left as they are. Throws when it can't be kept; then nothing changed. */
    fun dismiss(ids: List<String>) = synchronized(mutex) {
        val kept = read()
        write(kept.copy(dismissed = kept.dismissed + ids))
    }

    /** The findings the prompt hasn't announced yet; marks them announced. */
    fun unannounced(findings: List<DataRepairFinding>): List<DataRepairFinding> = synchronized(mutex) {
        val kept = read()
        val new = findings.filter { it.id !in kept.announced }
        if (new.isEmpty()) return@synchronized emptyList()
        // Only what is still pending is kept, so the list never grows without end.
        val pending = findings.map { it.id }.toSet()
        write(kept.copy(announced = kept.announced.intersect(pending) + new.map { it.id }))
        new
    }

    /** Marks [findings] announced: the owner saw them in the list. */
    fun markAnnounced(findings: List<DataRepairFinding>) = synchronized(mutex) {
        val kept = read()
        write(kept.copy(announced = kept.announced + findings.map { it.id }))
    }

    private data class Kept(val dismissed: Set<String>, val announced: Set<String>)

    /** Called holding the mutex. */
    private fun read(): Kept {
        val file = file ?: return memory
        val text = try {
            file.takeIf { it.exists() }?.readText()
        } catch (_: IOException) {
            null
        } ?: return Kept(emptySet(), emptySet())
        val stored = MachineText.parseOrNull(text) as? JsonObject ?: return Kept(emptySet(), emptySet())
        return Kept(ids(stored[DISMISSED]), ids(stored[ANNOUNCED]))
    }

    /** Called holding the mutex. */
    private fun write(kept: Kept) {
        val file = file ?: run {
            memory = kept
            return
        }
        val stored = JsonObject(
            mapOf(
                ANNOUNCED to JsonArray(kept.announced.sorted().map(::JsonPrimitive)),
                DISMISSED to JsonArray(kept.dismissed.sorted().map(::JsonPrimitive)),
            ),
        )
        val folder = file.absoluteFile.parentFile
        folder.mkdirs()
        val partial = File.createTempFile(file.name + "-", ".part", folder)
        try {
            partial.writeText(MachineText.json(stored))
            Files.move(
                partial.toPath(),
                file.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } finally {
            partial.delete()
        }
    }

    private fun ids(element: JsonElement?): Set<String> =
        (element as? JsonArray).orEmpty().mapNotNullTo(mutableSetOf()) {
            (it as? JsonPrimitive)?.takeIf { id -> id.isString }?.content
        }

    companion object {
        private const val DISMISSED = "dismissed"
        private const val ANNOUNCED = "announced"

        /** The end of the file's name, after the store's database's own. */
        private const val SUFFIX = ".repairs.json"

        /** The ledger of the store whose database is [database]: beside it, never in it. */
        fun forStore(database: File): DataRepairLedger =
            DataRepairLedger(File(database.absoluteFile.parentFile, database.name + SUFFIX))
    }
}
