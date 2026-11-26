package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.schema.HistoryEntry

/** Whether this record is the completion of a deadline. */
val HistoryEntry.isCompletion: Boolean get() = cycleDueDayISO != null

/** The due day of the cycle it closed. */
val HistoryEntry.cycleDueDay: CalendarDay? get() = StoredDay.day(cycleDueDayISO)

/** The due day its deadline moved to. */
val HistoryEntry.nextDueDay: CalendarDay? get() = StoredDay.day(nextDueDayISO)

/**
 * What deleting a record from Istoric does, worked out once, as the iOS app's `HistoryDeletion`
 * (ios/DosarCuSina/Services/History/HistoryDeletion.swift): the confirmation says it, and
 * [HistoryActions.delete] does exactly it.
 *
 * - Its line items go, and so does the reading it recorded; the value on the section follows the
 *   readings left.
 * - The documents filed with it stay in the binder, under the same section.
 * - A completion moves its deadline back to the cycle it closed only when it is the latest one: deleting
 *   it is as if the deadline wasn't done. An older completion leaves the deadline where it is.
 */
data class HistoryDeletion(
    /** The due day the deadline goes back to, when this is its latest completion. */
    val reopensCycle: CalendarDay?,
    /** The deadline that stays as it is, when this is an older completion. */
    val keepsDeadline: Boolean,
    /** The reading that goes with the record. */
    val removedReading: Double?,
    /** Documents filed with the record, which stay. */
    val keptDocuments: Int,
) {
    companion object {
        fun of(view: BinderView, entry: HistoryEntry): HistoryDeletion {
            val owner = entry.obligation?.let { view.row(Tables.obligations, it) }
            val isLatest = entry.isCompletion && owner != null &&
                HistoryActions.latestCompletion(view, owner)?.pk == entry.pk
            val recorded = entry.metricReading?.takeIf {
                entry.asset != null && HouseholdReadings.readings(view, entry.asset).any { log ->
                    HouseholdReadings.isReading(log, entry)
                }
            }
            return HistoryDeletion(
                reopensCycle = if (isLatest) entry.cycleDueDay else null,
                keepsDeadline = entry.isCompletion && owner != null && !isLatest,
                removedReading = recorded,
                keptDocuments = view.pointingAt(Tables.attachments, "historyEntry", entry.pk).size,
            )
        }
    }
}
