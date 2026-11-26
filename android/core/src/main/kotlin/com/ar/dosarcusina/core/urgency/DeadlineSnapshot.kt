package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.ObligationStatus
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * A plain copy of one deadline with what urgency, the reminder plan, the badge, the attention list
 * behind Urmează and the binder's box lines read, as the part of the iOS app's `ObligationSnapshot`
 * (ios/DosarCuSina/Services/SideEffects/ObligationSnapshot.swift) these rules use. Built once per
 * pass, so the rules never touch the database. None of the app's words: what a reminder or a line
 * says comes from the strings, with the deadline's [title], where it is shown.
 *
 * The store fills it (Phase 4's side effects and screens, from every deadline that isn't archived,
 * examples left out of everything that leaves the app).
 */
data class DeadlineSnapshot(
    val id: UUID,
    val status: ObligationStatus,
    val dueDay: CalendarDay,
    /** The day it comes back after „Amână”; hidden until that day starts where the phone is. */
    val snoozedUntil: CalendarDay? = null,
    /**
     * Its reminders as this cycle uses them ([ReminderProfile.forCycle]: a lead longer than how it
     * repeats is left out), never the stored profile, so reminders, urgency and the widget read
     * the same leads.
     */
    val reminders: ReminderProfile,
    /** Minutes after midnight for its reminders when it has a time of its own; null uses the general one. */
    val reminderMinuteOfDay: Int? = null,
    /** Its category is locked on this device: what shows outside the app stays generic. */
    val isSensitive: Boolean = false,
    val isExample: Boolean = false,
    /**
     * Since when the person could know this cycle as it now is (its due day, its reminders' leads
     * and that it is active): `Obligation.cycleKnownSince`. Reminders that would have fired before
     * it never had a chance, so the plan makes up for them with one catch-up reminder. Null when
     * unknown (no catch-up).
     */
    val cycleKnownSince: Instant? = null,
    /**
     * Closing it asks what nothing outside the app can ask, a new day or a new document
     * (`CompletionShape.closesOutsideTheApp` is false): its reminder's „Am rezolvat” opens the app.
     */
    val closesInTheApp: Boolean = false,
    /**
     * Its name as the person sees it („ITP”), the person's own words: the attention list orders two
     * deadlines that tie on everything else by it ([com.ar.dosarcusina.core.text.StandardOrder]).
     */
    val title: String = "",
    /** What it is expected to cost, when known: a nudge in the ranking and „Mai târziu”'s total. */
    val estimatedCost: Money? = null,
    /** The section it belongs to; null for one of the household's own (local taxes). */
    val sectionId: UUID? = null,
    /** That section's name, which orders the groups of „Curând”; null with no section. */
    val sectionName: String? = null,
) {
    /** How urgent it is on every surface: its cycle's reminders' rule. */
    val urgencyRule: UrgencyRule get() = reminders.urgencyRule

    /** How urgent it is on [today], by the one rule. */
    fun urgency(today: CalendarDay): AttentionUrgency = urgencyRule.urgency(dueDay, today)

    /** Still hidden on [today]: the day its snooze ends hasn't started yet. */
    fun isSnoozed(today: CalendarDay): Boolean = snoozedUntil?.let { today < it } ?: false

    /** The moment its snooze ends, the start of that day in [zone], while still after [now]. */
    fun snoozeEnds(now: Instant, zone: ZoneId): Instant? =
        snoozedUntil?.startOfDay(zone)?.takeIf { it.isAfter(now) }
}

/**
 * How many deadlines need doing now: active, not snoozed, and late past their grace or due today
 * ([AttentionUrgency.isAlarming]). The app's one count, as the iOS app's
 * `AttentionModel.digest(…).needsActionCount`: the badge and the attention list's count
 * ([com.ar.dosarcusina.core.attention.AttentionDigest.needsActionCount]) read it here.
 */
object NeedsAction {
    /** The count on [today]. */
    fun count(deadlines: List<DeadlineSnapshot>, today: CalendarDay): Int =
        deadlines.count { it.status == ObligationStatus.ACTIVE && !it.isSnoozed(today) && it.urgency(today).isAlarming }
}
