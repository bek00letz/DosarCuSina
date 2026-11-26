package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.history.HistoryRecords
import com.ar.dosarcusina.store.history.PaperIdentity
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.ServiceItem
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * The same visit logged twice, as the iOS app's `SameVisitTwiceStep`
 * (ios/DosarCuSina/Services/Repairs/VisitRepairSteps.swift): before another photo of a visit's invoice was
 * known as the same invoice, filing it again through the visit form logged a second visit on the section.
 * Visits of one section whose papers the one rule ([PaperIdentity]) says are the same invoice for sure (the
 * same number from the same firm on the same day, or no number to compare and the same day, total and firm)
 * are offered to be joined, leaving what filing the invoice once leaves: one visit (the one whose paper came
 * last) with every paper, the newest as the current copy and the rest archived beside it; its parts and jobs
 * once; one reading. Only visits that each have a paper are compared: a visit typed by hand was never doubled
 * by a photo. It asks: it changes what Istoric and the section's counter show.
 */
object SameVisitTwiceStep : DataRepairStep {
    override val id = DataRepairStepId.SAME_VISIT_TWICE
    override val group = DataRepairGroup.VISITS_LOGGED_TWICE

    /** One visit logged more than once: the record that stays and the ones joined into it. */
    data class Group(val keep: UUID, val merge: List<UUID>)

    /** The visits logged more than once, section by section. */
    fun groups(view: BinderView, zone: ZoneId): List<Group> =
        view.all(Tables.assets).filter { !it.isExample }.flatMap { groups(view, it, zone) }

    private fun groups(view: BinderView, section: Asset, zone: ZoneId): List<Group> {
        val visits = PaperIdentity.visits(view, section)
            .filter { !it.isExample && HistoryRecords.papers(view, it).isNotEmpty() }
            .sortedWith(compareBy<HistoryEntry> { it.occurredAt }.thenBy { RepairReading.key(it.id) })
        val placed = HashSet<UUID>()
        val groups = ArrayList<Group>()
        for ((index, visit) in visits.withIndex()) {
            if (visit.id in placed) continue
            val identity = PaperIdentity.of(view, visit, zone)
            // Only what is the same invoice for sure; the number alone may be another one.
            val same = listOf(visit) + visits.drop(index + 1).filter { other ->
                other.id !in placed && identity.match(PaperIdentity.of(view, other, zone)) in sure
            }
            group(view, same)?.let { group ->
                placed += same.map { it.id }
                groups += group
            }
        }
        return groups
    }

    /** The visits [same] as one group, the one whose paper came last kept; none for a visit alone. */
    private fun group(view: BinderView, same: List<HistoryEntry>): Group? {
        if (same.size < 2) return null
        val keep = same.maxBy { lastPaper(view, it) }
        return Group(keep.id, same.map { it.id }.filter { it != keep.id }.sortedBy(RepairReading::key))
    }

    private val sure = setOf(PaperIdentity.Match.NUMBER, PaperIdentity.Match.DAY_AND_TOTAL)

    /** When [entry]'s newest paper was filed. */
    private fun lastPaper(view: BinderView, entry: HistoryEntry): Instant =
        HistoryRecords.papers(view, entry).maxOfOrNull { it.createdAt } ?: Instant.MIN

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val entries = scan.view.all(Tables.history).reversed().associateBy { it.id }
        return groups(scan.view, scan.context.zone).mapNotNull { group ->
            val kept = entries[group.keep] ?: return@mapNotNull null
            val section = kept.asset?.let { scan.view.row(Tables.assets, it) }?.name.orEmpty()
            val day = CalendarDay.of(kept.occurredAt, scan.context.zone)
            val merged = group.merge.joinToString(",", transform = RepairReading::key)
            DataRepairFinding(
                DataRepairFinding.id(id, RepairReading.key(group.keep), merged), id,
                DataRepairSubject.SameVisit(group.keep, group.merge, day, section),
            )
        }
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNull { finding ->
            (finding.subject as? DataRepairSubject.SameVisit)?.let { Group(it.keep, it.merge) }
        }
        if (approved.isEmpty()) return
        // Only what still holds: the same groups found again now.
        val current = groups(step, context.zone).toSet()
        val entries = step.all(Tables.history).reversed().associateBy { it.id }
        for (group in approved.filter { it in current }) {
            val kept = entries[group.keep]
            val section = kept?.asset?.let { step.row(Tables.assets, it) } ?: continue
            val extra = group.merge.mapNotNull { entries[it] }
            join(step, extra, kept, section)
            keepPapers(step, listOf(kept) + extra, kept)
            for (entry in extra) step.row(Tables.history, entry.pk)?.let(step::delete)
        }
    }

    /**
     * Every paper stays with the visit that stays; the newest is its current copy, the others are archived
     * beside it, pointing at it (`AttachmentActions.supersede`).
     */
    private fun keepPapers(step: Step, visits: List<HistoryEntry>, kept: HistoryEntry) {
        val papers = visits.flatMap { HistoryRecords.papers(step, it) }
        for (paper in papers) step.update(paper.copy(historyEntry = kept.pk))
        val current = papers.mapNotNull { step.row(Tables.attachments, it.pk) }.filter { !it.isArchived }
        val newest = current.maxByOrNull { it.createdAt } ?: return
        for (older in current) {
            if (older.pk != newest.pk) step.update(older.copy(supersededBy = newest.pk, isArchived = true))
        }
    }

    /**
     * What the extra visits recorded that the one that stays doesn't: their number, total, firm, rating, note
     * and deadline where it has none, their parts and jobs it doesn't list, and one reading.
     */
    private fun join(step: Step, extra: List<HistoryEntry>, kept: HistoryEntry, section: Asset) {
        for (entry in extra) {
            val row = requireNotNull(step.row(Tables.history, kept.pk))
            val cost = if (row.totalCostAmount == null) entry else row
            step.update(
                row.copy(
                    reference = filled(row.reference) ?: filled(entry.reference) ?: row.reference,
                    totalCostAmount = cost.totalCostAmount,
                    totalCostCurrency = cost.totalCostCurrency,
                    rating = row.rating ?: entry.rating,
                    note = filled(row.note) ?: filled(entry.note) ?: row.note,
                    obligation = row.obligation ?: entry.obligation,
                ),
            )
            val firms = step.linked(Tables.entryProviders, entry.pk)
            if (step.linked(Tables.entryProviders, kept.pk).isEmpty() && firms.isNotEmpty()) {
                step.setLinked(Tables.entryProviders, kept.pk, firms)
            }
            // Parts and jobs, once: one the visit already lists stays as it is.
            for (item in HistoryRecords.items(step, entry)) {
                val listed = HistoryRecords.items(step, kept).any { itemKey(it) == itemKey(item) }
                if (!listed) step.update(item.copy(entry = kept.pk))
            }
        }
        joinReadings(step, extra, requireNotNull(step.row(Tables.history, kept.pk)), section)
    }

    /** The same part or job: its part's key, else its name as compared. */
    private fun itemKey(item: ServiceItem): String =
        item.componentKey?.let { "component:$it" } ?: "name:${PaperIdentity.comparable(item.name).orEmpty()}"

    /** One reading for the visit: its own, else the first extra visit's, moved to its moment. The others go. */
    private fun joinReadings(step: Step, extra: List<HistoryEntry>, kept: HistoryEntry, section: Asset) {
        val visits = listOf(kept) + extra
        val logs = HouseholdReadings.readings(step, section.pk).filter { log ->
            visits.any { HouseholdReadings.isReading(log, it) }
        }
        var stays = kept
        val donor = extra.firstOrNull { it.metricReading != null }
        if (kept.metricReading == null && donor != null) {
            stays = kept.copy(metricReading = donor.metricReading)
            step.update(stays)
            logs.firstOrNull { HouseholdReadings.isReading(it, donor) }
                ?.let { step.update(it.copy(recordedAt = kept.occurredAt)) }
        }
        val now = logs.mapNotNull { step.row(Tables.readings, it.pk) }
        val keeps = now.firstOrNull { HouseholdReadings.isReading(it, stays) }
        for (log in now) if (log.pk != keeps?.pk) HouseholdReadings.deleteReading(step, log)
        HeroMetric.sync(step, section.pk)
    }
}

/** [text] when it says something; none for none or empty text. */
private fun filled(text: String?): String? = text?.takeIf { it.isNotEmpty() }
