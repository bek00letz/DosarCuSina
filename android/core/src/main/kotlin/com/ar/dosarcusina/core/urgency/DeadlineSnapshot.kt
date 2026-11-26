package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.CalendarDay
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * Whether a deadline is running, as the iOS app's `ObligationStatus`. The stored texts are part
 * of the `.dosar` contract.
 */
enum class DeadlineStatus(val stored: String) {
    ACTIVE("active"),

    /** Temporarily off: no reminders, hidden from attention, kept in the list. */
    PAUSED("paused"),

    /** A one-off deadline that was completed. */
    DONE("done"),

    /** Kept for history only. */
    ARCHIVED("archived"),
    ;

    companion object {
        /**
         * What an unknown stored status (from a newer build or archive) behaves as: the loudest,
         * so a deadline never goes quiet because this build can't read its status.
         */
        val LOUDEST: DeadlineStatus = ACTIVE

        /** A stored value: unknown or missing reads as [LOUDEST]. */
        fun stored(raw: String?): DeadlineStatus = entries.firstOrNull { it.stored == raw } ?: LOUDEST
    }
}

/**
 * A plain copy of one deadline with what urgency, the reminder plan and the badge read, as the
 * part of the iOS app's `ObligationSnapshot` (ios/DosarCuSina/Services/SideEffects/ObligationSnapshot.swift)
 * these rules use. Built once per pass, so the rules never touch the database. No words: what a
 * reminder says comes from the strings, with the deadline's title, where it is shown.
 *
 * The store fills it (Phase 4's side effects, from every deadline that isn't archived, examples
 * left out of everything that leaves the app).
 */
data class DeadlineSnapshot(
    val id: UUID,
    val status: DeadlineStatus,
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
 * `AttentionModel.digest(…).needsActionCount`: the badge, and the attention list's count when it
 * is ported, read it here.
 */
object NeedsAction {
    /** The count on [today]. */
    fun count(deadlines: List<DeadlineSnapshot>, today: CalendarDay): Int =
        deadlines.count { it.status == DeadlineStatus.ACTIVE && !it.isSnoozed(today) && it.urgency(today).isAlarming }
}
