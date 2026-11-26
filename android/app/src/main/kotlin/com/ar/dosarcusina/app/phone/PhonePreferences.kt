package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.store.PersistenceLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.Executor

/**
 * This phone's own small things, kept outside the binder and never in a backup: the box order, the
 * trips, the recent searches (what the iOS app keeps in `UserDefaults`). One small JSON file, one
 * object of key to value, read once into memory and written whole: the same way this phone's lock
 * choices and the repair list's ledger are kept beside the store, with the app's one JSON writer
 * ([MachineText]), and readable on the JVM as on the phone.
 *
 * Reads come from memory, so a screen can read on the main thread once [load] has run (the app runs
 * it at start, off the main thread). A change is in memory at once and written by [writer], one write
 * at a time, each the latest values, so the file never goes back to an older one; a write that fails
 * is logged by its kind and tried again with the next change. Keys this build doesn't know (a newer
 * version's) are kept as they are. A file that can't be read reads as empty: these are conveniences,
 * and the next change writes a good one.
 */
class PhonePreferences(
    /** The file, in the app's own storage. */
    val file: File,
    /** Where the file is written, one write at a time: a single background thread in the app. */
    private val writer: Executor,
    private val log: PersistenceLog,
) {
    private val mutex = Any()
    private val writing = Any()
    private var loaded = false
    private val current = MutableStateFlow(JsonObject(emptyMap()))

    /** Every value, as kept now: what a screen observes. */
    val values: StateFlow<JsonObject>
        get() {
            load()
            return current.asStateFlow()
        }

    /** Reads the file into memory, once. */
    fun load() = synchronized(mutex) {
        if (loaded) return@synchronized
        current.value = read()
        loaded = true
    }

    /** The value kept for [key], if any. */
    operator fun get(key: String): JsonElement? = values.value[key]

    /** Keeps [value] for [key]; none forgets it. */
    operator fun set(key: String, value: JsonElement?) {
        synchronized(mutex) {
            load()
            val next = LinkedHashMap(current.value)
            if (value == null) next.remove(key) else next[key] = value
            current.value = JsonObject(next)
        }
        writer.execute(::flush)
    }

    /** Writes what is in memory now, whole or not at all. */
    private fun flush() = synchronized(writing) {
        val text = MachineText.json(current.value)
        log.attempt(WRITING) { write(text) }
    }

    private fun write(text: String) {
        val folder = file.absoluteFile.parentFile
        folder.mkdirs()
        val partial = File.createTempFile(file.name + "-", ".part", folder)
        try {
            partial.writeText(text)
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

    private fun read(): JsonObject {
        val text = try {
            file.takeIf { it.isFile }?.readText()
        } catch (error: IOException) {
            log.failed(READING, error)
            null
        } ?: return JsonObject(emptyMap())
        return MachineText.parseOrNull(text) as? JsonObject ?: JsonObject(emptyMap())
    }

    private companion object {
        const val WRITING = "Keeping this phone's preferences"
        const val READING = "Reading this phone's preferences"
    }
}
