package com.ar.dosarcusina.core.wording

import com.ar.dosarcusina.core.attention.DueDate
import com.ar.dosarcusina.core.attention.DueLine
import com.ar.dosarcusina.core.attention.DueVerb
import com.ar.dosarcusina.core.attention.DueWhen
import com.ar.dosarcusina.core.attention.TravelLines
import com.ar.dosarcusina.core.urgency.Consequence
import com.ar.dosarcusina.core.urgency.UrgencyRule
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationKind

/**
 * When something is due, in plain words, as the iOS app's `DueWording`
 * (ios/DosarCuSina/Services/Attention/DueWording.swift): „Expiră în 5 zile · 7 noiembrie”. The
 * words are written from the data `core.attention` says first ([DueLine], [TravelLines]).
 */
object DueWording {
    /** „în 5 zile”, „într-o lună”, „azi”, „mâine”, „ieri”, „acum 3 zile”, counted from [today]. */
    fun relative(daysRemaining: Int, today: CalendarDay): String = when (DueWhen.of(daysRemaining)) {
        DueWhen.YESTERDAY -> Word.app("ieri").written()
        DueWhen.AGO -> Word.app("acum %@", Word.text(DurationWording.distance(daysRemaining, today))).written()
        DueWhen.TODAY -> Word.app("azi").written()
        DueWhen.TOMORROW -> Word.app("mâine").written()
        DueWhen.INSIDE -> DurationWording.inside(DurationWording.distance(daysRemaining, today))
    }

    /** „7 noiembrie”, with the year when it isn't this year: „7 noiembrie 2027”. */
    fun date(date: DueDate): String =
        if (date.showsYear) DosarFormat.longDay(date.day) else DosarFormat.dayMonth(date.day)

    /** The verb a line starts with: „Expiră”, „De plătit”, „De făcut”, or in the past once its day has passed. */
    fun verb(verb: DueVerb, isLate: Boolean): String = Word.app(
        when (verb) {
            DueVerb.EXPIRES -> if (isLate) "A expirat" else "Expiră"
            DueVerb.PAY -> if (isLate) "Trebuia plătit" else "De plătit"
            DueVerb.DO -> if (isLate) "Trebuia făcut" else "De făcut"
        },
    ).written()

    /** „Expiră în 5 zile · 7 noiembrie”, „De plătit azi · 2 noiembrie”, „A expirat acum 3 zile · 30 octombrie”. */
    fun line(line: DueLine, today: CalendarDay): String =
        "${verb(line.verb, line.isLate)} ${relative(line.daysRemaining, today)} · ${date(line.date)}"

    /** The due line of a deadline of [kind] due on [due], on [today]. */
    fun line(kind: ObligationKind, due: CalendarDay, today: CalendarDay): String =
        line(DueLine.of(kind, due, today), today)

    /**
     * A passport's two lines instead of one due line: „Expiră pe 12 august 2027” and „Bun de
     * călătorit până pe 12 februarie 2027”; past the cut-off „A fost bun de călătorit până pe …”;
     * once it has expired, only „A expirat pe …”.
     */
    fun travelLines(lines: TravelLines): List<String> = when (lines) {
        is TravelLines.Expired -> listOf(Word.app("A expirat pe %@", Word.text(date(lines.expiry))).written())
        is TravelLines.Valid -> listOf(
            Word.app("Expiră pe %@", Word.text(date(lines.expiry))).written(),
            Word.app(
                if (lines.stillGoodForTravel) "Bun de călătorit până pe %@" else "A fost bun de călătorit până pe %@",
                Word.text(date(lines.goodForTravelUntil)),
            ).written(),
        )
    }

    /** A passport's lines, or null for a document without a travel cut-off, which keeps its [line]. */
    fun travelLines(due: CalendarDay, rule: UrgencyRule, today: CalendarDay): List<String>? =
        TravelLines.of(due, rule, today)?.let(::travelLines)

    /** Why it matters, in one plain sentence, from the consequence. */
    fun consequence(consequence: Consequence): String = Word.app(
        when (consequence) {
            Consequence.LEGAL -> "Dacă trece termenul, riști amendă sau probleme la control."
            Consequence.FINANCIAL -> "Dacă întârzii, pot veni penalități sau bani pierduți."
            Consequence.HEALTH -> "Ține de sănătate: e mai bine făcut la timp."
            Consequence.COMFORT -> "Nu e grav dacă întârzie puțin."
        },
    ).written()
}
