package com.ar.dosarcusina.core.deadlines

import com.ar.dosarcusina.core.urgency.Consequence
import com.ar.dosarcusina.core.urgency.ReminderProfile
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationKind

// What a deadline's kind means for how it repeats and reminds, as the iOS app's `ObligationKind`
// (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift): the kind itself is the one
// `core.values.ObligationKind`, and these say what the deadline rules read of it.

/**
 * Whether each cycle of a repeat counted from its due dates is money still owed when it is missed: a
 * month's rent, a tax installment. Done late, one "Gata" then closes one cycle and the next may still
 * be late; every other kind moves to its first due day after the day it was done, so it isn't late the
 * moment it is done.
 */
val ObligationKind.missedCyclesStayOwed: Boolean
    get() = this == ObligationKind.PAYMENT || this == ObligationKind.TAX

/** The reminders a deadline of this kind starts from when a blueprint or the person doesn't give any. */
// The profiles themselves, as the iOS app declares them.
@Suppress("MagicNumber")
val ObligationKind.defaultProfile: ReminderProfile
    get() = when (this) {
        ObligationKind.LEGAL, ObligationKind.INSURANCE -> ReminderProfile(listOf(30, 7, 0), Consequence.LEGAL)
        ObligationKind.TAX -> ReminderProfile(listOf(14, 1), Consequence.FINANCIAL)
        ObligationKind.HEALTH -> ReminderProfile(listOf(7, 1), Consequence.HEALTH, graceDays = 7)
        ObligationKind.RENEWAL -> ReminderProfile(listOf(60, 30), Consequence.LEGAL)
        ObligationKind.PAYMENT -> ReminderProfile(listOf(2, 0), Consequence.FINANCIAL)
        ObligationKind.MAINTENANCE -> ReminderProfile(listOf(14, 1), Consequence.COMFORT, graceDays = 14)
        ObligationKind.ROUTINE -> ReminderProfile(listOf(0), Consequence.COMFORT, graceDays = 3)
    }

/**
 * What a deadline's due day means for whether something is still valid, decided once, as the iOS
 * app's `DueDayValidity` (ios/DosarCuSina/Models/Obligations/DueDayValidity.swift).
 *
 * Today the due day is the **last valid day**, the way policies and identity documents print it:
 * an RCA "valabilă până la 12.08.2027" still covers 12 August. Whether it should rather be the
 * first day without cover is the owner's call; flipping [DUE_DAY_IS_LAST_VALID_DAY] changes every
 * check that asks, and nothing else needs to.
 */
object DueDayValidity {
    /** The due day is the last day something is valid (true), or the first day it isn't (false). */
    const val DUE_DAY_IS_LAST_VALID_DAY: Boolean = true

    /** Whether something due on [due] is still valid on [day]. */
    fun isValid(due: CalendarDay, day: CalendarDay): Boolean =
        if (DUE_DAY_IS_LAST_VALID_DAY) day <= due else day < due

    /** Whether something due on [due] stays valid every day up to and including [day]. */
    fun covers(through: CalendarDay, due: CalendarDay): Boolean = isValid(due, through)
}
