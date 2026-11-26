package com.ar.dosarcusina.store.search

import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.history.HistoryItemSnapshot
import com.ar.dosarcusina.core.search.SearchComponent
import com.ar.dosarcusina.core.search.SearchDeadline
import com.ar.dosarcusina.core.search.SearchDocument
import com.ar.dosarcusina.core.search.SearchEntries
import com.ar.dosarcusina.core.search.SearchFact
import com.ar.dosarcusina.core.search.SearchFirm
import com.ar.dosarcusina.core.search.SearchPaper
import com.ar.dosarcusina.core.search.SearchRecord
import com.ar.dosarcusina.core.search.SearchSection
import com.ar.dosarcusina.core.search.SearchValue
import com.ar.dosarcusina.core.search.SearchWording
import com.ar.dosarcusina.core.text.PaymentCardNumbers.KeptWhole
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.FreeText
import com.ar.dosarcusina.store.RecordRef
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.locks.BinderLocks
import com.ar.dosarcusina.store.locks.DocumentSections
import com.ar.dosarcusina.store.locks.isLocked
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.documentDay
import com.ar.dosarcusina.store.schema.dueDay
import com.ar.dosarcusina.store.schema.keptComponents
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import java.time.ZoneId

/**
 * The app's words for what search shows: [SearchWording], and a section's value as the app shows it
 * (the iOS app's `FieldFormatter.display`: a choice's label, a plate as "B-123-ABC", an amount in
 * lei, a day in words, a sealed value masked). The seam to the wording (Phase 4); the index and
 * the row read the same one.
 */
interface BinderSearchWording : SearchWording {
    fun shown(value: FieldValue, field: FieldDefinition): String
}

/**
 * The search index's documents read from the binder, as the iOS app's `SearchIndexBuilder`
 * (ios/DosarCuSina/Services/Search/SearchIndexBuilder.swift): assets with their field values and
 * the parts their records follow, deadlines, records of history, firms and their trades, documents
 * with their text. What each record gives is [SearchEntries]'s; this reads the records into it, from
 * one view of the binder ([view], a snapshot), with each section's lock from [locks], the one answer
 * for every category a section names.
 *
 * The index is kept per record: [documents] gives one record's documents, [recordsShowing] the
 * records to read again when one changes.
 */
// One reader for each kind of record, beside the three questions the indexer asks.
@Suppress("TooManyFunctions")
class BinderSearch(
    private val view: BinderView,
    private val locks: BinderLocks,
    private val wording: BinderSearchWording,
    private val zone: ZoneId = DosarCalendar.zone(),
) {
    private val entries = SearchEntries(wording, zone)
    private val links by lazy { BinderLinks(view) }
    private val documentSections by lazy {
        DocumentSections(
            view.all(Tables.assets), view.all(Tables.obligations), view.all(Tables.history),
            view.all(Tables.items), view.all(Tables.readings),
        )
    }

    /** Every record's documents, keyed by the record they come from. */
    fun buildByRecord(): Map<RecordRef, List<SearchDocument>> {
        val result = LinkedHashMap<RecordRef, List<SearchDocument>>()
        for (asset in view.all(Tables.assets)) result[ref(asset)] = entries.section(section(asset))
        for (row in view.all(Tables.obligations)) result[ref(row)] = listOf(entries.deadline(deadline(row)))
        for (entry in view.all(Tables.history)) result[ref(entry)] = listOf(entries.record(record(entry)))
        for (provider in view.all(Tables.providers)) result[ref(provider)] = listOf(entries.firm(firm(provider)))
        for (row in view.all(Tables.attachments)) result[ref(row)] = listOf(entries.paper(paper(row)))
        return result
    }

    /** One record's documents: a section with its parts, or a deadline, record, firm or document; none once gone. */
    fun documents(forRecord: RecordRef): List<SearchDocument> = when (forRecord.type) {
        Tables.assets.type -> view.row(Tables.assets, forRecord.row)?.let { entries.section(section(it)) }
        Tables.obligations.type ->
            view.row(Tables.obligations, forRecord.row)?.let { listOf(entries.deadline(deadline(it))) }
        Tables.history.type -> view.row(Tables.history, forRecord.row)?.let { listOf(entries.record(record(it))) }
        Tables.providers.type -> view.row(Tables.providers, forRecord.row)?.let { listOf(entries.firm(firm(it))) }
        Tables.attachments.type -> view.row(Tables.attachments, forRecord.row)?.let { listOf(entries.paper(paper(it))) }
        else -> null
    }.orEmpty()

    /**
     * The records whose documents show something of a changed record: itself, and those that print
     * its name, take its lock or list it. Null when the change can reach any record (a category's
     * name, fields or lock), so everything is read again.
     */
    fun recordsShowing(changed: RecordRef): Set<RecordRef>? = when (changed.type) {
        Tables.templates.type -> null
        Tables.assets.type -> setOf(changed) + links.showingSection(changed.row)
        Tables.obligations.type -> setOf(changed) + links.papersOf(obligation = changed.row)
        Tables.history.type -> setOf(changed) + links.showingRecord(changed.row)
        Tables.items.type -> links.showingPart(changed.row)
        Tables.providers.type -> setOf(changed) + links.showingFirm(changed.row)
        Tables.readings.type -> links.papersOf(reading = changed.row)
        Tables.attachments.type -> setOf(changed)
        else -> emptySet()
    }

    // Reading the records

    private fun template(key: String): CategoryTemplate? = links.templates[key]

    private fun isLocked(section: Asset?): Boolean = section?.let { locks.isLocked(it.templateKey) } ?: false

    private fun kept(section: Asset?): KeptWhole = section?.let { FreeText.keptWhole(it, view) } ?: KeptWhole.NOTHING

    private fun section(asset: Asset): SearchSection {
        val template = template(asset.templateKey)
        val fields = template?.keptSections?.items.orEmpty().flatMap { it.fields }
        val values = asset.keptValues.value
        return SearchSection(
            id = asset.id,
            name = asset.name,
            categoryName = template?.name,
            values = fields.mapNotNull { field -> values[field.key]?.let { value(field, it) } },
            facts = asset.keptFacts.items.map { SearchFact(it.label, it.value, it.isSensitive, it.isSecret) },
            notes = asset.notes,
            updatedAt = asset.updatedAt,
            isLocked = isLocked(asset),
            keptWhole = kept(asset),
            components = template?.keptComponents?.items.orEmpty().map {
                SearchComponent(it.key, it.name, it.group, it.synonyms)
            },
            parts = links.recordsOf(asset.pk).flatMap { entry ->
                val names = links.providerNames(entry.pk)
                links.partsOf(entry.pk).map { item ->
                    HistoryItemSnapshot(
                        componentKey = item.componentKey, name = item.name,
                        entryId = entry.id, occurredAt = entry.occurredAt,
                        partBrandOrCode = item.partBrandOrCode, supplierName = links.providerName(item.supplier),
                        providerNames = names,
                    )
                }
            },
        )
    }

    private fun value(field: FieldDefinition, value: FieldValue) = SearchValue(
        label = field.label, type = field.type, role = field.role, isSensitive = field.isSensitive,
        text = value.textValue, shown = wording.shown(value, field), isNumber = value is FieldValue.Number,
    )

    private fun deadline(obligation: Obligation): SearchDeadline {
        val section = obligation.asset?.let { view.row(Tables.assets, it) }
        return SearchDeadline(
            id = obligation.id, title = obligation.title,
            reference = obligation.reference, provider = obligation.provider,
            notes = obligation.notes, dueDay = obligation.dueDay ?: DosarCalendar.day(obligation.createdAt, zone),
            sectionName = section?.name, isLocked = isLocked(section), keptWhole = kept(section),
        )
    }

    private fun record(entry: HistoryEntry): SearchRecord {
        val section = entry.asset?.let { view.row(Tables.assets, it) }
        return SearchRecord(
            id = entry.id, title = entry.title, occurredAt = entry.occurredAt, sectionName = section?.name,
            items = links.partsOf(entry.pk).map {
                SearchRecord.Item(it.name, it.partBrandOrCode, links.providerName(it.supplier))
            },
            providerNames = links.providerNames(entry.pk), note = entry.note, reference = entry.reference,
            isLocked = isLocked(section), keptWhole = kept(section),
        )
    }

    // A locked section is never named in a firm's result: only the open ones it looks after.
    private fun firm(provider: Provider) = SearchFirm(
        id = provider.id, name = provider.name, trades = provider.trades, phone = provider.phone,
        sectionNames = view.linked(Tables.providerAssets, provider.pk)
            .mapNotNull { view.row(Tables.assets, it) }
            .filterNot { isLocked(it) }
            .map { it.name },
        address = provider.address, notes = provider.notes, updatedAt = provider.updatedAt,
    )

    private fun paper(attachment: Attachment): SearchPaper {
        val section = FreeText.section(attachment, view)?.let { view.row(Tables.assets, it) }
        return SearchPaper(
            id = attachment.id, title = attachment.title, fileName = attachment.fileName, sectionName = section?.name,
            isArchived = attachment.isArchived, extractedText = attachment.extractedText,
            isIdentity = attachment.kindRaw == IDENTITY, documentDay = attachment.documentDay,
            createdAt = attachment.createdAt, isLocked = locks.isLocked(attachment, documentSections),
            keptWhole = kept(section),
        )
    }

    private companion object {
        /** `DocumentKind.identity`: a document read off an identity paper, whose text is never searched. */
        const val IDENTITY = "identity"

        fun ref(record: Any): RecordRef = RecordRef.of(record)
    }
}
