package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.CalendarDay
import kotlin.math.abs

/**
 * How a deadline reminds, as the iOS app's `ReminderProfile`
 * (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift): how far ahead, how much missing it
 * costs, how late is still fine, whether to nudge once after the due day passes, and, for a
 * document that stops being good for travel before it expires, how long before.
 *
 * This is the profile the rules read. The archive's `ReminderProfile` is its stored form, which
 * keeps a consequence a newer build wrote as written; the store reads one into this with
 * [Consequence.stored]. Every length is held to what the app counts with ([ReminderLead.bounded]),
 * and a lead counts by its size, each once, largest first.
 */
class ReminderProfile(
    leadDays: List<Int>,
    val consequence: Consequence,
    graceDays: Int = 0,
    followUpAfterLapse: Boolean? = null,
    travelMarginDays: Int = 0,
) {
    /** Days before the due day to remind, largest first; 0 is the due day (or the travel cut-off). */
    val leadDays: List<Int> =
        leadDays.map { abs(it.toLong()).coerceAtMost(ReminderLead.LONGEST_DAYS.toLong()).toInt() }
            .distinct()
            .sortedDescending()

    /** Days after the due day that are still acceptable: late, but not alarming. */
    val graceDays: Int = ReminderLead.bounded(graceDays)

    /** One reminder the day after the due day while it is still open, then silence. */
    val followUpAfterLapse: Boolean = followUpAfterLapse ?: consequence.followsUpByDefault

    /** How long before its due day the document stops being good for travel, in days; 0 for most. */
    val travelMarginDays: Int = ReminderLead.bounded(travelMarginDays)

    /**
     * How urgent the deadline is on every surface: it needs the person from its earliest
     * reminder, capped by what its consequence warrants, from its travel cut-off when it has
     * one, and late within its grace is calm.
     */
    val urgencyRule: UrgencyRule
        get() = UrgencyRule(
            graceDays = graceDays,
            firstLeadDays = leadDays.firstOrNull() ?: 0,
            maxWindowDays = consequence.maxAttentionWindowDays,
            travelMarginDays = travelMarginDays,
        )

    /** It stops being good for travel before it expires (a passport): its leads count from that day. */
    val hasTravelCutoff: Boolean get() = travelMarginDays > 0

    /** The same profile with other leads, everything else kept (the travel margin included). */
    fun withLeadDays(leads: List<Int>): ReminderProfile =
        ReminderProfile(leads, consequence, graceDays, followUpAfterLapse, travelMarginDays)

    /**
     * The profile as the cycle that began on [cycleStart] and is due on [due] uses it, as the iOS
     * app's `forCycle(startingOn:due:)` (ios/DosarCuSina/Services/Obligations/CycleReminders.swift).
     *
     * A lead longer than the cycle would fall on or before the day the cycle began (a week's
     * warning on something that repeats every 3 days): it is left out of that cycle, so it never
     * fires in the past, never counts as a warning missed and never makes the deadline look
     * urgent for the whole cycle. When none fits, the deadline reminds on the day itself. A null
     * [cycleStart] (a rule with no set length, or one that doesn't repeat) keeps every lead.
     *
     * [cycleStart] is `RecurrenceEngine.cycleStart(endingOn: due, rule:)`; the store fills a
     * snapshot's reminders with this, never with the stored profile.
     */
    fun forCycle(cycleStart: CalendarDay?, due: CalendarDay): ReminderProfile {
        if (cycleStart == null) return this
        val fitting = leadDays.filter { fits(it, due, cycleStart) }
        if (fitting == leadDays) return this
        return withLeadDays(fitting.ifEmpty { listOf(0) })
    }

    /** Whether a lead of [days] reminds within the cycle that began on [cycleStart] (the day itself always does). */
    fun fits(days: Int, due: CalendarDay, cycleStart: CalendarDay?): Boolean {
        if (days <= 0 || cycleStart == null) return true
        return ReminderLead.of(days).dayBefore(urgencyRule.reminderAnchor(due)) > cycleStart
    }

    override fun equals(other: Any?): Boolean =
        other is ReminderProfile && other.leadDays == leadDays && other.consequence == consequence &&
            other.graceDays == graceDays && other.followUpAfterLapse == followUpAfterLapse &&
            other.travelMarginDays == travelMarginDays

    override fun hashCode(): Int =
        listOf(leadDays, consequence, graceDays, followUpAfterLapse, travelMarginDays).hashCode()

    override fun toString(): String =
        "ReminderProfile(leadDays=$leadDays, consequence=${consequence.stored}, graceDays=$graceDays, " +
            "followUpAfterLapse=$followUpAfterLapse, travelMarginDays=$travelMarginDays)"
}
