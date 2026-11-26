package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.Undoable
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.view
import com.ar.dosarcusina.store.examples.ExampleOwnership
import com.ar.dosarcusina.store.providers.ProviderActions
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.readings.PlannedSectionReading
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import java.time.Instant

/**
 * Logging what happened to a section, as the iOS app's `HistoryActions`
 * (ios/DosarCuSina/Services/History/HistoryActions.swift): the one way a record of history is written and
 * deleted. Repairs, visits, purchases and bills ([record], [recordVisit], [file]) with their parts and jobs
 * ([HistoryItems]), a section's dated note ([addNote]), a record's note ([setNote]) and rating ([rate]), and
 * deleting a record from Istoric ([delete]). Completing a deadline writes its record here too
 * ([recordCompletion], from `ObligationActions.complete`), in the same history.
 *
 * Every question comes first, before the unit of work opens (a lower counter, something of the person's in
 * an example: [HouseholdReadings.askAboutReading], [ExampleOwnership.requireReal]). A reading goes through
 * the one reading path ([HouseholdReadings]); a visit's firm through [ProviderActions.findOrCreate]. The
 * titles the store writes when nothing done names a record are the app's words ([wording]).
 */
// The iOS action's whole surface, one function per job.
@Suppress("TooManyFunctions")
class HistoryActions(
    private val unit: UnitOfWork,
    /** The words a record's title is written with when nothing done names it. */
    private val wording: HistoryWording,
    /** The step's clock: the change time it gives, and the day a record is on when none is given. */
    private val now: () -> Instant = unit.clock,
    /** The app's own categories: an example's question. */
    private val builtIns: Catalog = Catalog.builtIn,
) {
    /**
     * Logs one record (a repair, a purchase, a bill) in [asset]'s history, with its parts and jobs and the
     * counter reading it read, in one save. A lower counter asks before anything is written ([lowerReading]
     * answers it).
     *
     * [replacing] is the record the same paper logged when it was filed before ([PaperIdentity]): it takes
     * these values instead of a second one being added, and moves to [asset] if the paper did. Never a
     * completion, which belongs to its deadline.
     */
    fun record(
        asset: Asset,
        record: HistoryRecord,
        lowerReading: LowerReadingAnswer? = null,
        replacing: HistoryEntry? = null,
    ): HistoryEntry {
        val view = snapshot()
        val section = current(view, asset)
        // Every question first, before anything is written (`StepQuestion`).
        val isExample = ExampleOwnership.requireReal(view, section, builtIns, creatingExample = record.asExample)
        val date = record.occurredAt ?: now()
        val earlier = replaceable(view, replacing)
        val reading = plannedReading(view, record.metricReading, section, date, ReadingSource.PERSON, earlier)
        HouseholdReadings.askAboutReading(view, reading, lowerReading)
        return unit.perform(now = now()) { step ->
            val made = entryToWrite(step, earlier, record.kind, record.title, date, section)
            val entry = made.copy(
                metricReading = record.metricReading,
                totalCostAmount = record.totalCost?.amount, totalCostCurrency = record.totalCost?.currency,
                note = record.note, reference = record.reference, rating = record.rating?.let(::rating),
                isExample = isExample,
            )
            step.update(entry)
            step.setLinked(Tables.entryProviders, entry.pk, record.providers.map { it.pk })
            HistoryItems.add(step, record.items, entry)
            if (reading != null) HouseholdReadings.recordReading(step, reading, lowerReading, isExample = isExample)
            entry
        }
    }

    /**
     * Records one visit (a service, a repair, a check-up) with every part ticked on the checklist, in one
     * save: the record, its parts and jobs (each ticked part named as the category's catalog names it), the
     * counter reading (also kept as a reading), the firm. The receipt takes it all back ("Anulează vizita").
     * A lower counter asks before anything is written ([lowerReading] answers it).
     *
     * [replacing] is the visit the same invoice was filed with before ([PaperIdentity]): it takes these
     * values, parts and reading instead of a second visit being added.
     */
    fun recordVisit(
        asset: Asset,
        visit: VisitRecord,
        lowerReading: LowerReadingAnswer? = null,
        replacing: HistoryEntry? = null,
    ): Undoable<HistoryEntry> {
        val view = snapshot()
        val section = current(view, asset)
        // Every question first, before anything is written (`StepQuestion`).
        val isExample = ExampleOwnership.requireReal(view, section, builtIns)
        val date = visit.occurredAt ?: now()
        val earlier = replaceable(view, replacing)
        val reading = plannedReading(view, visit.odometer, section, date, visit.odometerSource, earlier)
        HouseholdReadings.askAboutReading(view, reading, lowerReading)
        return unit.performUndoable(now()) { step ->
            writeVisit(step, section, visit, Written(date, earlier, isExample, reading, lowerReading))
        }
    }

    /**
     * Files a visit from its form ([VisitDraft.filing]): its firm, found or made by the one rule
     * ([ProviderActions.findOrCreate], linked to the section) or the one chosen, and the visit, together, in
     * one undoable step. A lower counter asks before anything is written ([lowerReading] answers it).
     */
    fun file(visit: VisitFiling, lowerReading: LowerReadingAnswer? = null): Undoable<HistoryEntry> {
        val view = snapshot()
        val section = current(view, visit.asset)
        // Every question first, before anything is written (`StepQuestion`).
        val isExample = ExampleOwnership.requireReal(view, section, builtIns)
        val reading = plannedReading(view, visit.odometer, section, visit.occurredAt, visit.odometerSource, null)
        HouseholdReadings.askAboutReading(view, reading, lowerReading)
        val providers = ProviderActions(unit, now)
        return unit.performUndoable(now()) { step ->
            val provider = when (val choice = visit.provider) {
                VisitFiling.Who.None -> null
                is VisitFiling.Who.Existing -> choice.provider.also { providers.link(it, section) }
                is VisitFiling.Who.Named ->
                    providers.findOrCreate(choice.name, choice.taxID, choice.trade, linkedTo = section)
            }
            val record = visit.record(provider, wording)
            writeVisit(step, section, record, Written(visit.occurredAt, null, isExample, reading, lowerReading))
        }
    }

    /** Adds parts and jobs to [entry], in one save. */
    fun addItems(items: List<LineItemDraft>, entry: HistoryEntry) {
        unit.perform(now = now()) { step -> HistoryItems.add(step, items, fresh(step, entry)) }
    }

    /**
     * Writes the note of a record in Istoric ("Adaugă o notă" after a chore's "Gata", or from the record's
     * page), or clears it with none or blank text. Undoable: the receipt takes back only the note. A record
     * that is a note ([addNote]) keeps its first line as its title.
     */
    fun setNote(entry: HistoryEntry, note: String?): UndoReceipt {
        val text = note?.trim()
        return unit.performUndoable(now()) { step ->
            val row = fresh(step, entry)
            val title = text?.let(::noteTitle)?.takeIf { row.kindRaw == HistoryKind.NOTE.raw }
            step.update(row.copy(note = text?.takeIf { it.isNotEmpty() }, title = title ?: row.title))
        }.receipt
    }

    /**
     * A dated note of its own in [asset]'s Istoric ("Adaugă o notă" on a plant's page, whose category takes
     * notes instead of visits): a record of kind note, its first line its title, the whole text its note, on
     * [occurredAt]. Undoable. Blank text writes nothing and throws [HistoryNoteEmpty].
     */
    fun addNote(asset: Asset, note: String, occurredAt: Instant? = null): Undoable<HistoryEntry> {
        val text = note.trim()
        val title = noteTitle(text) ?: throw HistoryNoteEmpty()
        val view = snapshot()
        val section = current(view, asset)
        // Every question first, before anything is written (`StepQuestion`).
        val isExample = ExampleOwnership.requireReal(view, section, builtIns)
        val date = occurredAt ?: now()
        return unit.performUndoable(now()) { step ->
            val entry = entryToWrite(step, null, HistoryKind.NOTE, title, date, section)
                .copy(note = text, isExample = isExample)
            step.update(entry)
            entry
        }
    }

    /** Rates the job 1–5, or clears the rating with none. The firms' ratings follow from their jobs'. */
    fun rate(entry: HistoryEntry, rating: Int?) {
        unit.perform(now = now()) { step -> step.update(fresh(step, entry).copy(rating = rating?.let(::rating))) }
    }

    /**
     * Deletes [entry] from Istoric, doing exactly what [HistoryDeletion] says: its parts and the reading
     * it recorded go, the documents filed with it stay in the binder, and a deadline's latest completion
     * moves it back to the cycle it closed. One step, saved once. This is for an older record; the step
     * just taken is undone with its receipt.
     */
    fun delete(entry: HistoryEntry) {
        unit.perform(now = now()) { step -> delete(step, entry) }
    }

    /** What a visit's step writes, worked out before it opened. */
    private class Written(
        val date: Instant,
        val earlier: HistoryEntry?,
        val isExample: Boolean,
        val reading: PlannedSectionReading?,
        val lowerReading: LowerReadingAnswer?,
    )

    private fun writeVisit(step: Step, section: Asset, visit: VisitRecord, written: Written): HistoryEntry {
        val catalog = HistoryItems.components(step, section)
        val ticked = visit.checklist.map { item ->
            LineItemDraft(
                name = catalog.firstOrNull { it.key == item.componentKey }?.name ?: item.componentKey,
                componentKey = item.componentKey, partBrandOrCode = item.partBrandOrCode, cost = item.cost,
            )
        }
        val items = ticked + visit.extraItems
        val title = visit.title ?: wording.title(EntryTitle.of(items.map { it.name }))
        val made = entryToWrite(step, written.earlier, visit.kind, title, written.date, section)
        val entry = made.copy(
            metricReading = visit.odometer,
            totalCostAmount = visit.totalCost?.amount, totalCostCurrency = visit.totalCost?.currency,
            note = visit.note?.takeIf { it.isNotBlank() }, reference = visit.reference,
            rating = visit.rating?.let(::rating), isExample = written.isExample,
        )
        step.update(entry)
        step.setLinked(Tables.entryProviders, entry.pk, listOfNotNull(visit.provider?.pk))
        HistoryItems.add(step, items, entry)
        written.reading?.let {
            HouseholdReadings.recordReading(step, it, written.lowerReading, isExample = written.isExample)
        }
        return entry
    }

    /**
     * The reading a record or a visit logs with its counter: in the section's hero unit, at its moment. Asked
     * about before the step's unit opens. [earlier]'s own reading doesn't count against it: the step takes it
     * away first.
     */
    @Suppress("LongParameterList") // What a reading is planned from, as the iOS `plannedReading` takes it.
    private fun plannedReading(
        view: BinderView,
        value: Double?,
        section: Asset,
        at: Instant,
        source: ReadingSource,
        earlier: HistoryEntry?,
    ): PlannedSectionReading? {
        value ?: return null
        val unit = HeroMetric.unit(HeroMetric.categoryFields(view, section))
        return HouseholdReadings.plan(view, section.pk, value, at, source, unit, replaces = { log ->
            earlier?.let { HouseholdReadings.isReading(log, it) } ?: false
        })
    }

    private fun snapshot(): BinderView = unit.view()

    private fun current(view: BinderView, asset: Asset): Asset =
        view.row(Tables.assets, asset.pk) ?: throw NoSuchElementException("The section isn't in the binder")

    private fun fresh(step: Step, entry: HistoryEntry): HistoryEntry =
        step.row(Tables.history, entry.pk) ?: throw NoSuchElementException("The record isn't in the binder")

    companion object {
        /** The highest rating a job gets. */
        private const val BEST_RATING = 5

        /** A rating kept within one to five stars. */
        private fun rating(value: Int): Int = value.coerceIn(1, BEST_RATING)

        /**
         * Writes the record of [obligation]'s completion in [step], as the iOS `complete` does: [kind] (its
         * completion's record), the cycle it closed and what it was before (to go back to it), what it cost,
         * the reading, a note, a rating and its parts and jobs ([items]), under its section, an example when the
         * deadline is one. Who did the work is linked by row ([providers]). The day it moved to is set by the
         * caller ([closed]) once it is known.
         */
        @Suppress("LongParameterList") // A completion's parts, as the iOS action takes them.
        fun recordCompletion(
            step: Step,
            obligation: Obligation,
            kind: HistoryKind,
            cycle: CalendarDay,
            occurredAt: Instant,
            cost: Money? = null,
            metricReading: Double? = null,
            note: String? = null,
            rating: Int? = null,
            providers: List<Long> = emptyList(),
            items: List<LineItemDraft> = emptyList(),
        ): HistoryEntry {
            val entry = step.insert(
                HistoryEntry(
                    kindRaw = kind.raw,
                    title = obligation.title,
                    occurredAt = occurredAt,
                    cycleDueDayISO = StoredDay.text(cycle),
                    previousStatusRaw = obligation.statusRaw,
                    previousDueMetric = obligation.dueMetric,
                    totalCostAmount = cost?.amount,
                    totalCostCurrency = cost?.currency,
                    metricReading = metricReading,
                    note = note,
                    rating = rating?.let(::rating),
                    isExample = obligation.isExample,
                    obligation = obligation.pk,
                    asset = obligation.asset,
                ),
            )
            if (providers.isNotEmpty()) step.setLinked(Tables.entryProviders, entry.pk, providers)
            HistoryItems.add(step, items, entry)
            return entry
        }

        /** [entry] with the day its deadline moved to, written in [step]. */
        fun closed(step: Step, entry: HistoryEntry, next: CalendarDay?): HistoryEntry {
            val written = entry.copy(nextDueDayISO = next?.let(StoredDay::text))
            step.update(written)
            return written
        }

        /** Deletes [entry] in [step], as [HistoryActions.delete] does: inside a larger step (a repair). */
        fun delete(step: Step, entry: HistoryEntry) {
            val current = step.row(Tables.history, entry.pk) ?: return
            val effect = HistoryDeletion.of(step, current)
            val reopened = effect.reopensCycle
            val owner = current.obligation?.let { step.row(Tables.obligations, it) }
            if (reopened != null && owner != null) {
                val status = ObligationStatus.stored(owner.statusRaw)
                val back = if (status == ObligationStatus.DONE) {
                    ObligationStatus.entries.firstOrNull { it.raw == current.previousStatusRaw }
                        ?: ObligationStatus.ACTIVE
                } else {
                    status
                }
                step.update(
                    owner.copy(
                        dueDayISO = StoredDay.text(reopened),
                        dueMetric = current.previousDueMetric,
                        statusRaw = if (back == status) owner.statusRaw else back.raw,
                    ),
                )
            }
            if (effect.removedReading != null) HouseholdReadings.removeReading(step, current)
            for (row in step.pointingAt(Tables.attachments, "historyEntry", current.pk)) {
                step.row(Tables.attachments, row)?.let { step.update(it.copy(historyEntry = null)) }
            }
            step.row(Tables.history, current.pk)?.let(step::delete)
        }

        /**
         * The completions of [obligation], newest first, as the iOS `Obligation.history`: two recorded at
         * the same moment are ordered by the cycle they closed, which only moves forward.
         */
        fun history(view: BinderView, obligation: Obligation): List<HistoryEntry> =
            view.pointingAt(Tables.history, "obligation", obligation.pk)
                .mapNotNull { view.row(Tables.history, it) }
                .sortedWith(newestFirst)

        /**
         * The completion the deadline's current cycle comes from, as the iOS `Obligation.latestCompletion`:
         * the one that closed the latest cycle. Ordered by the cycle closed, which only moves forward, so a
         * completion dated in the past still counts as the latest when it is.
         */
        fun latestCompletion(view: BinderView, obligation: Obligation): HistoryEntry? =
            view.pointingAt(Tables.history, "obligation", obligation.pk)
                .mapNotNull { view.row(Tables.history, it) }
                .filter { it.isCompletion }
                .maxWithOrNull(byCycleClosed)

        /** A note's title: its first line that says something; none for blank text. */
        fun noteTitle(text: String): String? =
            text.split(NEWLINES).map { it.trim() }.firstOrNull { it.isNotEmpty() }

        /** The characters that end a line. */
        private val NEWLINES = Regex("[\\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]")

        /** A record a paper logged that filing it again may take over, as stored now: never a completion. */
        private fun replaceable(view: BinderView, entry: HistoryEntry?): HistoryEntry? =
            entry?.let { view.row(Tables.history, it.pk) }?.takeUnless { it.isCompletion }

        /**
         * A new record in [section]'s history, or [earlier] cleared to be written again: its parts and jobs and
         * the reading it recorded go, and it moves to [section] and [date].
         */
        @Suppress("LongParameterList") // What a record is written as, as the iOS `entryToWrite` takes it.
        private fun entryToWrite(
            step: Step,
            earlier: HistoryEntry?,
            kind: HistoryKind,
            title: String,
            date: Instant,
            section: Asset,
        ): HistoryEntry {
            if (earlier == null) {
                val made = HistoryEntry(kindRaw = kind.raw, title = title, occurredAt = date, asset = section.pk)
                return step.insert(made)
            }
            val row = step.row(Tables.history, earlier.pk) ?: throw NoSuchElementException("The record isn't there")
            HouseholdReadings.removeReading(step, row)
            for (item in HistoryRecords.items(step, row)) step.delete(item)
            val cleared = requireNotNull(step.row(Tables.history, row.pk))
                .copy(kindRaw = kind.raw, title = title, occurredAt = date, asset = section.pk)
            step.update(cleared)
            return cleared
        }

        /** Newest first; at the same moment, the later cycle first. */
        private val newestFirst: Comparator<HistoryEntry> =
            compareByDescending<HistoryEntry> { it.occurredAt }
                .thenByDescending { it.cycleDueDay ?: CalendarDay.EARLIEST }

        /** By the cycle closed, then by when. */
        private val byCycleClosed: Comparator<HistoryEntry> =
            compareBy<HistoryEntry> { it.cycleDueDay ?: CalendarDay.EARLIEST }.thenBy { it.occurredAt }
    }
}

/** A note says nothing: the sheet's button waits for words, as the iOS app's `HistoryNoteError.empty`. */
class HistoryNoteEmpty : Exception("A note says nothing")

/**
 * One record of history to log ([HistoryActions.record]): a repair, a purchase, a bill, with its parts and
 * jobs, what it cost, the counter it read and who did it. [reference] is the number of the paper it records
 * (a bill's invoice number).
 */
data class HistoryRecord(
    val kind: HistoryKind,
    val title: String,
    /** When it happened; none for now. */
    val occurredAt: Instant? = null,
    val metricReading: Double? = null,
    val totalCost: Money? = null,
    val note: String? = null,
    val reference: String? = null,
    val items: List<LineItemDraft> = emptyList(),
    val providers: List<Provider> = emptyList(),
    val rating: Int? = null,
    /** Made by the example loader: an example. */
    val asExample: Boolean = false,
)

/**
 * One visit to log ([HistoryActions.recordVisit]): every part ticked on the checklist, anything else done,
 * what it cost, the counter, who did it, a note, the invoice's number and a rating. Its title, when none is
 * given, names what was done ([EntryTitle.of]).
 */
data class VisitRecord(
    val kind: HistoryKind = HistoryKind.MAINTENANCE,
    val title: String? = null,
    /** When it happened; none for now. */
    val occurredAt: Instant? = null,
    val checklist: List<ChecklistItem> = emptyList(),
    val extraItems: List<LineItemDraft> = emptyList(),
    val totalCost: Money? = null,
    val odometer: Double? = null,
    /** Where the counter came from: read by the person, or printed on the invoice. */
    val odometerSource: ReadingSource = ReadingSource.PERSON,
    val provider: Provider? = null,
    val note: String? = null,
    val reference: String? = null,
    val rating: Int? = null,
)

/** One ticked part or job on the visit checklist, with what it cost if known, as the iOS `ChecklistItem`. */
data class ChecklistItem(val componentKey: String, val cost: Money? = null, val partBrandOrCode: String? = null)

/**
 * A confirmed line item to add to a record of history, as the iOS app's `LineItemDraft`: capture produces
 * drafts the person reviews; only confirmed values reach the actions.
 */
data class LineItemDraft(
    val name: String,
    /** A part's key; when none it is worked out from [name] and the category's parts. */
    val componentKey: String? = null,
    val group: String? = null,
    val partBrandOrCode: String? = null,
    val partSerialNumber: String? = null,
    val cost: Money? = null,
    val laborCost: Money? = null,
    val partsCost: Money? = null,
    val warrantyMonths: Int? = null,
    val daysInService: Int? = null,
    val locationDetail: String? = null,
    val batchOrTicket: String? = null,
    val notes: String? = null,
    /** Who supplied the part (its row), when different from who fitted it. */
    val supplier: Long? = null,
)
