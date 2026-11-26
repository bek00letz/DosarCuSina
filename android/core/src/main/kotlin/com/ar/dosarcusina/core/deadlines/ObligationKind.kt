package com.ar.dosarcusina.core.deadlines

import com.ar.dosarcusina.core.urgency.Consequence
import com.ar.dosarcusina.core.urgency.ReminderProfile
import com.ar.dosarcusina.core.values.CalendarDay

/**
 * What kind of duty a deadline is, as the iOS app's `ObligationKind`
 * (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift): how it is grouped, the reminders it
 * starts from when nothing more specific is given ([defaultProfile]), and whether a cycle missed is
 * money still owed ([missedCyclesStayOwed]). [raw] is stored (`Obligation.kindRaw`) and part of the
 * `.dosar` contract.
 */
enum class ObligationKind(val raw: String) {
    /** A legal requirement with penalties: ITP, gas installation checks, rovinietă. */
    LEGAL("legal"),

    /** Taxes and declarations to the state: local taxes, Declarația Unică. */
    TAX("tax"),

    /** Insurance that lapses: RCA, PAD, CASCO. */
    INSURANCE("insurance"),

    /** Health and prevention: vaccines, screenings, prescriptions. */
    HEALTH("health"),

    /** Documents that expire and take time to renew: ID card, passport. */
    RENEWAL("renewal"),

    /** Bills and recurring payments: rent, subscriptions, utilities. */
    PAYMENT("payment"),

    /** Upkeep that prevents bigger costs: oil change, boiler service. */
    MAINTENANCE("maintenance"),

    /** Everyday chores: watering plants, cleaning filters. */
    ROUTINE("routine"),
    ;

    /**
     * Whether each cycle of a repeat counted from its due dates is money still owed when it is
     * missed: a month's rent, a tax installment. Done late, one "Gata" then closes one cycle and the
     * next may still be late; every other kind moves to its first due day after the day it was done,
     * so it isn't late the moment it is done.
     */
    val missedCyclesStayOwed: Boolean get() = this == PAYMENT || this == TAX

    /** The reminders used when a blueprint or the person doesn't give any. */
    // The profiles themselves, as the iOS app declares them.
    @Suppress("MagicNumber")
    val defaultProfile: ReminderProfile
        get() = when (this) {
            LEGAL, INSURANCE -> ReminderProfile(listOf(30, 7, 0), Consequence.LEGAL)
            TAX -> ReminderProfile(listOf(14, 1), Consequence.FINANCIAL)
            HEALTH -> ReminderProfile(listOf(7, 1), Consequence.HEALTH, graceDays = 7)
            RENEWAL -> ReminderProfile(listOf(60, 30), Consequence.LEGAL)
            PAYMENT -> ReminderProfile(listOf(2, 0), Consequence.FINANCIAL)
            MAINTENANCE -> ReminderProfile(listOf(14, 1), Consequence.COMFORT, graceDays = 14)
            ROUTINE -> ReminderProfile(listOf(0), Consequence.COMFORT, graceDays = 3)
        }

    companion object {
        /** What an unknown stored kind behaves as: the loudest ([Consequence.LOUDEST]). */
        val LOUDEST: ObligationKind = LEGAL

        /**
         * A stored kind: unknown or missing reads as [LOUDEST]. The stored text is kept as it was,
         * never written back downgraded.
         */
        fun stored(raw: String?): ObligationKind = entries.firstOrNull { it.raw == raw } ?: LOUDEST
    }
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
