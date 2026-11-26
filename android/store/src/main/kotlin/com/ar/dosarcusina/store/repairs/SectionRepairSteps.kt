package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.FirmCopies
import com.ar.dosarcusina.archive.ProviderTaxID
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.CategoryParts
import com.ar.dosarcusina.catalog.SectionPocket
import com.ar.dosarcusina.core.search.SearchText
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.ParentLinks
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.sections.Making
import com.ar.dosarcusina.store.sections.SectionMaking
import com.ar.dosarcusina.store.sections.SectionPlaces
import com.ar.dosarcusina.store.templates.TemplateStore
import com.ar.dosarcusina.store.templates.behavior
import java.util.UUID

// The repairs that wait on sections and firms, as the iOS app's SectionsIntoTheirHomeStep.swift,
// LostRecordsStep.swift and DataRepairSteps.swift's DuplicateProvidersStep (with
// CaptureRepairs.duplicateProviderCandidates and mergeDuplicateProviders).

/**
 * Sections standing on their own that can be filed under the household's only section of the part
 * their category may belong to (plants kept before they could stand in a home, a category of one's
 * own that now says "Ține de…"), as the iOS app's `SectionsIntoTheirHomeStep`. Only a category that
 * goes under the only one by itself (`goesUnderTheOnlyOne`); with several of that part nothing is
 * guessed, one note says to move them with "Mută la…"; with none there is nothing to offer.
 * Examples are left as they are. Nothing was saved wrongly, so its findings are suggestions.
 */
object SectionsIntoTheirHomeStep : DataRepairStep {
    override val id = DataRepairStepId.SECTIONS_INTO_THEIR_HOME
    override val group = DataRepairGroup.BELONGS_TO_ANOTHER_SECTION
    override val isSuggestion = true
    override val applyVerb = ApplyVerb.MOVE

    /** A category whose sections go under the only one, those on their own, and where they could go. */
    private class Candidates(val category: CategoryTemplate, val sections: List<Asset>, val parents: List<Asset>)

    private fun candidates(view: BinderView): List<Candidates> {
        val categories = SectionPlaces.categories(view).values
            .filter { it.behavior.goesUnderTheOnlyOne && it.behavior.mayBelongTo != null }
            .sortedBy { it.key }
        val assets = view.all(Tables.assets)
        return categories.mapNotNull { category ->
            val sections = assets.filter { it.templateKey == category.key && it.parent == null && !it.isExample }
                .sortedBy { it.name }
            val parents = SectionPlaces.possibleParents(view, category.behavior)
            if (sections.isEmpty() || parents.isEmpty()) null else Candidates(category, sections, parents)
        }
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> = candidates(scan.view).flatMap { found ->
        val role = requireNotNull(found.category.behavior.mayBelongTo)
        val home = found.parents.singleOrNull()
        if (home == null) {
            // Several: which one is the person's to say.
            val subject = DataRepairSubject.IntoHome(null, null, role, null, null, found.category.name)
            val findingId = DataRepairFinding.id(id, found.category.key, "several")
            listOf(DataRepairFinding(findingId, id, subject, isFixable = false))
        } else {
            found.sections.map { section ->
                val subject = DataRepairSubject.IntoHome(
                    section.id, home.id, role, section.name, home.name, found.category.name,
                )
                DataRepairFinding(
                    DataRepairFinding.id(id, RepairReading.key(section.id), RepairReading.key(home.id)), id, subject,
                )
            }
        }
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNullTo(mutableSetOf()) { (it.subject as? DataRepairSubject.IntoHome)?.assetId }
        // Checked again: still on its own, and the home still the only one.
        for (found in candidates(step)) {
            val home = found.parents.singleOrNull() ?: continue
            for (section in found.sections) {
                if (section.id in approved && SectionPlaces.canFile(step, section, home)) {
                    step.update(section.copy(parent = home.pk))
                }
            }
        }
    }
}

/**
 * A deadline, a document, a record of history or a reading added to a section while another device
 * deleted it: its link let go, its id still names the section ([ParentLinks]). With no copy of the
 * section here to go back to, each is offered to be kept in a section of its own, „Recuperate”, or
 * left as it is, as the iOS app's `LostRecordsStep`. The section's lock isn't known any more, so
 * nothing of the record is named. „Recuperate” is a category of one's own with one key and one
 * section with one id on every device and on both apps (`ownCategories.json`, `recovered`), made
 * locked while any section is locked here. A part of a record of history or a page of a document
 * whose record was deleted is never offered. On Android nothing arrives from elsewhere yet, so the
 * binder is always whole (`CloudArrival`).
 */
object LostRecordsStep : DataRepairStep {
    override val id = DataRepairStepId.LOST_RECORDS
    override val group = DataRepairGroup.LOST_RECORDS
    override val applyVerb = ApplyVerb.KEEP

    /** What kind of record was left without its section. */
    enum class Kind(val raw: String) {
        DEADLINE("deadline"),
        DOCUMENT("document"),
        HISTORY("history"),
        READING("reading"),
    }

    /** One record left without its section. */
    data class Lost(val kind: Kind, val id: UUID)

    /** The records left without their section, by kind, then by id. */
    fun lost(view: BinderView): List<Lost> {
        val loose = ParentLinks.Held(
            obligations = view.all(Tables.obligations),
            attachments = view.all(Tables.attachments),
            history = view.all(Tables.history),
            readings = view.all(Tables.readings),
        ).loose()
        val records = loose.obligations.map { Lost(Kind.DEADLINE, it.id) } +
            loose.attachments.map { Lost(Kind.DOCUMENT, it.id) } +
            loose.history.map { Lost(Kind.HISTORY, it.id) } +
            loose.readings.map { Lost(Kind.READING, it.id) }
        return records.sortedWith(compareBy({ it.kind.raw }, { RepairReading.key(it.id) }))
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> = lost(scan.view).map { lost ->
        DataRepairFinding(
            DataRepairFinding.id(id, RepairReading.key(lost.id)), id, DataRepairSubject.LostRecord(lost.kind, lost.id),
        )
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val still = lost(step).toSet()
        val approved = findings.mapNotNull { finding ->
            (finding.subject as? DataRepairSubject.LostRecord)?.let { Lost(it.kind, it.id) }?.takeIf { it in still }
        }
        if (approved.isEmpty()) return
        val section = section(step, context).pk
        for (lost in approved) {
            when (lost.kind) {
                Kind.DEADLINE -> step.all(Tables.obligations).firstOrNull { it.id == lost.id }
                    ?.let { step.update(it.copy(asset = section)) }
                Kind.DOCUMENT -> step.all(Tables.attachments).firstOrNull { it.id == lost.id }
                    ?.let { step.update(it.copy(asset = section)) }
                Kind.HISTORY -> step.all(Tables.history).firstOrNull { it.id == lost.id }
                    ?.let { step.update(it.copy(asset = section)) }
                Kind.READING -> step.all(Tables.readings).firstOrNull { it.id == lost.id }
                    ?.let { step.update(it.copy(asset = section)) }
            }
        }
    }

    /** „Recuperate”'s section, made with its category the first time. */
    private fun section(step: Step, context: DataRepairContext): Asset {
        val recovered = Catalog.builtIn.ownCategories.recovered
        step.all(Tables.assets).firstOrNull { it.id == recovered.sectionID }?.let { return it }
        val locked = context.locks.binder(step.all(Tables.templates), step.all(Tables.assets).map { it.templateKey })
        val template = SectionPlaces.categories(step)[recovered.key] ?: TemplateStore.makeCustom(
            step, recovered.key, recovered.name, recovered.symbol, TemplateStore.DEFAULT_TINT,
            CategoryParts(pockets = SectionPocket.orderedRaw(recovered.pockets)), locked.anySectionLocked, context.now,
        )
        val making = Making(recovered.name, template, FieldValues(), null, emptyList(), false, recovered.sectionID)
        return SectionMaking.make(step, making, null, context.now, context.zone, Catalog.builtIn)
    }
}

/**
 * The same firm kept twice (the visit form and capture each made one), as the iOS app's
 * `DuplicateProvidersStep`: firms that are the same by `ProviderActions.findOrCreate`'s rule, the
 * same CUI or names that read the same, a chain counting as one group, are offered to be joined into
 * the one kept first. Its sections, jobs, parts and documents move over, its trades join, details it
 * lacks are filled in ([FirmCopies], the rule a backup's copy follows too), and the copies go. Two
 * copies of one firm with the same id are one firm, which the copy rule joins (`RecordsMeet`): only
 * firms with ids of their own are offered here. Examples are left as they are.
 */
object DuplicateProvidersStep : DataRepairStep {
    override val id = DataRepairStepId.DUPLICATE_PROVIDERS
    override val group = DataRepairGroup.FIRMS_KEPT_TWICE

    /** The firm kept first, and the copies that would join it. */
    data class Group(val keptId: UUID, val duplicateIds: List<UUID>)

    /** Every group of firms that are the same, by the firm kept first's id. */
    fun candidates(view: BinderView): List<Group> {
        val providers = view.all(Tables.providers).filter { !it.isExample }
        // Each firm starts in a group of its own; a shared name or CUI joins two groups.
        val parent = HashMap<UUID, UUID>()
        for (provider in providers) parent[provider.id] = provider.id
        fun root(id: UUID): UUID {
            var current = id
            while (true) {
                val next = parent[current] ?: return current
                if (next == current) return current
                current = next
            }
        }
        val firstByKey = HashMap<String, UUID>()
        for (provider in providers) {
            val keys = listOf("name:" + SearchText.normalize(provider.name)) +
                listOfNotNull(ProviderTaxID.normalized(provider.taxID)?.let { "cui:$it" })
            for (key in keys) {
                val other = firstByKey[key]
                if (other == null) {
                    firstByKey[key] = provider.id
                    continue
                }
                val a = root(other)
                val b = root(provider.id)
                if (a != b) parent[b] = a
            }
        }
        return providers.groupBy { root(it.id) }.values.mapNotNull { group ->
            val ordered = group.sortedWith(compareBy({ it.createdAt }, { RepairReading.key(it.id) }))
            val ids = ordered.map { it.id }.distinct()
            if (ids.size > 1) Group(ids.first(), ids.drop(1)) else null
        }.sortedBy { RepairReading.key(it.keptId) }
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val names = scan.view.all(Tables.providers).reversed().associate { it.id to it.name }
        return candidates(scan.view).map { group ->
            val duplicates = group.duplicateIds.map(RepairReading::key).sorted().joinToString(",")
            val name = names[group.keptId].orEmpty()
            val subject = DataRepairSubject.DuplicateProviders(group.keptId, group.duplicateIds, name)
            DataRepairFinding(DataRepairFinding.id(id, RepairReading.key(group.keptId), duplicates), id, subject)
        }
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        for (group in findings.mapNotNull { it.subject as? DataRepairSubject.DuplicateProviders }) {
            for (duplicate in group.duplicateIds) {
                val kept = provider(step, group.keptId)
                val copy = provider(step, duplicate)?.takeIf { kept != null && it.id != kept.id } ?: continue
                join(step, copy, requireNotNull(kept))
            }
        }
    }

    /** Moves everything [copy] holds onto [kept], gathers its details there, and deletes it. */
    private fun join(step: Step, copy: Provider, kept: Provider) {
        val keptSections = step.linked(Tables.providerAssets, kept.pk)
        val copySections = step.linked(Tables.providerAssets, copy.pk).filter { it !in keptSections }
        step.setLinked(Tables.providerAssets, kept.pk, keptSections + copySections)
        for (entry in step.linkedTo(Tables.entryProviders, copy.pk)) {
            val people = step.linked(Tables.entryProviders, entry).filter { it != copy.pk }
            step.setLinked(Tables.entryProviders, entry, if (kept.pk in people) people else people + kept.pk)
        }
        for (item in step.all(Tables.items).filter { it.supplier == copy.pk }) {
            step.update(item.copy(supplier = kept.pk))
        }
        for (document in step.all(Tables.attachments).filter { it.provider == copy.pk }) {
            step.update(document.copy(provider = kept.pk))
        }
        val gathered = FirmCopies.gather(details(copy), details(kept))
        step.update(
            requireNotNull(step.row(Tables.providers, kept.pk)).copy(
                trades = gathered.trades, phone = gathered.phone, email = gathered.email, address = gathered.address,
                notes = gathered.notes, manualRating = gathered.manualRating, wouldCallAgain = gathered.wouldCallAgain,
                taxID = gathered.taxID, contactIdentifier = gathered.contactIdentifier,
            ),
        )
        step.delete(requireNotNull(step.row(Tables.providers, copy.pk)))
    }

    private fun details(provider: Provider) = FirmCopies.Details(
        provider.trades, provider.phone, provider.email, provider.address, provider.notes, provider.manualRating,
        provider.wouldCallAgain, provider.taxID, provider.contactIdentifier,
    )

    /** The firm with [id], the first copy in row order. */
    private fun provider(step: Step, id: UUID): Provider? = step.all(Tables.providers).firstOrNull { it.id == id }
}
