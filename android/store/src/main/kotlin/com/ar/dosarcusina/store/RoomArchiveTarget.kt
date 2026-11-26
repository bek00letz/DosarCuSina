package com.ar.dosarcusina.store

import androidx.room3.withReadTransaction
import androidx.room3.withWriteTransaction
import com.ar.dosarcusina.archive.binder.ArchiveTarget
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.store.schema.StoredMoment
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.withLock
import java.time.Instant
import java.time.ZoneId

/**
 * Where an import writes and a backup reads, over the store: the archive's [ArchiveTarget].
 *
 * [snapshot] reads the binder in one read transaction ([BinderReading]), with whether each of its
 * categories is locked on this phone now (the one answer, [DeviceLocks.locked]). [apply] writes an
 * import everything or nothing, holding the store's write lock: the files first, each copied in a
 * piece at a time ([StoreFiles.keep]); then every row in one write transaction ([BinderWriting]),
 * the locks the import raises last inside it (so a lock kept for an import that then fails is only
 * ever a lock raised); then, whatever happened, the files no row names any more go, the copies of a
 * failed import with them.
 *
 * An import only raises locks (the iOS app's `DossierImporter`): each category the import leaves
 * locked is locked through [DeviceLocks.lock], which, for one that was open here, also writes on its
 * record when it was locked, so the lock travels to the person's other phones as one locked here
 * does. A category the import leaves open needs no choice, and none is written: what this phone
 * chose for a category stays, a category that goes included, so nothing opens if it comes back.
 *
 * It saves outside the unit of work, which comes next: an import through it then masks card
 * numbers like every other save and gives no change times of its own.
 */
class RoomArchiveTarget(
    private val store: BinderStore,
    private val locks: DeviceLocks,
    /**
     * The time zone the app counts days in (`Calendar.dosar`): a due day that can't be read is
     * the day its deadline was made there.
     */
    private val zone: () -> ZoneId = DosarCalendar::zone,
    /** Now, for when a lock the import raises was made. */
    private val now: () -> Instant = StoredMoment::now,
) : ArchiveTarget {
    /** Runs inside the write transaction once every row is written, before the locks: how a test fails half way. */
    internal var beforeLocks: () -> Unit = {}

    override fun snapshot(): Binder = runBlocking {
        store.database.withReadTransaction {
            val locked = locks.locked(store.database.templates().all())
            BinderReading(store.files, zone()).read(store.database, locked)
        }
    }

    override fun apply(changes: BinderChanges) = runBlocking {
        store.writing.withLock {
            try {
                filesOf(changes).forEach(store.files::keep)
                store.database.withWriteTransaction {
                    BinderWriting(store.database, changes).write()
                    beforeLocks()
                    raise(changes.locks.filterValues { it }.keys)
                }
            } finally {
                store.files.keepOnly(store.database.withReadTransaction { store.database.files().named().toSet() })
            }
        }
    }

    /** Locks every category of [keys] here, inside the import's transaction. */
    private suspend fun raise(keys: Set<String>) {
        if (keys.isEmpty()) return
        val at = now()
        for (row in store.database.templates().all()) {
            if (row.key !in keys) continue
            val saved = locks.lock(row, at)
            if (saved != row) store.database.templates().update(saved)
        }
    }

    private fun filesOf(changes: BinderChanges): List<StoredFile> =
        changes.written.assets.mapNotNull { it.photo } +
            changes.written.attachments.flatMap { listOfNotNull(it.file, it.thumbnail) + it.pages }
}
