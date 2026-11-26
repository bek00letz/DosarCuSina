package com.ar.dosarcusina.store

import androidx.room3.withReadTransaction
import androidx.room3.withWriteTransaction
import com.ar.dosarcusina.archive.binder.ArchiveTarget
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.DosarCalendar
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.withLock
import java.time.ZoneId

/**
 * Where an import writes and a backup reads, over the store: the archive's [ArchiveTarget].
 *
 * [snapshot] reads the binder in one read transaction ([BinderReading]). [apply] writes an
 * import everything or nothing, holding the store's write lock: the files first, each copied in
 * a piece at a time ([StoreFiles.keep]); then every row in one write transaction
 * ([BinderWriting]), this phone's lock choices last inside it (so a lock written for an import
 * that then fails is only ever a lock raised); then, whatever happened, the files no row names
 * any more go, the copies of a failed import with them.
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
) : ArchiveTarget {
    /** Runs inside the write transaction once every row is written, before the locks: how a test fails half way. */
    internal var beforeLocks: () -> Unit = {}

    override fun snapshot(): Binder = runBlocking {
        store.database.withReadTransaction { BinderReading(store.files, zone()).read(store.database, locks.read()) }
    }

    override fun apply(changes: BinderChanges) = runBlocking {
        store.writing.withLock {
            try {
                filesOf(changes).forEach(store.files::keep)
                store.database.withWriteTransaction {
                    BinderWriting(store.database, changes).write()
                    beforeLocks()
                    val next = (locks.read() + changes.locks).filterKeys { it !in changes.removed.templates }
                    locks.write(next)
                }
            } finally {
                store.files.keepOnly(store.database.withReadTransaction { store.database.files().named().toSet() })
            }
        }
    }

    private fun filesOf(changes: BinderChanges): List<StoredFile> =
        changes.written.assets.mapNotNull { it.photo } +
            changes.written.attachments.flatMap { listOfNotNull(it.file, it.thumbnail) + it.pages }
}
