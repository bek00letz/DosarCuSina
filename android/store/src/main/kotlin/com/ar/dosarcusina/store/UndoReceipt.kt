package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.StoredFile
import java.io.File
import java.io.IOException

/** What an undoable step did, and the receipt that takes it back. */
data class Undoable<T>(val value: T, val receipt: UndoReceipt)

/** Why a step couldn't be taken back. The screen words it; these say only which case it is. */
sealed class UndoError(message: String) : Exception(message) {
    /** Something the step changed was changed again since (another screen, another step). */
    class ChangedSince : UndoError("Something the step changed was changed again since")

    /** The step was already taken back, it never finished, or its receipt was let go. */
    class Unavailable : UndoError("The step can't be taken back")

    /** The pictures or files the step took, kept for its undo, can no longer be read. */
    class PicturesLost : UndoError("The pictures kept for the undo can't be read")
}

/**
 * Exactly what one step changed in the binder, made by the step itself, so the toast's
 * "Anulează" can put everything back as it was: values, links, documents and readings, as the
 * iOS app's `UndoReceipt` (ios/DosarCuSina/Services/Persistence/UndoReceipt.swift).
 *
 * A unit of work opened with [UnitOfWork.performUndoable] fills it as it saves: the records the
 * step made, and every stored property of the records it changed or deleted, as they were before
 * (read from the binder as stored, which holds the state the step started from), with every record
 * whose links or lists changed with them. Pictures and files are known by their digest
 * ([StoredValue.File]); the ones the step takes away are kept on disk ([UndoFiles]), never in memory.
 *
 * Undo takes back only what the step changed, property by property, in one unit of work. It
 * refuses when anything of a record's own state that the step changed was changed again since, or
 * when something came to point since at a record whose own state it changed or that it made, so it
 * never overwrites or strands something newer. A newer change to another property of the same
 * record stays, and so does what came to point at a record the step only linked to.
 *
 * A receipt lives in memory, only while the toast offers it ([discard] when the toast leaves).
 */
// Recording a step, sealing it and taking it back, each in its parts.
@Suppress("TooManyFunctions")
class UndoReceipt internal constructor(private val unit: UnitOfWork) {
    /** Records the step made; undo deletes them. */
    var inserted: List<RecordRef> = emptyList()
        private set

    /** Records the step changed or deleted, as they were before it. */
    var before: Map<RecordRef, RecordState> = emptyMap()
        private set

    /** Records the step deleted; undo brings them back. */
    var deleted: Set<RecordRef> = emptySet()
        private set

    /** Records the step made or changed, as it left them: undo checks they're still so. */
    var after: Map<RecordRef, RecordState> = emptyMap()
        private set

    /** The pictures and files the step took away, for undo to write back. */
    var files: UndoFiles? = null
        private set

    private var isSealed = false
    private var isUndone = false
    private var isDiscarded = false

    /** Whether "Anulează" can take this step back: it saved, changed something, and wasn't taken back yet. */
    val canUndo: Boolean
        get() = isSealed && !isUndone && !isDiscarded && !(inserted.isEmpty() && before.isEmpty())

    /** The records the step touched, for tests and for checking what a step did. */
    val touched: Set<RecordRef> get() = inserted.toSet() + before.keys

    /** Lets go of the receipt: its toast left. Its copies of what the step took go now. */
    fun discard() {
        isDiscarded = true
        files?.removeAll()
        files = null
    }

    // Recording (UnitOfWork)

    /** What the unit is about to save, read before the save while what it deletes can still be read. */
    internal class Pending(
        val inserted: List<RecordRef>,
        val before: Map<RecordRef, RecordState>,
        val files: UndoFiles?,
    )

    /**
     * Reads what [step] changed, just before it saves. Null when what the step takes can't be
     * kept; the receipt then stays unsealed and offers no undo, and the step itself still saves.
     */
    internal fun prepare(step: Step, storeFiles: StoreFiles, undoRoot: File): Pending? {
        val inserted = ArrayList<RecordRef>()
        val candidates = LinkedHashSet<RecordRef>()
        for (table in Tables.all) read(step, table, inserted, candidates)
        for (link in Tables.manyLinks) {
            for (owner in step.changedOwners(link)) {
                candidates += RecordRef(link.owner.type, owner)
                val targets = step.stored.linked(link, owner) + step.linked(link, owner)
                candidates += targets.map { RecordRef(link.target.type, it) }
            }
        }
        val before = LinkedHashMap<RecordRef, RecordState>()
        for (ref in candidates) capture(ref, step.stored)?.let { before[ref] = it }
        return try {
            Pending(inserted, before, taken(step, before, storeFiles, undoRoot))
        } catch (error: IOException) {
            unit.log.failed("Keeping what a step takes for its undo", error)
            null
        }
    }

    private fun <R : Any> read(
        step: Step,
        table: Table<R>,
        inserted: MutableList<RecordRef>,
        candidates: MutableSet<RecordRef>,
    ) {
        val changes = step.changes(table)
        for (record in changes.made) {
            inserted += RecordRef.of(table, record)
            candidates += RecordState.links(table, record, step).linked
        }
        for (record in changes.written) {
            candidates += RecordRef.of(table, record)
            candidates += RecordState.links(table, record, step).linked
            val stored = step.stored.row(table, table.rowOf(record))
            if (stored != null) candidates += RecordState.links(table, stored, step.stored).linked
        }
        for (record in changes.deleted) {
            candidates += RecordRef.of(table, record)
            candidates += RecordState.links(table, record, step.stored).linked
        }
    }

    /**
     * The pictures and files the step takes away: all of a deleted record's, and the ones a changed
     * record replaces or clears.
     */
    private fun taken(
        step: Step,
        before: Map<RecordRef, RecordState>,
        storeFiles: StoreFiles,
        undoRoot: File,
    ): UndoFiles? {
        val digests = before.flatMap { (ref, state) -> takenFrom(step, ref, state) }.toSet()
        if (digests.isEmpty()) return null
        val kept = UndoFiles(undoRoot)
        for (digest in digests) kept.keep(storeFiles.file(digest))
        return kept
    }

    /** The digests of the files [state] names that the record no longer holds in the same place, or at all. */
    private fun takenFrom(step: Step, ref: RecordRef, state: RecordState): List<String> {
        val table = Tables.named(ref.type) ?: return emptyList()
        val now = step.row(table, ref.row)
        return table.properties.filter { it.kind == StoredProperty.Kind.FILE }.mapNotNull { property ->
            val stored = state.values[property.name] as? StoredValue.File
            stored?.digest?.takeIf { now == null || readAny(property, now, step) != stored }
        }
    }

    /**
     * Completes the receipt once the unit has saved: how the step left every record it touched,
     * read from the step, and which of them are gone.
     */
    internal fun seal(pending: Pending, step: Step) {
        val left = LinkedHashMap<RecordRef, RecordState>()
        val gone = LinkedHashSet<RecordRef>()
        for (ref in pending.inserted + pending.before.keys) {
            val state = capture(ref, step)
            if (state != null) left[ref] = state else if (ref in pending.before) gone += ref
        }
        // A record written with the value it already had, or only read in case it changed, wasn't changed.
        val changed = pending.before.filter { (ref, state) -> left[ref] != state }
        inserted = pending.inserted
        before = changed
        after = left.filterKeys { it in changed || it in pending.inserted }
        deleted = gone
        files = pending.files
        files?.keepOnly(filesToWriteBack)
        if (files?.kept?.isEmpty() == true) {
            files?.removeAll()
            files = null
        }
        isSealed = true
    }

    /**
     * The pictures and files undo writes back: every one of a deleted record's, and the ones the
     * step changed on a record it left.
     */
    private val filesToWriteBack: Set<String>
        get() = before.flatMapTo(mutableSetOf()) { (ref, state) ->
            val names = after[ref]?.let { state.changed(from = it) } ?: state.values.keys
            names.mapNotNull { (state.values[it] as? StoredValue.File)?.digest }
        }

    // Undo

    /**
     * Puts back what the step changed, in one unit of work: records it deleted come back, records
     * it changed get back what it changed, records it made go. Their change times come back too,
     * unless a newer change gave one since: the unit gives none of its own ([ChangeOrigin.RESTORING]).
     */
    fun undo() {
        if (!canUndo) throw UndoError.Unavailable()
        val needed = filesToWriteBack
        val bytes = if (needed.isEmpty()) emptyMap() else files?.files(needed) ?: throw UndoError.PicturesLost()
        unit.perform(origin = ChangeOrigin.RESTORING) { step -> takeBack(step, bytes.values) }
        isUndone = true
        files?.removeAll()
        files = null
    }

    /** Puts back, in [step], what the step changed, with [files], the bytes it took. */
    private fun takeBack(step: Step, files: Collection<StoredFile>) {
        // Every record the step changed or deleted, as the step left it, is still here: else something changed since.
        if (!isUnchangedSinceStep(step)) throw UndoError.ChangedSince()
        files.forEach(step::keep)
        for (ref in deleted) step.bringBack(tableOf(ref), ref.row)
        for ((ref, state) in before) {
            val table = tableOf(ref)
            val record = requireNotNull(step.row(table, ref.row))
            takeBack(step, table, record, state, if (ref in deleted) null else after[ref])
        }
        // Last, so nothing that was there before goes with what the step made.
        for (ref in inserted) step.row(tableOf(ref), ref.row)?.let(step::remove)
    }

    /**
     * Whether every record the step left still holds what the step changed, nothing points at a
     * record it made or whose own state it changed that didn't then, and every record it deleted
     * is still gone.
     */
    private fun isUnchangedSinceStep(step: Step): Boolean {
        val asLeft = after.all { (ref, state) ->
            val table = tableOf(ref)
            val record = step.row(table, ref.row)
            record != null && isStillAsLeft(step, table, record, before[ref], state)
        }
        val stillGone = deleted.all { step.row(tableOf(it), it.row) == null }
        // A record the step changed and left, kept: brought back blank only where the step deleted it.
        return asLeft && stillGone && before.keys.all { it in deleted || step.row(tableOf(it), it.row) != null }
    }

    private fun capture(ref: RecordRef, view: BinderView): RecordState? {
        val table = Tables.named(ref.type) ?: return null
        return captureIn(table, ref.row, view)
    }

    private fun <R : Any> captureIn(table: Table<R>, row: Long, view: BinderView): RecordState? =
        view.row(table, row)?.let { RecordState.capture(table, it, view) }

    private fun tableOf(ref: RecordRef): Table<Any> {
        @Suppress("UNCHECKED_CAST")
        return requireNotNull(Tables.named(ref.type)) { "No kind of record ${ref.type}" } as Table<Any>
    }

    private fun <R : Any> readAny(property: StoredProperty<R>, record: Any, view: BinderView): StoredValue {
        @Suppress("UNCHECKED_CAST")
        return property.read(record as R, view)
    }

    internal companion object {
        /**
         * Whether [record] still holds what the step left ([after]) in every property the step
         * changed from [before]; with no [before] (a record the step made), in every property.
         */
        fun <R : Any> isStillAsLeft(
            view: BinderView,
            table: Table<R>,
            record: R,
            before: RecordState?,
            after: RecordState,
        ): Boolean {
            val changed = before?.let { after.changed(from = it) }
            val stepChanged = { name: String -> changed?.contains(name) ?: true }
            // A record the step made, or whose own state it changed: whatever came to point at it
            // since was built on what the step did, and the undo would pull it away.
            val ownStateChanged = table.properties.any { stepChanged(it.name) && ChangeTimes.isOwnState(it, record) }
            return table.properties.all { property ->
                val left = after.values[property.name]
                when {
                    left == null -> true
                    ChangeTimes.isOwnState(property, record) ->
                        !stepChanged(property.name) || property.read(record, view) == left
                    // Something that points at it now and didn't then.
                    !property.isOwn && ownStateChanged -> left.refs.containsAll(property.read(record, view).refs)
                    else -> true
                }
            }
        }

        /**
         * Writes back [before] where the step changed it from [after]; with no [after] (a record the
         * step deleted, brought back blank), every property. A time the unit keeps, and what of a
         * built-in category is the catalog's, go back only while still as the step left them; a
         * list of the records that point at this one follows their links.
         */
        fun <R : Any> takeBack(step: Step, table: Table<R>, record: R, before: RecordState, after: RecordState?) {
            val changed = after?.let { before.changed(from = it) }
            // A list of the records that point at this one follows their links.
            val written = table.properties.filter { it.isOwn && (changed == null || it.name in changed) }
            var result = record
            for (property in written) {
                val old = before.values[property.name]
                if (old != null && takesBack(property, result, old, after, step)) {
                    if (property.kind == StoredProperty.Kind.LINKS) {
                        restoreLinks(step, table, table.rowOf(result), property.name, old)
                    } else {
                        result = requireNotNull(property.write)(result, old, step)
                    }
                }
            }
            step.update(result)
        }

        /**
         * Whether [property] of [record] goes back to [old]: not when it already is, nor when it
         * is a time the unit keeps (or the catalog's part of a built-in) changed again since.
         */
        private fun <R : Any> takesBack(
            property: StoredProperty<R>,
            record: R,
            old: StoredValue,
            after: RecordState?,
            view: BinderView,
        ): Boolean {
            val now = property.read(record, view)
            val left = after?.values?.get(property.name)
            val changedSince = left != null && !ChangeTimes.isOwnState(property, record) && now != left
            return now != old && !changedSince
        }

        private fun <R : Any> restoreLinks(step: Step, table: Table<R>, row: Long, name: String, value: StoredValue) {
            val link = Tables.manyLinks.first { it.owner === table && it.name == name }
            val targets = value.refs.map { it.row }.filter { step.row(link.target, it) != null }
            step.setLinked(link, row, targets)
        }
    }
}
