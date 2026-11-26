package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationStatus

/**
 * The urgency rule behind a date a page shows (an expiry, a warranty's or a contract's end), as
 * the iOS app's `DateUrgency.rule(for:on:)`
 * (ios/DosarCuSina/Services/Attention/DateUrgency.swift), so every badge, hero line and form
 * says what Urmează says. A date is as urgent as the deadline it drives: the rule of the
 * section's open deadline due that day, by the reminders of its cycle. A date no deadline
 * reminds about is urgent only on the day and once it has passed.
 */
object DateUrgency {
    /**
     * The rule for [day] shown on a section whose deadlines are [deadlines] (in any order; none
     * when the section isn't there). Of two open deadlines due that day, the first by due day,
     * as the section lists them, decides.
     */
    fun rule(day: CalendarDay, deadlines: List<DeadlineSnapshot>): UrgencyRule =
        deadlines.filter { it.status == ObligationStatus.ACTIVE }
            .sortedBy { it.dueDay }
            .firstOrNull { it.dueDay == day }
            ?.urgencyRule
            ?: UrgencyRule.NO_REMINDERS
}
