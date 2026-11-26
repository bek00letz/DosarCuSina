package com.ar.dosarcusina.ui.ds

import com.ar.dosarcusina.core.readiness.ReadinessStatus
import com.ar.dosarcusina.core.urgency.UrgencyTone
import com.ar.dosarcusina.core.wording.Word

/**
 * Where something stands, as drawn: a badge's colour, symbol and words, as the iPhone app's
 * `DSStatus`. The design system draws a tone and never decides one: the tone comes from core's one
 * urgency rule ([UrgencyTone], `AttentionUrgency.tone`) or a checklist's outcome ([ReadinessStatus]).
 */
enum class DSStatus(val symbol: DSSymbol, val title: Word) {
    OVERDUE(DSSymbol.OVERDUE, Word.app("Întârziat")),
    SOON(DSSymbol.SOON, Word.app("În curând")),
    LATER(DSSymbol.CALENDAR, Word.app("Mai târziu")),
    DONE(DSSymbol.DONE, Word.app("Rezolvat")),
    ;

    companion object {
        /** How an urgency's tone is drawn. */
        fun of(tone: UrgencyTone): DSStatus = when (tone) {
            UrgencyTone.OVERDUE -> OVERDUE
            UrgencyTone.SOON -> SOON
            UrgencyTone.CALM -> LATER
        }

        /** The status a line about a due day takes its text colour from; none when nothing is needed yet. */
        fun urgent(tone: UrgencyTone): DSStatus? = if (tone == UrgencyTone.CALM) null else of(tone)

        /**
         * How a checklist's outcome is drawn, as the iPhone app's `DSStatus(readiness:)`: a problem
         * in red, worth a look in amber, ready in green; something not in the binder, an optional
         * check and one ticked by hand have no status colour (null) and stay neutral.
         */
        fun of(readiness: ReadinessStatus): DSStatus? = when (readiness) {
            ReadinessStatus.PROBLEM -> OVERDUE
            ReadinessStatus.WARNING -> SOON
            ReadinessStatus.OK -> DONE
            ReadinessStatus.MISSING, ReadinessStatus.SUGGESTED, ReadinessStatus.REMINDER -> null
        }
    }
}
