package com.ar.dosarcusina.store.search

import com.ar.dosarcusina.core.search.SearchIndex
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.store.BinderSnapshot
import com.ar.dosarcusina.store.BinderStore
import com.ar.dosarcusina.store.RecordRef
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.locks.BinderLocks
import com.ar.dosarcusina.store.locks.CategoryLocks
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.ZoneId

/**
 * What one save changed, as the iOS app's `SearchChanges`: the records it made or wrote again
 * ([changed]), those it deleted ([deleted]), or that it can't say ([everything]): then everything is
 * read again. A lock chosen on this phone is a change of [everything] too: every entry says again
 * whether it is locked.
 */
data class SearchChanges(
    val changed: Set<RecordRef> = emptySet(),
    val deleted: Set<RecordRef> = emptySet(),
    val everything: Boolean = false,
) {
    val isEmpty: Boolean get() = changed.isEmpty() && deleted.isEmpty() && !everything
}

/**
 * Keeps Caută's index in step with the binder, as the iOS app's `SearchIndexer`
 * (ios/DosarCuSina/Services/Search/SearchIndexer.swift). The first look reads every record; after
 * that, a save reads again only the records it changed and those that show them
 * ([BinderSearch.recordsShowing]). A change to a category, or a save that can't say what it
 * changed, reads everything. One pass at a time; saves made while it reads wait their turn.
 *
 * Each pass reads the binder as stored ([BinderSnapshot]) and the locks as this phone has them now
 * ([BinderLocks], the one answer for every category a section names).
 */
class SearchIndexer(
    private val store: BinderStore,
    private val locks: CategoryLocks,
    private val wording: BinderSearchWording,
    /** The time zone days are counted in, read each pass: the app's calendar's. */
    private val zone: () -> ZoneId = DosarCalendar::zone,
) {
    private val passes = Mutex()

    /** Which documents each record gave, to take them out when it changes. */
    private val documentIds = HashMap<RecordRef, List<String>>()
    private var index: SearchIndex? = null

    /** How many records the last pass read, for tests: everything, or only what changed. */
    @Volatile
    var lastRecordsRead: Int = 0
        private set

    /** The index, read in full the first time. */
    suspend fun current(): SearchIndex = passes.withLock { index ?: rebuilt() }

    /** Reads every record again. */
    suspend fun rebuild(): SearchIndex = passes.withLock { rebuilt() }

    /** Brings the index up to date with one save, reading only what it touched. */
    suspend fun apply(changes: SearchChanges): SearchIndex = passes.withLock {
        val current = index
        when {
            current == null || changes.everything -> rebuilt()
            changes.isEmpty -> current
            else -> updated(current, changes) ?: rebuilt()
        }
    }

    /** The index after [changes], or null when they can reach every record. */
    private suspend fun updated(current: SearchIndex, changes: SearchChanges): SearchIndex? {
        if (changes.deleted.any { it.type == Tables.templates.type }) return null
        val search = read()
        val records = LinkedHashSet<RecordRef>()
        for (changed in changes.changed - changes.deleted) records += search.recordsShowing(changed) ?: return null
        val removing = HashSet<String>()
        for (deleted in changes.deleted) removing += documentIds.remove(deleted).orEmpty()
        val adding = records.flatMap { record ->
            removing += documentIds[record].orEmpty()
            search.documents(record).also { documents ->
                if (documents.isEmpty()) documentIds.remove(record) else documentIds[record] = documents.map { it.id }
            }
        }
        lastRecordsRead = records.size
        return current.updating(removing, adding).also { index = it }
    }

    private suspend fun rebuilt(): SearchIndex {
        val byRecord = read().buildByRecord()
        documentIds.clear()
        for ((record, documents) in byRecord) documentIds[record] = documents.map { it.id }
        lastRecordsRead = byRecord.size
        return SearchIndex(byRecord.values.flatten(), wording).also { index = it }
    }

    private suspend fun read(): BinderSearch {
        val snapshot = BinderSnapshot.read(store.database)
        val named = snapshot.all(Tables.assets).map { it.templateKey }
        val binderLocks = BinderLocks.of(snapshot.all(Tables.templates), named, locks)
        return BinderSearch(snapshot, binderLocks, wording, zone())
    }
}
