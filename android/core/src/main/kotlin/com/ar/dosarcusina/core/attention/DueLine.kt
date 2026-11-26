package com.ar.dosarcusina.core.attention

import com.ar.dosarcusina.core.urgency.UrgencyRule
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationKind

// When something is due, as kinds and days, the data part of the iOS app's `DueWording`
// (ios/DosarCuSina/Services/Attention/DueWording.swift): which verb, how far, which day, and a
// passport's two lines. Phase 4 writes them („Expiră în 5 zile · 7 noiembrie”).

/** The verb a due line starts with, by what kind of duty the deadline is (`DueWording.Verb`). */
enum class DueVerb {
    /** „Expiră”, past „A expirat”: legal duties, insurance, renewals. */
    EXPIRES,

    /** „De plătit”, past „Trebuia plătit”: taxes and payments. */
    PAY,

    /** „De făcut”, past „Trebuia făcut”: health, upkeep and chores. */
    DO,
    ;

    companion object {
        fun of(kind: ObligationKind): DueVerb = when (kind) {
            ObligationKind.LEGAL, ObligationKind.INSURANCE, ObligationKind.RENEWAL -> EXPIRES
            ObligationKind.TAX, ObligationKind.PAYMENT -> PAY
            ObligationKind.HEALTH, ObligationKind.MAINTENANCE, ObligationKind.ROUTINE -> DO
        }
    }
}

/**
 * How far a due day is, as the line says it (`DueWording.When`): „ieri”, „acum 3 zile”, „azi”,
 * „mâine”, „în 5 zile”. [AGO] and [INSIDE] say a distance in days, weeks, months and years
 * (`DurationWording.distance`, from today).
 */
enum class DueWhen {
    YESTERDAY,
    AGO,
    TODAY,
    TOMORROW,
    INSIDE,
    ;

    companion object {
        fun of(daysRemaining: Int): DueWhen = when {
            daysRemaining == -1 -> YESTERDAY
            daysRemaining < 0 -> AGO
            daysRemaining == 0 -> TODAY
            daysRemaining == 1 -> TOMORROW
            else -> INSIDE
        }
    }
}

/** A day as a due line writes it: „7 noiembrie”, with its year when it isn't this year's. */
data class DueDate(val day: CalendarDay, val showsYear: Boolean) {
    companion object {
        fun of(day: CalendarDay, today: CalendarDay): DueDate = DueDate(day, showsYear = day.year != today.year)
    }
}

/** A deadline's due line, „Expiră în 5 zile · 7 noiembrie”, as kinds and days. */
data class DueLine(
    val verb: DueVerb,
    /** Its day has passed: the verb in the past („A expirat”). */
    val isLate: Boolean,
    val whenDue: DueWhen,
    /** Whole days until it is due; negative once it has passed. */
    val daysRemaining: Int,
    val date: DueDate,
) {
    companion object {
        /** The line of a deadline of [kind] due on [due], on [today]. */
        fun of(kind: ObligationKind, due: CalendarDay, today: CalendarDay): DueLine {
            val days = today.daysTo(due)
            return DueLine(DueVerb.of(kind), days < 0, DueWhen.of(days), days, DueDate.of(due, today))
        }
    }
}

/**
 * A document with a travel cut-off (a passport) shows both its dates instead of one due line
 * (`DueWording.travelLines`): „Expiră pe 12 august 2027” and „Bun de călătorit până pe 12 februarie
 * 2027”; past the cut-off, „A fost bun de călătorit până pe …”; once it has expired, only „A
 * expirat pe …”.
 */
sealed interface TravelLines {
    /** It has expired: one line, „A expirat pe …”. */
    data class Expired(val expiry: DueDate) : TravelLines

    /** It hasn't: its expiry, then the last day it is good for travel, still ahead or passed. */
    data class Valid(val expiry: DueDate, val goodForTravelUntil: DueDate, val stillGoodForTravel: Boolean) :
        TravelLines

    companion object {
        /**
         * The lines of a document due on [due] with [rule], on [today]; null without a cut-off,
         * which keeps its [DueLine].
         */
        fun of(due: CalendarDay, rule: UrgencyRule, today: CalendarDay): TravelLines? {
            val cutoff = rule.travelCutoff(due) ?: return null
            val expiry = DueDate.of(due, today)
            return if (today > due) {
                Expired(expiry)
            } else {
                Valid(expiry, DueDate.of(cutoff, today), stillGoodForTravel = today <= cutoff)
            }
        }
    }
}
