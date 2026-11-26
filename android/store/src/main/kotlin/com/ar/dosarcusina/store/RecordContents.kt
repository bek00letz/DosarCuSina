package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.HistoryEntry

/**
 * What a record holds and goes with it when the app deletes it, as the iOS app's
 * `RecordContents` (ios/DosarCuSina/Services/Persistence/RecordContents.swift): a section's
 * deadlines, documents (with their pages), records of history (with their parts) and readings;
 * a record of history's parts; a document's pages.
 *
 * The database never deletes these by itself: its links only let go (`ON DELETE SET NULL`). So
 * every deletion of a record goes through here, once, inside a step of the unit of work
 * ([Step.delete]), and takes what it holds; the step lets go of every link to what goes, the
 * links to many kept for it included ([com.ar.dosarcusina.store.schema.ProviderAssets],
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

    /** Deletes [record] and everything it holds ([owned]), the parts first, in [step]. */
    fun delete(step: Step, record: Any) {
        when (record) {
            is Asset -> {
                step.all(Tables.obligations).filter { it.asset == record.pk }.forEach(step::remove)
                step.all(Tables.attachments).filter { it.asset == record.pk }.forEach { delete(step, it) }
                step.all(Tables.history).filter { it.asset == record.pk }.forEach { delete(step, it) }
                step.all(Tables.readings).filter { it.asset == record.pk }.forEach(step::remove)
            }
            is HistoryEntry -> step.all(Tables.items).filter { it.entry == record.pk }.forEach(step::remove)
            is Attachment -> pagesOf(step, record).forEach(step::remove)
            else -> Unit
        }
        step.remove(record)
    }

    /**
     * Deletes [record]'s row alone, with what is no record of its own: a document's pages, which a
     * backup carries inside the document. What else it holds stays, its link let go: what an import
     * takes out goes this way, since it lists every record it takes out.
     */
    internal fun deleteRow(step: Step, record: Any) {
        if (record is Attachment) pagesOf(step, record).forEach(step::remove)
        step.remove(record)
    }

    private fun pagesOf(step: Step, document: Attachment) =
        step.all(Tables.pages).filter { it.attachment == document.pk }
}
