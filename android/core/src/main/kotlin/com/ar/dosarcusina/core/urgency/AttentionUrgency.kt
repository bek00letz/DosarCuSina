package com.ar.dosarcusina.core.urgency

/**
 * How close a due day is, in the steps every surface shows, as the iOS app's `AttentionUrgency`
 * (ios/Shared/Urgency.swift). Declared from the most urgent to the calmest, so the order of the
 * entries is the order of urgency.
 */
enum class AttentionUrgency(val stored: String) {
    /** Past due and past its grace period: shown as a problem. */
    OVERDUE("overdue"),
    TODAY("today"),

    /** Past due but within the grace the person can live with: shown calmly, not as an alarm. */
    WITHIN_GRACE("withinGrace"),

    /** Its first reminder has gone out (at most its consequence's window ahead): listed under „Acum”. */
    SOON("soon"),

    /** Within the next month, but nothing has reminded yet: listed under „Curând”. */
    UPCOMING("upcoming"),
    LATER("later"),
    ;

    /** Counted on the app's badge: late past grace, or due today. */
    val isAlarming: Boolean get() = this == OVERDUE || this == TODAY

    /** Needs the person now: listed under „Acum”, shown on its box, drawn in a warning tone. */
    val needsAttentionNow: Boolean get() = this <= SOON

    /** The tone every surface draws it in. */
    val tone: UrgencyTone
        get() = when (this) {
            OVERDUE -> UrgencyTone.OVERDUE
            TODAY, WITHIN_GRACE, SOON -> UrgencyTone.SOON
            UPCOMING, LATER -> UrgencyTone.CALM
        }
}

/**
 * The tone an urgency is drawn in, as the iOS app's `UrgencyTone`. Decided here; the screens and
 * the widget only pick their colours and symbols for it.
 */
enum class UrgencyTone(val stored: String) {
    /** Late past its grace: red, with an exclamation mark. */
    OVERDUE("overdue"),

    /** Needs the person now (due today, late within grace, or reminded): amber, with a clock. */
    SOON("soon"),

    /** Nothing to do yet. */
    CALM("calm"),
}
