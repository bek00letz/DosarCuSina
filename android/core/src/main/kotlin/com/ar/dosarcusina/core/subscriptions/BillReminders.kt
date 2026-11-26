package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationStatus
import java.util.UUID

/**
 * A subscription's "Factura de plătit" follows how its bills are paid, as the iOS app's `BillReminders`
 * (ios/DosarCuSina/Services/Subscriptions/BillReminders.swift): this is its rule, for the store to carry out. When
 * the bank starts paying by direct debit, the reminder already made pauses: nothing to pay by hand. When direct
 * debit stops, a reminder whose day hasn't passed comes back, and one whose day has passed stays paused until the
 * next bill takes it up again. Bills keep going into the history either way, so the missing-bill note still works.
 *
 * The store runs it where a section's values change (the iOS app's `AssetActions.update`), and pauses or resumes
 * each deadline through the deadline actions, inside the edit's own step, so "Anulează" takes back both together.
 */
object BillReminders {
    /** What happened to the bill reminder. */
    enum class Change {
        /** Direct debit turned on: the reminder to pay is paused. */
        PAUSED,

        /** Direct debit turned off: the reminder for a bill still to pay is back. */
        RESUMED,
    }

    /** A subscription's "Factura de plătit" deadline, as the rule reads it. */
    data class BillDeadline(val id: UUID, val status: ObligationStatus, val dueDay: CalendarDay)

    /** What the edit changes: which way, and the deadlines to pause or to resume. */
    data class Followed(val change: Change, val deadlines: List<UUID>)

    /** Which way the setting moved between a subscription's values before and after an edit, if it did. */
    fun direction(paidByDirectDebitBefore: Boolean, paidByDirectDebitAfter: Boolean): Change? = when {
        paidByDirectDebitBefore == paidByDirectDebitAfter -> null
        paidByDirectDebitAfter -> Change.PAUSED
        else -> Change.RESUMED
    }

    /**
     * What following the setting does to the subscription's bill deadlines ([bills]) on [today]: the active ones
     * pause; a paused one comes back only while its day hasn't passed. Null when nothing changes (the setting didn't
     * move, or there was no deadline to change).
     */
    fun follow(
        paidByDirectDebitBefore: Boolean,
        paidByDirectDebitAfter: Boolean,
        bills: List<BillDeadline>,
        today: CalendarDay,
    ): Followed? {
        val change = direction(paidByDirectDebitBefore, paidByDirectDebitAfter) ?: return null
        val changed = when (change) {
            Change.PAUSED -> bills.filter { it.status == ObligationStatus.ACTIVE }
            // Only a bill still to pay; an older one waits for the next bill.
            Change.RESUMED -> bills.filter { it.status == ObligationStatus.PAUSED && it.dueDay >= today }
        }
        return if (changed.isEmpty()) null else Followed(change, changed.map { it.id })
    }
}
