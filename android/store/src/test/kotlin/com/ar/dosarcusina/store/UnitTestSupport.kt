package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.MemoryFile
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.locks.CategoryLocks
import com.ar.dosarcusina.store.locks.SectionLocks
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.ServiceItem
import kotlinx.coroutines.runBlocking
import java.time.Instant

/** Noon in Bucharest on [day], as the iOS tests' `noon`. */
fun noon(day: String): Instant = Instant.parse("${day}T10:00:00Z")

/** A persistence log that keeps what is written, for a test to read. */
class RecordingLog : PersistenceLog {
    val entries = mutableListOf<PersistenceLog.Entry>()

    override fun write(entry: PersistenceLog.Entry) {
        entries += entry
    }
}

/** A store in memory with its unit of work, this phone's locks by the real rules, and a log a test reads. */
class TestBinderStore(
    /** The moment a step without a clock of its own saves at. */
    var now: Instant = noon("2026-11-26"),
    sectionLocks: SectionLocks = SectionLocks(file = null),
) {
    val store: BinderStore = scratchStore(sectionLocks)
    val locks = CategoryLocks(store.locks, Catalog.builtIn)
    val log = RecordingLog()
    val undoRoot = scratchFolder("undo-")
    val unit = UnitOfWork(store, locks, log, clock = { now }, undoRoot = undoRoot)

    /** The binder as stored now, read in one transaction. */
    fun snapshot(): BinderSnapshot = runBlocking { BinderSnapshot.read(store.database) }

    /** Every record's state as stored now: what is really saved. */
    fun database(): Map<RecordRef, RecordState> = snapshot().states()

    /** The record of [table] in [row], as stored now. */
    fun <R : Any> stored(table: Table<R>, row: Long): R? = snapshot().row(table, row)

    fun <R : Any> stored(record: R): R = requireNotNull(stored(Tables.of(record), Tables.of(record).rowOf(record)))
}

/** The records that differ between two states of the binder, with the properties that do. */
fun differences(a: Map<RecordRef, RecordState>, b: Map<RecordRef, RecordState>): Map<RecordRef, Set<String>> =
    (a.keys + b.keys).mapNotNull { ref ->
        val left = a[ref]
        val right = b[ref]
        if (left == null || right == null) return@mapNotNull ref to emptySet<String>()
        left.changed(from = right).takeIf { it.isNotEmpty() }?.let { ref to it }
    }.toMap()

/** Every picture and file in a state of the binder, where it is: its record, its property and its digest. */
fun filePlaces(database: Map<RecordRef, RecordState>): Set<Triple<RecordRef, String, String>> =
    database.values.flatMapTo(mutableSetOf()) { state ->
        state.values.mapNotNull { (name, value) ->
            (value as? StoredValue.File)?.digest?.let { Triple(state.ref, name, it) }
        }
    }

/** A file of a few bytes, as a page's picture. */
fun picture(vararg bytes: Int): MemoryFile = MemoryFile(ByteArray(bytes.size) { bytes[it].toByte() })

/**
 * A car with a visit, a line item, a reading and a document with one page, saved with an old
 * change time each, as a backup's writer keeps the times it carries (the iOS tests' `Records`).
 */
class Records(val binder: TestBinderStore, val car: Asset, val visit: HistoryEntry, val item: ServiceItem,
    val reading: MeasurementLog, val document: Attachment, val page: AttachmentPage) {
    val unit: UnitOfWork get() = binder.unit

    /** Each record as stored now. */
    val storedCar: Asset get() = binder.stored(car)
    val storedVisit: HistoryEntry get() = binder.stored(visit)
    val storedItem: ServiceItem get() = binder.stored(item)
    val storedReading: MeasurementLog get() = binder.stored(reading)
    val storedDocument: Attachment get() = binder.stored(document)
    val storedPage: AttachmentPage get() = binder.stored(page)

    companion object {
        fun make(
            at: Instant,
            binder: TestBinderStore = TestBinderStore(),
        ): Records = binder.unit.performPrivate { step ->
            val car = step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle", updatedAt = at))
            val visit = step.insert(HistoryEntry(
                kindRaw = "visit",
                title = "Revizie",
                occurredAt = at,
                asset = car.pk,
                updatedAt = at,
            ))
            val item = step.insert(ServiceItem(name = "Filtru ulei", entry = visit.pk, updatedAt = at))
            val reading = step.insert(MeasurementLog(
                kindRaw = "odometer",
                value = 100_000.0,
                recordedAt = at,
                asset = car.pk,
                updatedAt = at,
            ))
            val document = step.insert(
                Attachment(
                    fileName = "factura.heic",
                    contentType = "public.heic",
                    kindRaw = "invoice",
                    asset = car.pk,
                    updatedAt = at,
                ),
            )
            val page = step.insert(AttachmentPage(
                index = 0,
                imageData = step.keep(picture(1, 2, 3)),
                attachment = document.pk,
            ))
            Records(binder, car, visit, item, reading, document, page)
        }
    }
}
