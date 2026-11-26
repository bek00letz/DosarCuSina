package com.ar.dosarcusina.store.search

import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.RecordRef
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.ServiceItem

/**
 * Who points at whom in one view of the binder, read once: what search follows from a record to
 * the records that show it, both ways, without reading every table for each record.
 */
internal class BinderLinks(private val view: BinderView) {
    /** The categories by key; of two copies before they are joined, the first. */
    val templates: Map<String, CategoryTemplate> by lazy {
        view.all(Tables.templates).groupBy { it.key }.mapValues { (_, copies) -> copies.first() }
    }

    private val historyByAsset by lazy { view.all(Tables.history).groupBy { it.asset } }
    private val itemsByEntry by lazy { view.all(Tables.items).groupBy { it.entry } }
    private val itemsBySupplier by lazy { view.all(Tables.items).groupBy { it.supplier } }
    private val obligationsByAsset by lazy { view.all(Tables.obligations).groupBy { it.asset } }
    private val readingsByAsset by lazy { view.all(Tables.readings).groupBy { it.asset } }
    private val attachments by lazy { view.all(Tables.attachments) }
    private val attachmentsByAsset by lazy { attachments.groupBy { it.asset } }
    private val attachmentsByObligation by lazy { attachments.groupBy { it.obligation } }
    private val attachmentsByEntry by lazy { attachments.groupBy { it.historyEntry } }
    private val attachmentsByItem by lazy { attachments.groupBy { it.serviceItem } }
    private val attachmentsByReading by lazy { attachments.groupBy { it.measurement } }

    /** The firms by the sections they look after, and the records of history by who did them. */
    private val firmsByAsset by lazy {
        inverse(view.all(Tables.providers).associate { it.pk to view.linked(Tables.providerAssets, it.pk) })
    }
    private val recordsByFirm by lazy {
        inverse(view.all(Tables.history).associate { it.pk to view.linked(Tables.entryProviders, it.pk) })
    }

    fun recordsOf(asset: Long): List<HistoryEntry> = historyByAsset[asset].orEmpty()

    fun partsOf(entry: Long): List<ServiceItem> = itemsByEntry[entry].orEmpty()

    fun providerName(provider: Long?): String? = provider?.let { view.row(Tables.providers, it) }?.name

    /** Who did a record's work, by name, in order (the iOS app's `HistoryEntry.providerNames`). */
    fun providerNames(entry: Long): List<String> =
        view.linked(Tables.entryProviders, entry).mapNotNull { view.row(Tables.providers, it)?.name }.sorted()

    /** What shows a section: its deadlines and records, the firms that look after it, every document filed under it. */
    fun showingSection(asset: Long): Set<RecordRef> {
        val obligations = obligationsByAsset[asset].orEmpty()
        val entries = historyByAsset[asset].orEmpty()
        val items = entries.flatMap { partsOf(it.pk) }
        val papers = attachmentsByAsset[asset].orEmpty() +
            obligations.flatMap { attachmentsByObligation[it.pk].orEmpty() } +
            entries.flatMap { attachmentsByEntry[it.pk].orEmpty() } +
            items.flatMap { attachmentsByItem[it.pk].orEmpty() } +
            readingsByAsset[asset].orEmpty().flatMap { attachmentsByReading[it.pk].orEmpty() }
        val firms = firmsByAsset[asset].orEmpty().map { RecordRef(Tables.providers.type, it) }
        return refs(obligations) + refs(entries) + firms + refs(papers)
    }

    /** What shows a record of history: its section, its documents and its parts' documents. */
    fun showingRecord(entry: Long): Set<RecordRef> {
        val record = view.row(Tables.history, entry) ?: return emptySet()
        val papers = attachmentsByEntry[entry].orEmpty() + partsOf(entry).flatMap { attachmentsByItem[it.pk].orEmpty() }
        return listOfNotNull(record.asset?.let { RecordRef(Tables.assets.type, it) }).toSet() + refs(papers)
    }

    /** What shows a part: its documents, its record and the record's section (whose parts it lists). */
    fun showingPart(item: Long): Set<RecordRef> {
        val part = view.row(Tables.items, item) ?: return emptySet()
        val entry = part.entry?.let { view.row(Tables.history, it) }
        val holders = listOfNotNull(
            entry?.let { RecordRef(Tables.history.type, it.pk) },
            entry?.asset?.let { RecordRef(Tables.assets.type, it) },
        )
        return refs(attachmentsByItem[item].orEmpty()) + holders
    }

    /** What shows a firm's name: the records it did or supplied a part for, and their sections. */
    fun showingFirm(provider: Long): Set<RecordRef> {
        val rows = recordsByFirm[provider].orEmpty() + itemsBySupplier[provider].orEmpty().mapNotNull { it.entry }
        val entries = rows.distinct().mapNotNull { view.row(Tables.history, it) }
        return refs(entries) + entries.mapNotNull { it.asset }.map { RecordRef(Tables.assets.type, it) }
    }

    /** The documents of a deadline or a reading. */
    fun papersOf(obligation: Long? = null, reading: Long? = null): Set<RecordRef> = refs(
        obligation?.let { attachmentsByObligation[it] }.orEmpty() + reading?.let { attachmentsByReading[it] }.orEmpty(),
    )

}

private fun refs(records: List<Any>): Set<RecordRef> = records.mapTo(LinkedHashSet(), RecordRef::of)

/** Each target with the owners that link to it. */
private fun inverse(links: Map<Long, List<Long>>): Map<Long, List<Long>> =
    links.flatMap { (owner, targets) -> targets.map { it to owner } }.groupBy({ it.first }, { it.second })
