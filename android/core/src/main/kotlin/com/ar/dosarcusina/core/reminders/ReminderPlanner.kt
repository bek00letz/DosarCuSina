package com.ar.dosarcusina.core.reminders

import com.ar.dosarcusina.core.urgency.DeadlineSnapshot
import com.ar.dosarcusina.core.urgency.ReminderLead
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationStatus
import java.time.Instant
import java.time.ZoneId

/**
 * Works out every reminder that should be pending, from deadline snapshots, as the iOS app's
 * `ReminderPlanner` (ios/DosarCuSina/Services/Reminders/ReminderPlanner.swift). Pure: no
 * notification manager, no database, no clock and no time zone of its own (the pass reads the
 * zone once as it starts and hands it in), so every rule is tested.
 *
 * - Each lead of the profile reminds once, at the reminder time. A lead of whole months is
 *   calendar months ([ReminderLead]).
 * - A document with a travel cut-off (a passport) counts its leads back from the cut-off. The
 *   follow-up after it lapses stays the day after it expires.
 * - A deadline that became known after its warnings had passed gets one catch-up reminder at the
 *   next reminder time, so it is never silent.
 * - A snooze holds back every reminder before the day it ends, and reminds on that day.
 * - One reminder per moment: when two fall at the same moment, the first by [ReminderPurpose]'s
 *   order is kept (a lead, the follow-up, the catch-up, the snooze), and of two of one purpose the
 *   one whose identifier sorts first.
 * - When there are more than [limit], every deadline's next reminder comes first, most
 *   consequential first, then the rest by time, and the last place goes to a reminder to open
 *   the app, just before the planned ones run out.
 */
object ReminderPlanner {
    const val IDENTIFIER_PREFIX: String = "obligation."

    /** The one follow-up after the due day: `obligation.<id>.lapse`. */
    const val LAPSE_SUFFIX: String = "lapse"

    /** The one reminder for warnings that passed before the deadline was known. */
    const val CATCH_UP_SUFFIX: String = "catchup"

    /** The reminder on the day a snooze ends. */
    const val SNOOZE_SUFFIX: String = "snooze"

    /** The „open the app so reminders continue” reminder, under the same prefix so it is owned like any other. */
    const val CONTINUE_IDENTIFIER: String = IDENTIFIER_PREFIX + "continue"

    /** The iPhone keeps at most 64 pending requests per app; the plan leaves room for the system. */
    const val DEFAULT_LIMIT: Int = 60

    /** How long before the planned reminders run out the „open the app” reminder comes, at the latest. */
    private const val CONTINUE_LEAD_SECONDS = 30L * 60


    /** Every reminder that should be pending at [now], in order of time (then identifier). */
    fun plan(
        deadlines: List<DeadlineSnapshot>,
        now: Instant,
        zone: ZoneId,
        defaultMinuteOfDay: Int = ReminderClock.DEFAULT_MINUTE_OF_DAY,
        limit: Int = DEFAULT_LIMIT,
    ): List<PlannedReminder> {
        val perDeadline = deadlines
            .filter { it.status == ObligationStatus.ACTIVE && !it.isExample }
            .mapNotNull { deadline ->
                val reminders = candidates(deadline, now, zone, defaultMinuteOfDay).sortedWith(BY_TIME)
                if (reminders.isEmpty()) null else deadline.reminders.consequence.weight to reminders
            }
        val all = perDeadline.flatMap { it.second }
        if (all.size <= limit) return all.sortedWith(BY_TIME)

        // Too many for the phone: every deadline's next reminder first, the most consequential
        // first, then everything else by time.
        val firsts = perDeadline
            .sortedWith(
                compareByDescending<Pair<Int, List<PlannedReminder>>> { it.first }.thenBy(BY_TIME) { it.second[0] },
            )
            .map { it.second[0] }
        val rest = perDeadline.flatMap { it.second.drop(1) }.sortedWith(BY_TIME)
        val ordered = firsts + rest
        val kept = ordered.take(maxOf(0, limit - 1))
        val dropped = ordered.drop(kept.size)

        val runsOut = dropped.minOfOrNull { it.fireAt }
        val continuing = runsOut?.let { continueReminder(it, now, zone, defaultMinuteOfDay) }
        return kept.sortedWith(BY_TIME) + listOfNotNull(continuing)
    }

    /** One reminder a deadline wants: what it is for, the day it is planned for, its identifier's suffix. */
    private data class Wanted(val purpose: ReminderPurpose, val day: CalendarDay, val suffix: String)

    /** When one deadline's reminders fire: its reminder time in the pass's zone, after now, held back by a snooze. */
    private class Clock(deadline: DeadlineSnapshot, val now: Instant, val zone: ZoneId, defaultMinuteOfDay: Int) {
        val minute: Int = deadline.reminderMinuteOfDay ?: defaultMinuteOfDay
        val snoozeEnds: Instant? = deadline.snoozeEnds(now, zone)

        fun fire(day: CalendarDay): Instant = ReminderClock.moment(day, minute, zone)

        fun isAhead(day: CalendarDay): Boolean = fire(day).isAfter(now)

        /** Before the moment its snooze ends. */
        fun isHeld(day: CalendarDay): Boolean = snoozeEnds?.let { fire(day).isBefore(it) } ?: false
    }

    /** Every reminder one deadline wants pending, one per moment, in no particular order. */
    internal fun candidates(
        deadline: DeadlineSnapshot,
        now: Instant,
        zone: ZoneId,
        defaultMinuteOfDay: Int,
    ): List<PlannedReminder> {
        val clock = Clock(deadline, now, zone, defaultMinuteOfDay)
        val once = listOfNotNull(catchUp(deadline, clock), followUp(deadline, clock), snooze(deadline, clock))
        val atMoment = LinkedHashMap<Instant, PlannedReminder>()
        for (want in leads(deadline, clock) + once) {
            val fire = clock.fire(want.day)
            val made = reminder(deadline, want, fire, zone)
            val kept = atMoment[fire]
            if (kept == null || precedes(made, kept)) atMoment[fire] = made
        }
        return atMoment.values.toList()
    }

    /** Each lead once, from the travel cut-off when there is one, while ahead and not held back by a snooze. */
    private fun leads(deadline: DeadlineSnapshot, clock: Clock): List<Wanted> {
        val cutoff = deadline.reminders.urgencyRule.travelCutoff(deadline.dueDay)
        val purpose = if (cutoff != null) ReminderPurpose.TRAVEL_LEAD else ReminderPurpose.LEAD
        val prefix = if (cutoff != null) ReminderIdentifiers.TRAVEL_LEAD else ReminderIdentifiers.DUE_LEAD
        val anchor = cutoff ?: deadline.dueDay
        return deadline.reminders.leadDays
            .map { offset -> Wanted(purpose, ReminderLead.of(offset).dayBefore(anchor), prefix + offset) }
            .filter { clock.isAhead(it.day) && !clock.isHeld(it.day) }
    }

    /** The one catch-up, while nothing is snoozed. */
    private fun catchUp(deadline: DeadlineSnapshot, clock: Clock): Wanted? {
        if (clock.snoozeEnds != null) return null
        return catchUpDay(deadline, clock.minute, clock.zone)
            ?.takeIf(clock::isAhead)
            ?.let { Wanted(ReminderPurpose.CATCH_UP, it, CATCH_UP_SUFFIX) }
    }

    /** „Follow up after it lapses”: one reminder the day after the due day, then silence. */
    private fun followUp(deadline: DeadlineSnapshot, clock: Clock): Wanted? {
        if (!deadline.reminders.followUpAfterLapse) return null
        val day = deadline.dueDay.addingDays(1)
        val wanted = clock.isAhead(day) && !clock.isHeld(day)
        return if (wanted) Wanted(ReminderPurpose.FOLLOW_UP, day, LAPSE_SUFFIX) else null
    }

    /** The day a snooze ends, while it is still ahead. */
    private fun snooze(deadline: DeadlineSnapshot, clock: Clock): Wanted? {
        val day = deadline.snoozedUntil
        if (clock.snoozeEnds == null || day == null) return null
        return if (clock.isAhead(day)) Wanted(ReminderPurpose.SNOOZE, day, SNOOZE_SUFFIX) else null
    }

    /** Of two reminders of one deadline at one moment, whether [made] is the one kept over [kept]. */
    private fun precedes(made: PlannedReminder, kept: PlannedReminder): Boolean {
        val byPurpose = rank(made.purpose).compareTo(rank(kept.purpose))
        return byPurpose < 0 || (byPurpose == 0 && made.identifier < kept.identifier)
    }

    /**
     * Which of two at one moment is kept: a lead (before the due day or a travel cut-off), then
     * the follow-up, the catch-up, the snooze.
     */
    private val PRECEDENCE: List<Set<ReminderPurpose>> = listOf(
        setOf(ReminderPurpose.LEAD, ReminderPurpose.TRAVEL_LEAD),
        setOf(ReminderPurpose.FOLLOW_UP),
        setOf(ReminderPurpose.CATCH_UP),
        setOf(ReminderPurpose.SNOOZE),
    )

    private fun rank(purpose: ReminderPurpose): Int = PRECEDENCE.indexOfFirst { purpose in it }

    /**
     * The day of the one catch-up reminder for a deadline whose warnings (leads before the day
     * they count from) had all passed by the time it became known: the first reminder time after
     * that, as long as it falls before that day, or on it when the profile doesn't remind on the
     * day itself. Anchored to when the cycle became known, so it fires once and never repeats.
     */
    internal fun catchUpDay(deadline: DeadlineSnapshot, minuteOfDay: Int, zone: ZoneId): CalendarDay? {
        val knownSince = deadline.cycleKnownSince ?: return null
        val profile = deadline.reminders
        val warnings = profile.leadDays.filter { it > 0 }
        if (warnings.isEmpty()) return null
        val anchor = profile.urgencyRule.reminderAnchor(deadline.dueDay)
        val warningFires = warnings.map { lead ->
            ReminderClock.moment(ReminderLead.of(lead).dayBefore(anchor), minuteOfDay, zone)
        }
        if (warningFires.any { it.isAfter(knownSince) }) return null

        var day = CalendarDay.of(knownSince, zone)
        if (!ReminderClock.moment(day, minuteOfDay, zone).isAfter(knownSince)) day = day.addingDays(1)
        val remindsOnTheDay = 0 in profile.leadDays
        val beforeAnchor = day < anchor || (day == anchor && !remindsOnTheDay)
        // Past a travel cut-off the document still expires: one reminder by the day it does.
        val beforeExpiry = anchor < deadline.dueDay && day <= deadline.dueDay
        return if (beforeAnchor || beforeExpiry) day else null
    }

    /**
     * The „open the app” reminder: the reminder time the day before the planned reminders run
     * out, or half an hour before when that has passed.
     */
    internal fun continueReminder(runsOut: Instant, now: Instant, zone: ZoneId, minuteOfDay: Int): PlannedReminder? {
        val dayBefore = CalendarDay.of(runsOut, zone).addingDays(-1)
        val choices = listOf(
            ReminderClock.moment(dayBefore, minuteOfDay, zone),
            runsOut.minusSeconds(CONTINUE_LEAD_SECONDS),
        )
        val fire = choices.firstOrNull { it.isAfter(now) && it.isBefore(runsOut) } ?: return null
        return PlannedReminder(
            identifier = CONTINUE_IDENTIFIER,
            purpose = ReminderPurpose.CONTINUE,
            obligationId = null,
            cycle = null,
            day = null,
            fireAt = fire,
            trigger = TriggerParts.of(fire, zone),
        )
    }

    /** The reminder of [deadline] [want] asks for, at [fire]. */
    private fun reminder(deadline: DeadlineSnapshot, want: Wanted, fire: Instant, zone: ZoneId): PlannedReminder {
        val lastDays = want.day.daysTo(deadline.dueDay) <= 1
        return PlannedReminder(
            identifier = ReminderIdentifiers.make(deadline.id, want.suffix),
            purpose = want.purpose,
            obligationId = deadline.id,
            cycle = deadline.dueDay,
            day = want.day,
            fireAt = fire,
            trigger = TriggerParts.of(fire, zone),
            isTimeSensitive = lastDays && deadline.reminders.consequence.allowsTimeSensitiveReminders,
            isProtected = deadline.isSensitive,
            closesInTheApp = deadline.closesInTheApp,
        )
    }

    /** In order of time, then of identifier. */
    internal val BY_TIME: Comparator<PlannedReminder> =
        compareBy<PlannedReminder> { it.fireAt }.thenBy { it.identifier }
}
