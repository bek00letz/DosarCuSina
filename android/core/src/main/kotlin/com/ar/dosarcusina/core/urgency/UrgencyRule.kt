package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.CalendarDay

/**
 * The one rule for how urgent a deadline is, from its reminder profile, as the iOS app's
 * `UrgencyRule` (ios/Shared/Urgency.swift):
 * - late within its grace days is calm ([AttentionUrgency.WITHIN_GRACE]), later than that is overdue;
 * - it needs the person from the day its first reminder goes out, but never earlier than its
 *   consequence's window (an identity card that reminds three months ahead joins „Acum” only in
 *   its last month);
 * - a document that stops being good for travel before it expires (a passport, six months
 *   before) has a travel cut-off: its reminders count back from the cut-off, and from the
 *   cut-off on it needs the person, whatever its consequence's window;
 * - otherwise it is upcoming within a month (of its cut-off, when it has one), later after that.
 *
 * Every length is held to what the app counts with ([ReminderLead.bounded]), however it was made.
 * Every surface (Urmează, boxes, badges, a deadline's page, the widget, reminders) asks this rule;
 * none compares a number of days with a threshold of its own.
 */
class UrgencyRule(graceDays: Int, firstLeadDays: Int, maxWindowDays: Int, travelMarginDays: Int = 0) {
    /** Days after the due day that are still fine. */
    val graceDays: Int = ReminderLead.bounded(graceDays)

    /**
     * The earliest reminder, in days before the day reminders count from (the travel cut-off
     * when there is one, else the due day); 0 when it reminds only on that day.
     */
    val firstLeadDays: Int = ReminderLead.bounded(firstLeadDays)

    /** The furthest ahead its consequence lets it ask for attention, in days (30 is a month). */
    val maxWindowDays: Int = ReminderLead.bounded(maxWindowDays)

    /**
     * How long before the due day the document stops being good for travel, in days (whole
     * months as calendar months, like a lead: 180 is six months); 0 when it is good for travel
     * until it expires. Declared by the document type, never chosen by hand.
     */
    val travelMarginDays: Int = ReminderLead.bounded(travelMarginDays)

    /**
     * The last day a document with a travel margin is good for travel („Bun de călătorit până
     * pe …”): the margin before its due day. Null when it is good for travel until it expires.
     */
    fun travelCutoff(due: CalendarDay): CalendarDay? =
        if (travelMarginDays > 0) ReminderLead.of(travelMarginDays).dayBefore(due) else null

    /** The day its reminders count back from: the travel cut-off, else the due day. */
    fun reminderAnchor(due: CalendarDay): CalendarDay = travelCutoff(due) ?: due

    /**
     * The first day it needs the person: the later of its first reminder (at least the day
     * before) and its consequence's window, and never later than its travel cut-off. A rule with
     * no window and no cut-off starts on the due day.
     */
    fun attentionStart(due: CalendarDay): CalendarDay {
        val cutoff = travelCutoff(due)
        if (maxWindowDays <= 0) return cutoff ?: due
        val reminded = ReminderLead.of(maxOf(firstLeadDays, 1)).dayBefore(reminderAnchor(due))
        val window = ReminderLead.of(maxWindowDays).dayBefore(due)
        val capped = maxOf(reminded, window)
        return if (cutoff != null) minOf(capped, cutoff) else capped
    }

    /** How many days ahead of [due] it needs the person. */
    fun windowDays(due: CalendarDay): Int = attentionStart(due).daysTo(due)

    /** How urgent a deadline due on [due] is on [today]. */
    fun urgency(due: CalendarDay, today: CalendarDay): AttentionUrgency {
        val days = today.daysTo(due)
        return when {
            days < 0 -> if (-days <= graceDays) AttentionUrgency.WITHIN_GRACE else AttentionUrgency.OVERDUE
            days == 0 -> AttentionUrgency.TODAY
            today >= attentionStart(due) -> AttentionUrgency.SOON
            today.daysTo(reminderAnchor(due)) <= UPCOMING_WINDOW_DAYS -> AttentionUrgency.UPCOMING
            else -> AttentionUrgency.LATER
        }
    }

    override fun equals(other: Any?): Boolean =
        other is UrgencyRule && other.graceDays == graceDays && other.firstLeadDays == firstLeadDays &&
            other.maxWindowDays == maxWindowDays && other.travelMarginDays == travelMarginDays

    override fun hashCode(): Int = listOf(graceDays, firstLeadDays, maxWindowDays, travelMarginDays).hashCode()

    override fun toString(): String =
        "UrgencyRule(graceDays=$graceDays, firstLeadDays=$firstLeadDays, maxWindowDays=$maxWindowDays, " +
            "travelMarginDays=$travelMarginDays)"

    companion object {
        /** What „Curând” covers: the next month. */
        const val UPCOMING_WINDOW_DAYS: Int = 30

        /** A date nothing reminds about: urgent only on the day and once it has passed. */
        val NO_REMINDERS: UrgencyRule = UrgencyRule(graceDays = 0, firstLeadDays = 0, maxWindowDays = 0)
    }
}
