package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.text.PaymentCardNumbers
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.documentDay
import com.ar.dosarcusina.store.schema.dueDay
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.snoozedUntil
import com.ar.dosarcusina.store.schema.validUntil
import com.ar.dosarcusina.store.schema.withKeptValues
import java.util.UUID

/**
 * The one rule for a kept day that can't be, wherever it is kept: in a section's values or in a day
 * kept on a deadline, a completion or a document, as the iOS app's `DayYearsStep`.
 *
 * - **Another calendar's year.** Before the iOS app counted every day in one Gregorian calendar, a
 *   phone set to another calendar wrote the days it worked out itself in that calendar's years: on a
 *   phone set to the Buddhist calendar, today was 2569. Such a day reads as a year that can't be (more
 *   than 200 years ahead, or before 1800). A year 543 ahead of a likely one is the Buddhist calendar's
 *   (its months and days are the Gregorian ones), so it is offered back 543 years, asking first. Any
 *   other year that can't be can't be worked back safely: the finding only says where it is and what
 *   to check ([DataRepairFinding.isFixable] false).
 * - **A day its month doesn't have.** A backup may bring a day as it was written, such as "2026-02-30"
 *   (kept as written, since days are stored as days, never rolled over). It counts as the month's last
 *   day ([CalendarDay.onCalendar]); the list offers that day, asking first.
 */
object DayYearsStep : DataRepairStep {
    override val id = DataRepairStepId.DAY_YEARS
    override val group = DataRepairGroup.IMPOSSIBLE_DAYS

    /** How far a year read from another calendar is from the Gregorian one: the Buddhist era. */
    const val BUDDHIST_OFFSET = 543
    private const val FURTHEST_AHEAD = 200
    private const val EARLIEST_YEAR = 1800
    private const val EARLIEST_MEANT = 1900
    private const val LATEST_MEANT_AHEAD = 100

    /** Where a day is kept. */
    sealed interface Place {
        /** Its part of a finding's id. */
        val key: String

        /** A date field of a section's values. */
        data class Field(val assetId: UUID, val fieldKey: String) : Place {
            override val key get() = "field:${RepairReading.key(assetId)}:$fieldKey"
        }

        data class Due(val obligationId: UUID) : Place {
            override val key get() = "due:${RepairReading.key(obligationId)}"
        }

        data class Snooze(val obligationId: UUID) : Place {
            override val key get() = "snooze:${RepairReading.key(obligationId)}"
        }

        data class Cycle(val entryId: UUID) : Place {
            override val key get() = "cycle:${RepairReading.key(entryId)}"
        }

        data class Next(val entryId: UUID) : Place {
            override val key get() = "next:${RepairReading.key(entryId)}"
        }

        data class DocumentDay(val attachmentId: UUID) : Place {
            override val key get() = "document-day:${RepairReading.key(attachmentId)}"
        }

        data class ValidUntil(val attachmentId: UUID) : Place {
            override val key get() = "valid-until:${RepairReading.key(attachmentId)}"
        }
    }

    /** What a kept day says. */
    sealed interface Verdict {
        /** The day offered in its place, when there is one. */
        val offered: CalendarDay? get() = null

        /** A day that can be. */
        data object Possible : Verdict

        /** A year that can't be, and the day it means. */
        data class Means(val day: CalendarDay) : Verdict {
            override val offered get() = day
        }

        /** A day its month doesn't have, in a year that can be, and that month's last day. */
        data class Missing(val lastOfMonth: CalendarDay) : Verdict {
            override val offered get() = lastOfMonth
        }

        /** A year that can't be, and no safe way to the day it means. */
        data object Unknown : Verdict
    }

    /** A day that can't be, what it says, where it is, and how to write a day back there. */
    class Candidate internal constructor(
        val place: Place,
        val day: CalendarDay,
        val verdict: Verdict,
        val name: String,
        val section: String?,
        internal val write: (Step, CalendarDay) -> Unit,
    )

    /**
     * A year more than 200 years ahead or before 1800 can't be. It means the day 543 years before when
     * that lands between 1900 and a hundred years ahead. In a year that can be, a day its month doesn't
     * have is offered as that month's last day.
     */
    fun verdict(day: CalendarDay, thisYear: Int): Verdict = when {
        day.year > thisYear + FURTHEST_AHEAD || day.year < EARLIEST_YEAR -> meant(day, thisYear)
        day.isOnCalendar -> Verdict.Possible
        else -> Verdict.Missing(day.onCalendar)
    }

    /** The day a year that can't be means, 543 years before, when that is a day and lands where it can. */
    private fun meant(day: CalendarDay, thisYear: Int): Verdict {
        val year = day.year - BUDDHIST_OFFSET
        val meant = CalendarDay.valid(year, day.month, day.day)
        val likely = year in EARLIEST_MEANT..(thisYear + LATEST_MEANT_AHEAD)
        return if (meant != null && likely) Verdict.Means(meant) else Verdict.Unknown
    }

    /** Every kept day of the binder in [view] that can't be, in the iOS app's order. */
    fun candidates(view: BinderView, thisYear: Int): List<Candidate> {
        val found = Found(view, thisYear)
        sectionDays(found)
        for (deadline in view.all(Tables.obligations)) {
            val pk = deadline.pk
            val section = found.section(deadline.asset)
            found.check(deadline.dueDay, Place.Due(deadline.id), deadline.title, section) { step, fixed ->
                step.row(Tables.obligations, pk)?.let { step.update(it.copy(dueDayISO = StoredDay.text(fixed))) }
            }
            found.check(deadline.snoozedUntil, Place.Snooze(deadline.id), deadline.title, section) { step, fixed ->
                step.row(Tables.obligations, pk)?.let { step.update(it.copy(snoozedUntilISO = StoredDay.text(fixed))) }
            }
        }
        for (entry in view.all(Tables.history)) {
            // Only a completion keeps the days of its cycle.
            val cycle = entry.cycleDueDayISO ?: continue
            val pk = entry.pk
            val section = found.section(entry.asset)
            found.check(StoredDay.day(cycle), Place.Cycle(entry.id), entry.title, section) { step, fixed ->
                step.row(Tables.history, pk)?.let { step.update(it.copy(cycleDueDayISO = StoredDay.text(fixed))) }
            }
            found.check(StoredDay.day(entry.nextDueDayISO), Place.Next(entry.id), entry.title, section) { step, fixed ->
                step.row(Tables.history, pk)?.let { step.update(it.copy(nextDueDayISO = StoredDay.text(fixed))) }
            }
        }
        for (document in view.all(Tables.attachments)) {
            val pk = document.pk
            val name = document.title ?: document.fileName
            val section = found.section(document.asset)
            found.check(document.documentDay, Place.DocumentDay(document.id), name, section) { step, fixed ->
                step.row(Tables.attachments, pk)?.let { step.update(it.copy(documentDayISO = StoredDay.text(fixed))) }
            }
            found.check(document.validUntil, Place.ValidUntil(document.id), name, section) { step, fixed ->
                step.row(Tables.attachments, pk)?.let { step.update(it.copy(validUntilISO = StoredDay.text(fixed))) }
            }
        }
        return found.candidates
    }

    /** The date fields of every section's values, each section's by key. */
    private fun sectionDays(found: Found) {
        val categories = RepairReading.categories(found.view)
        for (asset in found.view.all(Tables.assets)) {
            val labels = categories[asset.templateKey]?.let(RepairReading::fields)?.associate { it.key to it.label }
            for ((key, value) in asset.keptValues.value.storage.toSortedMap()) {
                val day = (value as? FieldValue.Day)?.value
                found.check(day, Place.Field(asset.id, key), labels?.get(key) ?: key, asset.name) { step, fixed ->
                    step.row(Tables.assets, asset.pk)?.let { step.update(withDay(it, key, fixed)) }
                }
            }
        }
    }

    /** The days found so far that can't be. */
    private class Found(val view: BinderView, private val thisYear: Int) {
        val candidates = ArrayList<Candidate>()

        fun section(row: Long?): String? = row?.let { view.row(Tables.assets, it) }?.name

        fun check(day: CalendarDay?, place: Place, name: String, section: String?, write: (Step, CalendarDay) -> Unit) {
            day ?: return
            val verdict = verdict(day, thisYear)
            if (verdict != Verdict.Possible) candidates += Candidate(place, day, verdict, name, section, write)
        }
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> =
        candidates(scan.view, thisYear(scan.context)).map { candidate ->
            DataRepairFinding(
                id = DataRepairFinding.id(id, candidate.place.key, candidate.day.isoString),
                step = id,
                // The names are shown in the list: never with a card number they may hold.
                subject = DataRepairSubject.DayYear(
                    place = candidate.place,
                    from = candidate.day,
                    to = candidate.verdict.offered,
                    verdict = candidate.verdict,
                    name = PaymentCardNumbers.redact(candidate.name),
                    section = candidate.section?.let { PaymentCardNumbers.redact(it) },
                ),
                isFixable = candidate.verdict.offered != null,
            )
        }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNull { it.subject as? DataRepairSubject.DayYear }
            .mapNotNull { subject -> subject.to?.let { subject.place to (subject.from to it) } }
            .toMap()
        if (approved.isEmpty()) return
        // Checked again: a day changed since it was found stays as it is now.
        for (candidate in candidates(step, thisYear(context))) {
            val (from, to) = approved[candidate.place] ?: continue
            if (from == candidate.day && candidate.verdict.offered == to) candidate.write(step, to)
        }
    }

    private fun thisYear(context: DataRepairContext): Int = CalendarDay.of(context.now, context.zone).year

    private fun withDay(asset: Asset, key: String, day: CalendarDay): Asset {
        val kept = asset.keptValues
        return asset.withKeptValues(kept.replacingValue(kept.value.with(key, FieldValue.Day(day))))
    }
}
