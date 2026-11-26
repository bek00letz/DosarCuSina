package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.binder.ArchiveTarget
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.store.repairs.DataRepairCenter
import com.ar.dosarcusina.store.schema.StoredMoment
import kotlinx.coroutines.runBlocking
import java.time.ZoneId

/**
 * Where an import writes and a backup reads, over the store: the archive's [ArchiveTarget].
 *
 * [snapshot] reads the binder in one read transaction ([BinderSnapshot], [BinderReading]). [apply]
 * writes an import as one step of the unit of work, a backup's own writer
 * ([UnitOfWork.performPrivate]): everything or nothing, its words masked like any save's, the
 * times the backup carries kept and none given of its own. The files first, each copied in a
 * piece at a time ([Step.keep]); then every row ([BinderWriting]); then the locks it raises (so a
 * lock kept for an import that then fails is only ever a lock raised). Whatever happens, the files
 * no row names any more go, the copies of a failed import with them.
 *
 * What a backup brought may need repairs (deadlines from a first-version copy, a whole card number):
 * after every import, whichever way it came in, the repair list looks again ([DataRepairCenter]), and
 * the calm prompt says so, as the iOS app's `DossierArchiveService.lookForRepairs`. The backup is in by
 * then, so a repair list that can't look doesn't undo it: the failure is logged, and the list looks
 * again at the next launch.
 *
 * An import only raises locks (the iOS app's `DossierImporter`): each category the import leaves
 * locked is locked through [DeviceLocks.lock], which, for one that was open here, also writes on its
 * record when it was locked, so the lock travels to the person's other phones as one locked here
 * does. A category the import leaves open needs no choice, and none is written: what this phone
 * chose for a category stays, a category that goes included, so nothing opens if it comes back.
 */
class RoomArchiveTarget(
    private val unit: UnitOfWork,
    /** The repair list every import looks at again. */
    private val repairs: DataRepairCenter,
    /**
     * The time zone the app counts days in (`Calendar.dosar`): a due day that can't be read is
     * the day its deadline was made there.
     */
    private val zone: () -> ZoneId = DosarCalendar::zone,
) : ArchiveTarget {
    /** Runs inside the import's step once every row is written, before the locks: how a test fails half way. */
    internal var beforeLocks: () -> Unit = {}

    override fun snapshot(): Binder {
        val snapshot = runBlocking { BinderSnapshot.read(unit.store.database) }
        val locked = unit.locks.locked(snapshot.all(Tables.templates))
        return BinderReading(unit.store.files, zone()).read(snapshot, locked)
    }

    override fun apply(changes: BinderChanges) {
        unit.performPrivate { step ->
            filesOf(changes).forEach(step::keep)
            BinderWriting(step, changes).write()
            beforeLocks()
            raise(step, changes.locks.filterValues { it }.keys)
        }
        unit.log.attempt(LOOK_FOR_REPAIRS) { repairs.refresh(announce = true) }
    }

    /** Locks every category of [keys] here, in the import's step. */
    private fun raise(step: Step, keys: Set<String>) {
        if (keys.isEmpty()) return
        val at = StoredMoment.kept(unit.clock())
        for (row in step.all(Tables.templates)) {
            if (row.key in keys) step.update(unit.locks.lock(row, at))
        }
    }

    private fun filesOf(changes: BinderChanges): List<StoredFile> =
        changes.written.assets.mapNotNull { it.photo } +
            changes.written.attachments.flatMap { listOfNotNull(it.file, it.thumbnail) + it.pages }

    private companion object {
        const val LOOK_FOR_REPAIRS = "Refreshing the repair list after an import"
    }
}
