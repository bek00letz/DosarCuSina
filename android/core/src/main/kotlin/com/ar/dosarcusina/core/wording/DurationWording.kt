package com.ar.dosarcusina.core.wording

import com.ar.dosarcusina.core.urgency.AttentionUrgency
import com.ar.dosarcusina.core.urgency.ReminderLead
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarLocale
import java.time.DateTimeException
import java.time.Period
import kotlin.math.abs

// How long and how far, in words, as the iOS app's ios/Shared/DurationWording.swift: its counts
// are the Shared table's plural forms, so a duration reads the same on every surface and both apps.

/** „o zi”, „5 zile”, „20 de zile”: a count of one is a word, two and up are digits (`DayCount`). */
object DayCount {
    fun phrase(count: Int): String = phrase(count.toLong())

    fun phrase(count: Long): String = Word.shared("%lld zile", Word.count(magnitude(count))).written()
}

/** „un an”, „3 ani”, „20 de ani”; „o lună”, „5 luni”; „o săptămână”, „3 săptămâni” (`CalendarCount`). */
object CalendarCount {
    fun years(count: Int): String = Word.shared("%lld ani", Word.count(magnitude(count.toLong()))).written()

    fun months(count: Int): String = Word.shared("%lld luni", Word.count(magnitude(count.toLong()))).written()

    fun weeks(count: Int): String = Word.shared("%lld săptămâni", Word.count(magnitude(count.toLong()))).written()
}

/**
 * How long something is, in the unit a person feels (`DurationWording`):
 * - [distance]: how far a day is from today, calendar-accurate and never rounded up: under 3
 *   weeks in days, then weeks, then months and weeks, then years and months (years only from 3);
 * - [lead]: a reminder's lead as the person chose it, whole months as calendar months;
 * - [inside]: a duration after „în”, joined as Romanian joins it („într-o lună”).
 */
object DurationWording {
    private const val THREE_WEEKS = 21L
    private const val DAYS_IN_WEEK = 7
    private const val MONTHS_IN_YEAR = 12
    private const val YEARS_WITHOUT_MONTHS = 3

    /** How far [days] from [from] is: „5 zile”, „3 săptămâni”, „2 luni și 3 săptămâni”, „un an și 4 luni”. */
    fun distance(days: Int, from: CalendarDay): String {
        val n = magnitude(days.toLong())
        if (n < THREE_WEEKS) return DayCount.phrase(n)
        val period = period(from, n) ?: return DayCount.phrase(n)
        val weeks = period.days / DAYS_IN_WEEK
        return when {
            period.years > 0 -> yearsAndMonths(period.years, period.months)
            period.months == 0 -> CalendarCount.weeks(maxOf(weeks, 1))
            weeks == 0 -> CalendarCount.months(period.months)
            else -> both(CalendarCount.months(period.months), CalendarCount.weeks(weeks))
        }
    }

    /** A reminder's lead: „7 zile”, „o lună”, „6 luni”, „un an”. */
    fun lead(days: Int): String = when (val lead = ReminderLead.of(days)) {
        is ReminderLead.Days -> DayCount.phrase(lead.days)
        is ReminderLead.Months -> yearsAndMonths(lead.months / MONTHS_IN_YEAR, lead.months % MONTHS_IN_YEAR)
    }

    /**
     * A duration after „în”: „în 5 zile”, „într-o lună”, „într-un an și 4 luni”. Every „in this
     * long” is written here; [startsSentence] capitalises it: „Într-o lună”.
     */
    fun inside(phrase: String, startsSentence: Boolean = false): String {
        val text = Word.shared("în %@", Word.text(phrase)).written()
        val joined = when {
            text.startsWith("în o ") -> "într-o " + text.removePrefix("în o ")
            text.startsWith("în un ") -> "într-un " + text.removePrefix("în un ")
            else -> text
        }
        return if (startsSentence) startingSentence(joined) else joined
    }

    /** „un an și 4 luni”, „3 ani”, „5 luni”. Months stop mattering from 3 years. */
    fun yearsAndMonths(years: Int, months: Int): String = when {
        years == 0 -> CalendarCount.months(months)
        months == 0 || years >= YEARS_WITHOUT_MONTHS -> CalendarCount.years(years)
        else -> both(CalendarCount.years(years), CalendarCount.months(months))
    }

    /** The years, months and days from [from] to [days] days after it; null past the calendar's end. */
    private fun period(from: CalendarDay, days: Long): Period? {
        val start = from.localDate()
        return try {
            Period.between(start, start.plusDays(days))
        } catch (_: DateTimeException) {
            null
        }
    }

    private fun both(first: String, second: String): String =
        Word.shared("%@ și %@", Word.text(first), Word.text(second)).written()
}

/**
 * When a deadline is, in a few words, from its urgency (`WhenWording`): „azi”, „mâine”, „în 5
 * zile”, „întârziat cu o zi” (late within grace), „depășit de 3 zile” (late past grace).
 */
object WhenWording {
    fun phrase(urgency: AttentionUrgency, daysRemaining: Int, today: CalendarDay): String {
        val distance = DurationWording.distance(daysRemaining, today)
        return when (urgency) {
            AttentionUrgency.OVERDUE -> Word.shared("depășit de %@", Word.text(distance)).written()
            AttentionUrgency.WITHIN_GRACE -> Word.shared("întârziat cu %@", Word.text(distance)).written()
            AttentionUrgency.TODAY -> Word.shared("azi").written()
            AttentionUrgency.SOON, AttentionUrgency.UPCOMING, AttentionUrgency.LATER ->
                if (daysRemaining == 1) Word.shared("mâine").written() else DurationWording.inside(distance)
        }
    }

    /** The same words starting a line on their own: „Azi”, „În 5 zile”, „Depășit de 3 zile”. */
    fun standalone(urgency: AttentionUrgency, daysRemaining: Int, today: CalendarDay): String =
        startingSentence(phrase(urgency, daysRemaining, today))
}

/** [text] with its first letter a capital, as Romanian writes it. */
internal fun startingSentence(text: String): String = text.replaceFirstChar { it.uppercase(DosarLocale.locale) }

private fun magnitude(count: Long): Long = if (count == Long.MIN_VALUE) Long.MAX_VALUE else abs(count)
