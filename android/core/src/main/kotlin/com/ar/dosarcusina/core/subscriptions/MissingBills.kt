package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.RecurrenceInterval
import java.util.UUID

/**
 * The plain facts about one subscription the missing-bill note needs, as the iOS app's `BillWatchSnapshot`: the
 * store fills one for every section of a category that plays the subscription part.
 */
data class BillWatch(
    val id: UUID,
    /** Its stored service (`subscription.service`), as stored; null for none. */
    val service: String?,
    /** How often its bills come ([BillingCycle.interval] of its stored cycle). */
    val cycle: RecurrenceInterval,
    val bills: List<BillRecord>,
    /** Locked when its category is, or the section it is filed under: its note then names nothing. */
    val isSensitive: Boolean,
    val isExample: Boolean,
)

/** A subscription whose bill hasn't come, for a calm note in Urmează's "Din timp". */
data class MissingBillNote(val id: UUID, val isSensitive: Boolean, val missing: MissingBill)

/**
 * Which subscriptions' bills haven't come when they usually do, as the iOS app's `AttentionModel.missingBills`
 * (ios/DosarCuSina/Services/Attention/MissingBills.swift): only those billed on a rhythm ([Service.sendsRegularBills])
 * that have had a bill before, never an example, oldest expected first. What the note says is the screen's (Phase 4).
 */
object MissingBills {
    fun find(subscriptions: List<BillWatch>, today: CalendarDay): List<MissingBillNote> = subscriptions
        .filter { !it.isExample && ServiceKind.sendsRegularBills(it.service) }
        .mapNotNull { watch ->
            BillHistory.missing(watch.bills, watch.cycle, today)
                ?.let { MissingBillNote(watch.id, watch.isSensitive, it) }
        }
        .sortedBy { it.missing.expectedDay }
}
