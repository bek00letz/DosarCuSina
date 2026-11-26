package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.BinderDatabase
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.IssuerLesson
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem

/**
 * What a record holds and goes with it when the app deletes it, as the iOS app's
 * `RecordContents` (ios/DosarCuSina/Services/Persistence/RecordContents.swift): a section's
 * deadlines, documents (with their pages), records of history (with their parts) and readings;
 * a record of history's parts; a document's pages.
 *
 * The database never deletes these by itself: its links only let go (`ON DELETE SET NULL`). So
 * every deletion of a record goes through here, once, inside the caller's transaction, and
 * takes what it holds, and the links to many kept for it ([com.ar.dosarcusina.store.schema.ProviderAssets],
 * [com.ar.dosarcusina.store.schema.HistoryEntryProviders]), which the database refuses to leave
 * pointing at nothing when the transaction ends.
 */
object RecordContents {
    /** What each kind of record holds, by the name of the iOS relationship: what [delete] takes with it. */
    val owned: Map<String, Set<String>> = mapOf(
        "Asset" to setOf("obligations", "attachments", "history", "measurements"),
        "HistoryEntry" to setOf("items"),
        "Attachment" to setOf("pages"),
    )

    /** Deletes [record] and everything it holds ([owned]), the parts first. Call it inside a write transaction. */
    suspend fun delete(database: BinderDatabase, record: Any) {
        when (record) {
            is Asset -> {
                database.obligations().ofAsset(record.pk).forEach { deleteRow(database, it) }
                database.attachments().ofAsset(record.pk).forEach { delete(database, it) }
                database.history().ofAsset(record.pk).forEach { delete(database, it) }
                database.readings().ofAsset(record.pk).forEach { deleteRow(database, it) }
            }
            is HistoryEntry -> database.items().ofEntry(record.pk).forEach { deleteRow(database, it) }
            else -> Unit
        }
        deleteRow(database, record)
    }

    /**
     * Deletes [record]'s row alone, with what is no record of its own: the links to many kept for
     * it, and a document's pages, which a backup carries inside the document. What else it holds
     * stays, its link let go: what an import takes out goes this way, since it lists every record
     * it takes out.
     */
    internal suspend fun deleteRow(database: BinderDatabase, record: Any) {
        when (record) {
            is Asset -> {
                database.providerAssets().deleteOfAsset(record.pk)
                database.assets().delete(record)
            }
            is HistoryEntry -> {
                database.entryProviders().deleteOfEntry(record.pk)
                database.history().delete(record)
            }
            is Attachment -> {
                database.pages().ofAttachment(record.pk).forEach { database.pages().delete(it) }
                database.attachments().delete(record)
            }
            is Provider -> {
                database.providerAssets().deleteOfProvider(record.pk)
                database.entryProviders().deleteOfProvider(record.pk)
                database.providers().delete(record)
            }
            is Obligation -> database.obligations().delete(record)
            is ServiceItem -> database.items().delete(record)
            is MeasurementLog -> database.readings().delete(record)
            is AttachmentPage -> database.pages().delete(record)
            is IssuerLesson -> database.lessons().delete(record)
            is CategoryTemplate -> database.templates().delete(record)
            else -> throw IllegalArgumentException("Not a record of the binder: ${record::class.simpleName}")
        }
    }
}
