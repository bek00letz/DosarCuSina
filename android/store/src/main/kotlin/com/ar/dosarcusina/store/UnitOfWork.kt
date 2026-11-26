package com.ar.dosarcusina.store

import androidx.room3.withReadTransaction
import androidx.room3.withWriteTransaction
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.schema.StoredMoment
import com.ar.dosarcusina.store.security.SecretsKeptSealed
import kotlinx.coroutines.runBlocking
import java.io.File
import java.time.Instant

/**
 * A question for the person that a step must ask before its unit opens (a lower counter,
 * something of theirs in an example), as the iOS app's `StepQuestion`: thrown from inside a unit
 * once it has written, it is a step that didn't ask first, and the log says so.
 */
interface StepQuestion

/**
 * The one way the binder saves, and the way several actions become one step for the person, as
 * the iOS app's `UnitOfWork` (ios/DosarCuSina/Services/Persistence/UnitOfWork.swift).
 *
 * Every action records its changes in a [Step] handed to it by [perform], and the unit saves once
 * at the end: everything or nothing. A failure anywhere in the step, including the final save,
 * keeps none of it, so one "Salvează" never leaves half a filing behind. A unit opened inside
 * another one (on the same thread) joins it: the actions inside only record their changes, the
 * outer unit's origin holds, and it saves once.
 *
 * - **It never waits.** The work is plain code, never a suspending one: whatever a step needs that
 *   takes time (a capture's pages, the fingerprint, a reading) is gathered before the unit opens.
 *   The unit holds the store's write lock ([BinderStore.writing]) for the whole step, files
 *   included, so no other save slips into it, and none is lost with it: another thread's save
 *   waits, then saves on its own.
 * - **It asks first.** A step's questions for the person ([StepQuestion]) are asked before its unit
 *   opens; one thrown from inside it once it has written is logged as a fault.
 * - **It keeps every held record's holder by id** ([ParentLinks.stamp]), and a record goes with
 *   what it holds only through [RecordContents.delete] ([Step.delete]).
 * - **It keeps card numbers out** ([FreeText]): every card number in the words of every record it
 *   saves is masked just before it saves, whoever wrote it, a backup's own writer included.
 * - **It keeps secrets sealed** ([SecretsKeptSealed]): a section that would keep a secret in plain
 *   (a PIN, an alarm code) stops the save; every action seals first.
 * - **It keeps change times, and only it** ([ChangeTimes], [CycleTimes]), by whose step it is
 *   ([ChangeOrigin]), at the step's clock: the opener's, else the first one a step inside it gives,
 *   else the moment it saves.
 *
 * Work that must only happen once the changes are kept goes in [afterCommit]. A step the person
 * can take back opens its unit with [performUndoable], which returns the step's [UndoReceipt].
 */
class UnitOfWork(
    val store: BinderStore,
    /** This phone's locks: what a category a step makes is made with ([Step.lockMadeWith]) is kept before it saves. */
    internal val locks: DeviceLocks,
    /** Where a failure nobody is told of is logged: work after a save, a receipt's files, a late question. */
    internal val log: PersistenceLog,
    /** The moment a step saves, when it has no clock of its own. */
    internal val clock: () -> Instant = Instant::now,
    /** Where receipts keep the pictures their steps took ([UndoFiles]): the app's cache folder. */
    private val undoRoot: File = File(System.getProperty("java.io.tmpdir"), "Anulare"),
) {
    /** The unit open on this thread for [store], if any. */
    internal class Scope(val origin: ChangeOrigin, var now: Instant?, val step: Step, var receipt: UndoReceipt?) {
        val afterCommit = ArrayList<() -> Unit>()
    }

    /** Whether a unit of work is open on this thread. */
    val isOpen: Boolean get() = store.openScope.get() != null

    /** A failure the next save is to meet, for tests: cleared after one use. */
    @Volatile
    private var failingCommit: Throwable? = null

    /** Makes the next unit that writes fail as it saves, for a test to check a failed save leaves nothing behind. */
    internal fun failNextCommitForTesting(error: Throwable) {
        failingCommit = error
    }

    /**
     * Runs [work] as one step: the actions inside it record their changes in its [Step], and the
     * unit saves once at the end. If [work] throws or the save fails, nothing of it is kept and the
     * error is rethrown. Opened inside another unit, it joins it: the outer unit's [origin] holds,
     * and [now] is used only when the outer unit has no clock.
     *
     * [origin] says whose change it is: the person's by default. [now] is the step's clock, the
     * change time it gives; without one, the moment it saves.
     */
    fun <T> perform(origin: ChangeOrigin = ChangeOrigin.PERSON, now: Instant? = null, work: (Step) -> T): T {
        store.openScope.get()?.let { joined ->
            if (joined.now == null) joined.now = now
            return work(joined.step)
        }
        return run(origin, now, null, work)
    }

    /**
     * Runs [work] as one step, like [perform], and returns with its result the receipt that takes
     * it back. Opened inside another unit, it joins it, and the receipt covers that whole unit: the
     * step the person took is the outer one. The receipt is usable once the outermost unit has saved.
     */
    fun <T> performUndoable(now: Instant? = null, work: (Step) -> T): Undoable<T> {
        store.openScope.get()?.let { joined ->
            val receipt = joined.receipt ?: UndoReceipt(this).also { joined.receipt = it }
            if (joined.now == null) joined.now = now
            return Undoable(work(joined.step), receipt)
        }
        val receipt = UndoReceipt(this)
        return Undoable(run(ChangeOrigin.PERSON, now, receipt, work), receipt)
    }

    /**
     * Runs a backup's own writer as one step, as the iOS app's `performPrivate`: saved once,
     * everything or nothing, its holders stamped and its words masked like any save, and the times
     * the backup carries kept, none given of its own. It joins no other unit.
     */
    fun <T> performPrivate(work: (Step) -> T): T {
        check(!isOpen) { "A backup's writer is a step of its own" }
        return run(ChangeOrigin.RESTORING, null, null, work)
    }

    /** Runs [action] once the open unit has saved, or right away when none is open; nothing, when the unit fails. */
    fun afterCommit(action: () -> Unit) {
        val scope = store.openScope.get()
        if (scope != null) scope.afterCommit += action else afterSaving(listOf(action))
    }

    private fun <T> run(origin: ChangeOrigin, now: Instant?, receipt: UndoReceipt?, work: (Step) -> T): T {
        runBlocking { store.writing.lock() }
        val scope = Scope(origin, now, Step(store.database, store.files), receipt)
        store.openScope.set(scope)
        var wrote = false
        val result = try {
            val outcome = runCatching { work(scope.step) }
            outcome.exceptionOrNull()?.let { noteQuestionAskedLate(it, scope.step) }
            val value = outcome.getOrThrow()
            wrote = commit(scope)
            value
        } finally {
            store.openScope.remove()
            val keptFiles = scope.step.keptFiles
            scope.step.close()
            try {
                // What no record names any more goes: what a failed step kept, what a saved one let go of.
                if (wrote || keptFiles) store.files.keepOnly(namedFiles())
            } finally {
                store.writing.unlock()
            }
        }
        afterSaving(scope.afterCommit)
        return result
    }

    /** Saves everything the step recorded, in one transaction; whether it wrote anything. */
    private fun commit(scope: Scope): Boolean {
        val step = scope.step
        val now = StoredMoment.kept(scope.now ?: clock())
        keepLocksMadeWith(step, now)
        // What holds each record by id, card numbers out and change times first, so a receipt records
        // them; what the step changed is read before the save, while the store holds where it started.
        ParentLinks.stamp(step)
        FreeText.mask(step)
        SecretsKeptSealed.check(step, Catalog.builtIn)
        ChangeTimes.stamp(step, scope.origin, now)
        val receipt = scope.receipt
        val pending = receipt?.prepare(step, store.files, undoRoot)
        val wrote = step.hasChanges
        if (wrote) {
            failingCommit?.let {
                failingCommit = null
                throw it
            }
            runBlocking { store.database.withWriteTransaction { step.write() } }
        }
        if (receipt != null && pending != null) receipt.seal(pending, step)
        return wrote
    }

    /**
     * Keeps as this phone's choice the lock each new category was made with, before the save: a
     * category's lock lives on the phone, not in the store, and one that can't be kept stops the
     * save, so no category is saved open that was made locked. Its row comes back as it is to be
     * saved (one of the person's own made locked is locked everywhere).
     */
    private fun keepLocksMadeWith(step: Step, now: Instant) {
        for (template in step.changes(Tables.templates).made) {
            val locked = step.madeLocked[template.pk] ?: continue
            step.update(locks.madeWith(template, locked, now))
        }
    }

    private fun namedFiles(): Set<String> =
        runBlocking { store.database.withReadTransaction { store.database.files().named().toSet() } }

    private fun afterSaving(actions: List<() -> Unit>) {
        for (action in actions) log.attempt("Work after a save", action)
    }

    /**
     * A question thrown after the step wrote is a step that didn't ask first. It is only logged:
     * nothing of the step is kept, and a person must never lose their work to a development check.
     */
    private fun noteQuestionAskedLate(error: Throwable, step: Step) {
        if (error !is StepQuestion || !step.hasChanges) return
        val kind = PersistenceLog.kindOf(error)
        log.write(PersistenceLog.Entry(PersistenceLog.Level.FAULT, "A question asked after its unit wrote", kind))
    }
}
