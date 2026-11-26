package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.CalendarDay

/**
 * Whether something is still valid on a day, as the iOS app's `DueDayValidity`
 * (ios/DosarCuSina/Models/Obligations/DueDayValidity.swift): a deadline's due day is the last day
 * it is valid (an RCA due on 3 May covers 3 May). The one answer the readiness checks, a
 * deadline's validity and capture's filing read.
 */
object DueDayValidity {
    /** The due day is the last day something is valid (true), or the first day it isn't (false). */
    const val DUE_DAY_IS_LAST_VALID_DAY: Boolean = true

    /** Whether something due on [due] is still valid on [day]. */
    fun isValid(due: CalendarDay, day: CalendarDay): Boolean = if (DUE_DAY_IS_LAST_VALID_DAY) day <= due else day < due

    /** Whether something due on [due] stays valid every day up to and including [through]. */
    fun covers(through: CalendarDay, due: CalendarDay): Boolean = isValid(due, through)
}
