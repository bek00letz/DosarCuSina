package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.ServiceItem
import java.util.UUID

/**
 * Whether [section]'s category is locked on this phone (the one answer,
 * [CategoryLocks.isSensitive]), given its category's record when the caller has it: the iOS app's
 * `Asset.isSensitive(template:)`.
 */
fun CategoryLocks.isSensitive(section: Asset, template: CategoryTemplate?): Boolean =
    isSensitive(section.templateKey, template)

/** The same answer, from the categories by key: the iOS app's `Asset.isSensitive(among:)`. */
fun CategoryLocks.isSensitive(section: Asset, among: Map<String, CategoryTemplate>): Boolean =
    isSensitive(section.templateKey, among)

/**
 * Whether the deadline [deadline] is locked on this phone, read now: its section's answer. A
 * deadline of the whole household has no section, so no lock. What closing it asks, never a copy
 * kept from earlier.
 */
fun CategoryLocks.isSensitive(
    deadline: Obligation,
    sections: Map<Long, Asset>,
    among: Map<String, CategoryTemplate>,
): Boolean = deadline.asset?.let(sections::get)?.let { isSensitive(it, among) } ?: false

/**
 * The lock a document's page is drawn behind: the pure part of the iOS app's `RouteLock`, which the
 * app's routes take on (Phase 6).
 */
sealed interface DocumentLock {
    /** Nothing of a section: a paper of the whole household's. */
    data object Open : DocumentLock

    /** Behind the lock of the section [id]. */
    data class Section(val id: UUID) : DocumentLock

    /** It names nothing that can be found: locked while anything of the binder is (locks fail closed). */
    data object UnknownSection : DocumentLock
}

/**
 * The sections documents belong to, from the binder's rows as a screen holds them: the iOS app's
 * `Attachment.sections`. Each row is found by the link the database keeps (its `pk`).
 */
class DocumentSections(
    assets: List<Asset>,
    obligations: List<Obligation>,
    entries: List<HistoryEntry>,
    items: List<ServiceItem>,
    readings: List<MeasurementLog>,
) {
    private val assets = assets.associateBy { it.pk }
    private val obligations = obligations.associateBy { it.pk }
    private val entries = entries.associateBy { it.pk }
    private val items = items.associateBy { it.pk }
    private val readings = readings.associateBy { it.pk }

    /**
     * Every section [document] belongs to, each once: its own, its deadline's, its record's in
     * Istoric (a visit's invoice, a bill), its part's record's and its reading's.
     */
    fun of(document: Attachment): List<Asset> {
        val entryOfPart = document.serviceItem?.let(items::get)?.entry?.let(entries::get)
        val candidates = listOf(
            document.asset,
            document.obligation?.let(obligations::get)?.asset,
            document.historyEntry?.let(entries::get)?.asset,
            entryOfPart?.asset,
            document.measurement?.let(readings::get)?.asset,
        )
        return candidates.mapNotNull { it?.let(assets::get) }.distinctBy { it.id }
    }

    /** Whether [document] is a paper of the whole household's: a household deadline's or record's. */
    fun belongsToTheHousehold(document: Attachment): Boolean =
        document.obligation?.let(obligations::get) != null || document.historyEntry?.let(entries::get) != null

    /**
     * The lock [document]'s page is drawn behind, each section answered by [isLocked]: a section
     * that is locked if it has one, else its first section; a paper of the whole household's is
     * open, one that names nothing that can be found is [DocumentLock.UnknownSection]. The one rule
     * behind [CategoryLocks.lock] and [BinderLocks.lock].
     */
    internal fun lock(document: Attachment, isLocked: (Asset) -> Boolean): DocumentLock {
        val belongs = of(document)
        val section = belongs.firstOrNull(isLocked) ?: belongs.firstOrNull()
        return when {
            section != null -> DocumentLock.Section(section.id)
            belongsToTheHousehold(document) -> DocumentLock.Open
            else -> DocumentLock.UnknownSection
        }
    }
}

/**
 * The lock [document]'s page is drawn behind, by the one answer for each section it belongs to: a
 * section whose category is locked if it has one (so the page is locked if any of them is), else its
 * first section. A document of the whole household's is open; one that names nothing that can be
 * found is [DocumentLock.UnknownSection]. The iOS app's `Attachment.lock(among:)`.
 */
fun CategoryLocks.lock(
    document: Attachment,
    sections: DocumentSections,
    among: Map<String, CategoryTemplate>,
): DocumentLock = sections.lock(document) { isSensitive(it, among) }

/** The same lock, each section answered by the whole binder's locks (what search reads, [BinderLocks.isLocked]). */
fun BinderLocks.lock(document: Attachment, sections: DocumentSections): DocumentLock =
    sections.lock(document) { isLocked(it.templateKey) }

/**
 * Whether [document] is locked on this phone where it is named away from its page (search), by the
 * lock its page is drawn behind ([lock]): locked when any section it belongs to is; a paper of the
 * whole household's is open; one that names nothing that can be found is locked while anything of
 * the binder is (locks fail closed). The iOS app's `Attachment.isSensitive(among:binder:)`.
 */
fun BinderLocks.isLocked(document: Attachment, sections: DocumentSections): Boolean =
    when (val lock = lock(document, sections)) {
        DocumentLock.Open -> false
        is DocumentLock.Section ->
            sections.of(document).firstOrNull { it.id == lock.id }?.let { isLocked(it.templateKey) } ?: true
        DocumentLock.UnknownSection -> anySectionLocked
    }
