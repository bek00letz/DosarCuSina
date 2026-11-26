package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.store.schema.StoredMoment
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.util.UUID

/**
 * Which categories this phone keeps behind the person's confirmation: the one source of truth for
 * a section's lock, as the iOS app's `SectionLocks` (ios/DosarCuSina/Services/Security/SectionLocks.swift).
 * [CategoryLocks] reads it and is the one way to change it.
 *
 * Locking travels, opening doesn't (DECISIONS, 2026-11-25). This phone's choices live on it, beside
 * the store, never in it, each with when it was made; locking a category also writes when on its
 * record (`CategoryTemplate.lockedEverywhereAt`), which sync carries. A category is locked here when
 * it was locked anywhere after this phone last chose for it (or this phone never chose), else as this
 * phone chose, else as the catalog says (Acte and Sănătate) or as it was made ([isLocked]). So
 * locking on one phone locks it on every phone, a new one included, and opening it opens it only on
 * the phone that opens it.
 *
 * The choices are kept in a small file next to the store ([fileForStore]) and when each was made in
 * a second one beside it ([timesFile]), whose name starts with the first's, so "Începe din nou"
 * leaves both. They sit in the app's own storage, readable once the phone was unlocked after it
 * started, as the iOS files are. The files never leave the phone, so their form is this app's own:
 * the choices as a JSON object of category key to whether it is locked (the iOS form), the times as
 * a JSON object of category key to milliseconds since 1970, the precision the database keeps a
 * moment at. A store kept in memory (tests, previews) has locks of its own ([file] null), gone with it.
 *
 * Locks stay on when they can't be read ([needsChoosingAgain]). A file that is there but can't be
 * read, or none where one was set aside (by an older build's "Începe din nou", or by a change that
 * then couldn't write its new file), means every category is locked, whatever it was before and
 * whatever is chosen meanwhile, until the person keeps the locks ([chooseAgain], through
 * [CategoryLocks.keepLocksAsTheyAre], which takes a [LockLowering]). What couldn't be read is never
 * written over: the first change reads the file again, and if it still can't, sets it aside and
 * starts a new one that remembers the wait. A choice that can't be written throws, and then nothing
 * changes, so nothing shows as locked that isn't kept.
 *
 * Only the store changes it ([set], [adopt] and [chooseAgain] are the module's): every other caller
 * goes through [CategoryLocks], which asks for a [LockLowering] before anything opens.
 */
class SectionLocks(
    /** Where the choices are kept; none for a store in memory. */
    val file: File?,
) {
    private val mutex = Any()
    private var choices: Map<String, Boolean>
    /**
     * When this phone made each choice. A choice without a time (made before locks travelled, or its
     * time lost) is older than any lock made anywhere.
     */
    private var chosenAt: Map<String, Instant>
    /** Every category stays locked until the person keeps the locks ([chooseAgain]). */
    private var untilChosenAgain: Boolean
    /** The file is there and couldn't be read: it is read again before anything is written, and never written over. */
    private var fileUnread: Boolean
    private val changes = MutableStateFlow(0L)

    init {
        val loaded = file?.let(::load) ?: Loaded(emptyMap(), untilChosenAgain = false, fileUnread = false)
        choices = loaded.choices
        untilChosenAgain = loaded.untilChosenAgain
        fileUnread = loaded.fileUnread
        chosenAt = file?.let { loadTimes(timesFile(it)) }.orEmpty()
    }

    /**
     * Goes up with every change, for what follows the locks (search, widgets, reminders, a screen
     * that shows a lock): the iOS app's `SectionLocks.didChange` and `generation`.
     */
    val generation: StateFlow<Long> = changes.asStateFlow()

    /**
     * Whether [key] is locked on this phone: locked anywhere ([lockedEverywhereAt], from its record)
     * after this phone last chose for it, else its choice here, else [byDefault]. While the locks wait
     * to be chosen again, every category is locked.
     */
    fun isLocked(key: String, byDefault: Boolean, lockedEverywhereAt: Instant? = null): Boolean = synchronized(mutex) {
        when {
            untilChosenAgain -> true
            lockedEverywhereAt != null && chosenAt[key]?.isAfter(lockedEverywhereAt) != true -> true
            else -> choices[key] ?: byDefault
        }
    }

    /** Whether this phone chose to lock [key], and when ([LockPublishing] sends it up); none if it never chose. */
    fun lockedHere(key: String): Choice? = synchronized(mutex) { choices[key]?.let { Choice(it, chosenAt[key]) } }

    /** Whether this phone's locks couldn't be read and wait for the person to keep them as they are now. */
    val needsChoosingAgain: Boolean get() = synchronized(mutex) { untilChosenAgain }

    /** Every choice this phone made. */
    val all: Map<String, Boolean> get() = synchronized(mutex) { choices }

    /**
     * Locks or opens [key] on this phone, as chosen at [now]: a newer choice than any lock made
     * elsewhere, so opening here opens it here. Throws when the choice can't be kept; then nothing
     * changes. Only [CategoryLocks] calls it, after asking for what opening needs.
     */
    internal fun set(locked: Boolean, key: String, now: Instant) {
        update(choosing = setOf(key), now = now) { it[key] = locked }
    }

    /** Takes [values] as this phone's choices for keys it hasn't decided on, with no time: new categories' locks. */
    internal fun adopt(values: Map<String, Boolean>) {
        update(now = StoredMoment.now()) { choices ->
            for ((key, locked) in values) if (key != WAIT_KEY && key !in choices) choices[key] = locked
        }
    }

    /**
     * Ends the wait after the locks couldn't be read: [locks] (every category's lock as it shows now:
     * on) become this phone's choices, and a category of one's own from another phone starts open
     * again. That opens what would have been locked, so only [CategoryLocks.keepLocksAsTheyAre]
     * calls it, with the person's confirmation.
     */
    internal fun chooseAgain(locks: Map<String, Boolean>, now: Instant) {
        update(endingTheWait = true, choosing = locks.keys, now = now) { choices ->
            for ((key, locked) in locks) if (key != WAIT_KEY) choices[key] = locked
        }
    }

    /** Reads the file again if it couldn't be read before: the store opened again. */
    fun readAgainIfUnread() {
        val file = file ?: return
        val read = synchronized(mutex) {
            if (!fileUnread) return@synchronized false
            val again = load(file)
            if (again.fileUnread) return@synchronized false
            choices = again.choices
            untilChosenAgain = again.untilChosenAgain
            fileUnread = false
            true
        }
        if (read) told()
    }

    private fun update(
        endingTheWait: Boolean = false,
        choosing: Set<String> = emptySet(),
        now: Instant,
        change: (MutableMap<String, Boolean>) -> Unit,
    ) {
        val changed = synchronized(mutex) {
            if (fileUnread && file != null) {
                // It may read now; then the change goes over what it says.
                val again = load(file)
                if (!again.fileUnread) {
                    choices = again.choices
                    untilChosenAgain = again.untilChosenAgain
                    fileUnread = false
                }
            }
            val next = choices.toMutableMap().also(change).toMap()
            val waits = untilChosenAgain && !endingTheWait
            val at = StoredMoment.kept(now)
            val times = chosenAt.toMutableMap()
            for (key in choosing) if (key != WAIT_KEY && key in next) times[key] = at
            if (next == choices && waits == untilChosenAgain && times == chosenAt) return@synchronized false
            if (file != null) write(file, next, times, waits)
            choices = next
            chosenAt = times.toMap()
            untilChosenAgain = waits
            true
        }
        if (changed) told()
    }

    /** Called holding the mutex. */
    private fun write(file: File, next: Map<String, Boolean>, times: Map<String, Instant>, waits: Boolean) {
        // The times first: a choice whose time didn't make it reads as older, so locked wherever a
        // lock was made since (locks fail closed).
        if (times != chosenAt) {
            val written = JsonObject(times.toSortedMap().mapValues { JsonPrimitive(it.value.toEpochMilli()) })
            replace(timesFile(file), MachineText.json(written))
        }
        if (fileUnread) setAside(file)
        val stored = next.toSortedMap().mapValues { JsonPrimitive(it.value) } +
            (if (waits) mapOf(WAIT_KEY to JsonPrimitive(true)) else emptyMap())
        replace(file, MachineText.json(JsonObject(stored.toSortedMap())))
        fileUnread = false
    }

    private fun told() {
        changes.update { it + 1 }
    }

    /** Whether this phone chose to lock a category, and when; [at] is none for a choice from before locks travelled. */
    data class Choice(val locked: Boolean, val at: Instant?)

    /** What a file of choices says. */
    data class Loaded(
        val choices: Map<String, Boolean>,
        val untilChosenAgain: Boolean,
        val fileUnread: Boolean,
    )

    companion object {
        /**
         * Kept among the choices in the file while the locks wait to be chosen again (the iOS app's
         * `waitKey`). An older build reads it as the choice for a category that doesn't exist, and
         * leaves it.
         */
        const val WAIT_KEY = "#untilChosenAgain"

        /** The end of the name of the choices' file, after the store's own. */
        private const val SUFFIX = ".section-locks.json"

        /** How a file of choices that couldn't be read is named once set aside, after its own name. */
        private const val SET_ASIDE = ".unread-"

        /** How an older build's "Începe din nou" named what it moved aside, before the file's name. */
        private const val MOVED_ASIDE = "unreadable-"

        private val byFile = HashMap<String, SectionLocks>()

        /**
         * The locks of the store whose database is [database]: one for each store, so everything that
         * opens the same store shares them (the iOS app's `SectionLocks.of`).
         */
        fun of(database: File): SectionLocks {
            val file = fileForStore(database)
            return synchronized(byFile) { byFile.getOrPut(file.canonicalPath) { SectionLocks(file) } }
        }

        /** Where a store's locks are kept on this phone: beside its database, never in it. */
        fun fileForStore(database: File): File = File(database.absoluteFile.parentFile, database.name + SUFFIX)

        /** When this phone made each choice: beside the choices, under a name that starts with theirs. */
        fun timesFile(file: File): File = File(file.absoluteFile.parentFile, file.name + ".times")

        /**
         * What [file] says. A file that is there and can't be read keeps every category locked. With
         * none where one was set aside, every category is locked too, until the person chooses again.
         */
        fun load(file: File): Loaded {
            if (!file.exists()) return Loaded(emptyMap(), untilChosenAgain = wasSetAside(file), fileUnread = false)
            val stored = readChoices(file) ?: return Loaded(emptyMap(), untilChosenAgain = true, fileUnread = true)
            return Loaded(stored - WAIT_KEY, untilChosenAgain = stored[WAIT_KEY] ?: false, fileUnread = false)
        }

        /**
         * What the times file says; none when it isn't there or can't be read (every choice then
         * reads as older than any lock).
         */
        fun loadTimes(file: File): Map<String, Instant> {
            val text = read(file) ?: return emptyMap()
            val stored = MachineText.parseOrNull(text) as? JsonObject ?: return emptyMap()
            return stored.mapNotNull { (key, value) ->
                (value as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull?.let { key to Instant.ofEpochMilli(it) }
            }.toMap()
        }

        /** The choices in [file], every value a yes or a no, or none when it can't be read as that. */
        private fun readChoices(file: File): Map<String, Boolean>? {
            val stored = read(file)?.let(MachineText::parseOrNull) as? JsonObject ?: return null
            val choices = stored.mapValues { (_, value) ->
                (value as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: return null
            }
            return choices
        }

        private fun read(file: File): String? = try {
            file.readText()
        } catch (_: IOException) {
            null
        }

        /**
         * Whether this phone's choices were set aside with none written after them: by an older
         * build's "Începe din nou" ("unreadable-<when>-<file>"), or by a change that set an unread
         * file aside and then couldn't write its own.
         */
        private fun wasSetAside(file: File): Boolean {
            val names = file.absoluteFile.parentFile?.list().orEmpty()
            return names.any {
                (it.startsWith(MOVED_ASIDE) && it.endsWith("-" + file.name)) || it.startsWith(file.name + SET_ASIDE)
            }
        }

        /** Keeps a file that couldn't be read beside the new one, never under it. */
        private fun setAside(file: File) {
            val target = File(file.absoluteFile.parentFile, file.name + SET_ASIDE + UUID.randomUUID())
            Files.move(file.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
        }

        /** Writes [text] as [file] whole or not at all: beside it first, then moved over it. */
        private fun replace(file: File, text: String) {
            val folder = file.absoluteFile.parentFile
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
    }
}
