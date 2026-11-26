package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.ServiceItem
import java.util.UUID

/**
 * Each record a section, a record of history or a document holds keeps the id of the one that
 * holds it beside its link, as the iOS app's `ParentLinks`
 * (ios/DosarCuSina/Services/Persistence/ParentLinks.swift): `Obligation.assetID`,
 * `Attachment.assetID`, `HistoryEntry.assetID`, `MeasurementLog.assetID`, `ServiceItem.entryID`,
 * `AttachmentPage.attachmentID`. A link is a row, which lets go when the row goes; the id stays,
 * so a record left without what held it can go back to a copy of it ([rehome]).
 *
 * Pure: the caller reads the rows and writes what these give back, in its own transaction.
 */
object ParentLinks {
    /** The names of the ids, in every model that has one. */
    val idNames: Set<String> = setOf("assetID", "entryID", "attachmentID")

    /** The id of the record a row is: what [stamp] writes from a link. */
    fun interface IdOfRow {
        fun id(row: Long): UUID?
    }

    // Stamping: every save writes the id of what holds a record from its link, before change
    // times and undo read the step, so an id is never a change of its own.

    fun stamp(record: Obligation, assets: IdOfRow): Obligation =
        follow(record.assetID, record.asset, assets)?.let { record.copy(assetID = it.value) } ?: record

    fun stamp(record: Attachment, assets: IdOfRow): Attachment =
        follow(record.assetID, record.asset, assets)?.let { record.copy(assetID = it.value) } ?: record

    fun stamp(record: HistoryEntry, assets: IdOfRow): HistoryEntry =
        follow(record.assetID, record.asset, assets)?.let { record.copy(assetID = it.value) } ?: record

    fun stamp(record: MeasurementLog, assets: IdOfRow): MeasurementLog =
        follow(record.assetID, record.asset, assets)?.let { record.copy(assetID = it.value) } ?: record

    fun stamp(record: ServiceItem, entries: IdOfRow): ServiceItem =
        follow(record.entryID, record.entry, entries)?.let { record.copy(entryID = it.value) } ?: record

    fun stamp(record: AttachmentPage, attachments: IdOfRow): AttachmentPage =
        follow(record.attachmentID, record.attachment, attachments)
            ?.let { record.copy(attachmentID = it.value) } ?: record

    /** The id to write when it isn't the one the link names (none for no link), or null when it already is. */
    private fun follow(id: UUID?, link: Long?, ids: IdOfRow): Holder? {
        val linked = link?.let(ids::id)
        return if (linked == id) null else Holder(linked)
    }

    private class Holder(val value: UUID?)

    // Left without what held them

    /** The row of a record with an id here, if there is one. */
    fun interface RowOfId {
        fun row(id: UUID): Long?
    }

    /** Every record whose link let go while its id still names what held it, and what it goes back to. */
    data class Held(
        val obligations: List<Obligation> = emptyList(),
        val attachments: List<Attachment> = emptyList(),
        val history: List<HistoryEntry> = emptyList(),
        val readings: List<MeasurementLog> = emptyList(),
        val items: List<ServiceItem> = emptyList(),
        val pages: List<AttachmentPage> = emptyList(),
    ) {
        val isEmpty: Boolean
            get() = obligations.isEmpty() && attachments.isEmpty() && history.isEmpty() &&
                readings.isEmpty() && items.isEmpty() && pages.isEmpty()

        /** Only the records left without what held them: no link, and an id that names it. */
        fun loose(): Held = Held(
            obligations = obligations.filter { it.asset == null && it.assetID != null },
            attachments = attachments.filter { it.asset == null && it.assetID != null },
            history = history.filter { it.asset == null && it.assetID != null },
            readings = readings.filter { it.asset == null && it.assetID != null },
            items = items.filter { it.entry == null && it.entryID != null },
            pages = pages.filter { it.attachment == null && it.attachmentID != null },
        )
    }

    /**
     * Puts back every record of [records] left without what held it whose holder is here by its
     * id ([assets], [entries], [attachments]: the row of the copy with that id), and gives only
     * the records it put back, to be saved as the app's own step (no change time: the link is
     * what the person last saw). Run at launch and after every change that came from elsewhere,
     * before copies meet (`RecordsMeet`). A record whose holder isn't here stays as it is, for
     * the repair list (`LostRecordsStep`).
     */
    fun rehome(records: Held, assets: RowOfId, entries: RowOfId, attachments: RowOfId): Held {
        val loose = records.loose()
        return Held(
            obligations = loose.obligations.mapNotNull { r -> r.assetID?.let(assets::row)?.let { r.copy(asset = it) } },
            attachments = loose.attachments.mapNotNull { r -> r.assetID?.let(assets::row)?.let { r.copy(asset = it) } },
            history = loose.history.mapNotNull { r -> r.assetID?.let(assets::row)?.let { r.copy(asset = it) } },
            readings = loose.readings.mapNotNull { r -> r.assetID?.let(assets::row)?.let { r.copy(asset = it) } },
            items = loose.items.mapNotNull { r -> r.entryID?.let(entries::row)?.let { r.copy(entry = it) } },
            pages = loose.pages.mapNotNull { r ->
                r.attachmentID?.let(attachments::row)?.let { r.copy(attachment = it) }
            },
        )
    }
}
