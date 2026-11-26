package com.ar.dosarcusina.core.attention

import com.ar.dosarcusina.core.subscriptions.MissingBillNote
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.RecurrenceInterval
import java.util.UUID

/**
 * A calm note in Urmează's „Din timp”, as the iOS app's `AttentionNote`
 * (ios/DosarCuSina/Services/Attention/MissingBills.swift): something worth knowing, with nothing
 * due. It never notifies, never counts on the badge and never reaches widgets. Kinds and days only:
 * what a note says is the screens' (Phase 4).
 */
sealed interface CalmNote {
    /** When a bill was expected; null for what has no day (the suggestions), which goes last. */
    val expectedDay: CalendarDay?

    /** A bill that hasn't come when it usually does; tapping it opens [sectionId], the subscription. */
    data class MissingBill(val note: MissingBillNote) : CalmNote {
        override val expectedDay: CalendarDay get() = note.missing.expectedDay

        /** The subscription it is about. */
        val sectionId: UUID get() = note.id

        /** Its subscription is locked: the note names nothing (the iOS app's „O factură n-a venit încă”). */
        val isLocked: Boolean get() = note.isSensitive

        /** Its bills come every week: it says „săptămâna asta”. */
        val isWeekly: Boolean get() = isWeekly(note.missing.cycle)

        /**
         * How many months its bills come apart, which picks the words of its title by the String
         * Catalog's plural forms („luna asta” for one, „încă” for more); 0 for a cycle of days or
         * weeks, which has no whole month and so never says „luna asta”.
         */
        val monthsApart: Int get() = monthsApart(note.missing.cycle)
    }

    /**
     * Every suggestion for the binder waiting (repair steps that are suggestions, not corrections),
     * as one note: how many, and what they are about ([topics], each step's own words), never the
     * names of what they would move, so it says nothing a locked section wouldn't. Tapping it opens
     * the suggestions' page.
     */
    data class Suggestions(val count: Int, val topics: List<String>) : CalmNote {
        override val expectedDay: CalendarDay? get() = null
    }

    companion object {
        /** Whether a bill that comes every [cycle] comes every week. */
        fun isWeekly(cycle: RecurrenceInterval): Boolean =
            cycle.unit == RecurrenceInterval.Unit.WEEK && cycle.every == 1

        /** How many months a cycle's bills come apart: a month's or a year's in months; 0 for days or weeks. */
        fun monthsApart(cycle: RecurrenceInterval): Int = when (cycle.unit) {
            RecurrenceInterval.Unit.MONTH -> cycle.every
            RecurrenceInterval.Unit.YEAR -> cycle.every * MONTHS_IN_A_YEAR
            RecurrenceInterval.Unit.DAY, RecurrenceInterval.Unit.WEEK -> 0
        }

        private const val MONTHS_IN_A_YEAR = 12
    }
}

/**
 * The calm notes of „Din timp”, in the order they show: the bills that haven't come, oldest
 * expected first ([missingBills], as [com.ar.dosarcusina.core.subscriptions.MissingBills.find]
 * gives them, the one count of them), then the suggestions.
 */
fun AttentionModel.calmNotes(
    missingBills: List<MissingBillNote>,
    suggestions: CalmNote.Suggestions?,
): List<CalmNote> = missingBills.map(CalmNote::MissingBill) + listOfNotNull(suggestions)

/** One note for every suggestion waiting: how many, and what they are about. Null with none. */
fun AttentionModel.suggestionNote(count: Int, topics: List<String>): CalmNote.Suggestions? =
    if (count > 0) CalmNote.Suggestions(count, topics) else null
