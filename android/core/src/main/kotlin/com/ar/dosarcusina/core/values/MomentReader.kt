package com.ar.dosarcusina.core.values

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.regex.Matcher
import java.util.regex.Pattern

/**
 * Reads a moment as the iOS app's `MachineText.moment(_:)` does (Foundation's ISO 8601 reader,
 * then a day alone), pinned by shared/test-vectors/values/machine-moment-read.json:
 *
 * - `year-month-dayThour:minute:second`, each a run of ASCII digits (`2026-1-2T8:0:0Z` too),
 *   an uppercase `T`, then an optional fraction (`.5`, any number of digits; never `,5` or `.`
 *   alone), then the time zone, which must be there: `Z` or `z`, `GMT` or `UTC` (each with an
 *   optional offset after it), or an offset of hours, minutes and seconds of one or two digits
 *   each, the colons optional (`+2`, `+02`, `+0200`, `+02:00`, `+02:00:30`), up to any number of
 *   hours. What follows the time zone isn't read.
 * - The month is 1 to 12 and the day 1 to 31; past that, values roll over as a calendar does:
 *   `24:00:00` is the next midnight, `23:59:60` the next minute, 30 February is 2 March.
 * - Else exactly ten characters that are a day (`2026-11-02`): its start in UTC, a day the
 *   calendar doesn't have counting as its month's last.
 *
 * A moment on iOS is a Double count of seconds since 2001, so the one read here is the nearest
 * such count: 08:00:00.999999999 is 08:00:01, as on the iPhone.
 */
internal object MomentReader {
    private const val DAY_LENGTH = 10
    private const val SECONDS_PER_MINUTE = 60L
    private const val SECONDS_PER_HOUR = 3_600L
    private const val SECONDS_PER_DAY = 86_400L
    private const val NANOS_DIGITS = 9
    private const val MONTHS = 12L
    private const val LONGEST_MONTH = 31L

    /** A year, a month and a day; then an hour, a minute and a second. */
    private const val DATE_PARTS = 3

    /** 2001-01-01T00:00:00Z, where an iPhone counts its moments from. */
    private const val REFERENCE_EPOCH_SECOND = 978_307_200L

    private const val DIGITS = "([0-9]+)"
    private const val ZONE = "(?:([Zz])|GMT|UTC|(?=[+-][0-9]))"
    private const val OFFSET = "(?:([+-])([0-9]{1,2}):?([0-9]{1,2})?(?::([0-9]{1,2}))?)?"

    /** Groups 1 to 6 are the date and time's numbers, then the fraction, `Z`, and the offset's sign and parts. */
    private val STAMP: Pattern =
        Pattern.compile("$DIGITS-$DIGITS-${DIGITS}T$DIGITS:$DIGITS:$DIGITS(?:\\.([0-9]+))?$ZONE$OFFSET")
    private const val NUMBERS = 6
    private const val FRACTION = 7
    private const val UTC_LETTER = 8
    private const val SIGN = 9
    private const val OFFSET_HOURS = 10
    private const val OFFSET_MINUTES = 11
    private const val OFFSET_SECONDS = 12

    fun read(raw: String): Instant? {
        val stamp = timestamp(raw)
        return if (stamp != null) asOnIPhone(stamp) else dayAlone(raw)
    }

    private fun dayAlone(raw: String): Instant? {
        if (TextRules.characters(raw).size != DAY_LENGTH) return null
        return CalendarDay.parse(raw)?.startOfDay(ZoneOffset.UTC)
    }

    private fun timestamp(raw: String): Instant? {
        val match = STAMP.matcher(raw).takeIf { it.lookingAt() } ?: return null
        val numbers = (1..NUMBERS).map { match.group(it).toLongOrNull() }
        return numbers.takeIf { null !in it }?.let { moment(it.filterNotNull(), match) }
    }

    private fun moment(numbers: List<Long>, match: Matcher): Instant? {
        val (year, month, day) = numbers
        val (hour, minute, second) = numbers.drop(DATE_PARTS)
        if (year > Int.MAX_VALUE || month !in 1L..MONTHS || day !in 1L..LONGEST_MONTH) return null
        val date = LocalDate.of(year.toInt(), 1, 1).plusMonths(month - 1).plusDays(day - 1)
        val clock = hour * SECONDS_PER_HOUR + minute * SECONDS_PER_MINUTE + second
        return Instant.ofEpochSecond(date.toEpochDay() * SECONDS_PER_DAY + clock - offsetSeconds(match), nanos(match))
    }

    /** The fraction of a second, in nanoseconds, half to even past the ninth digit. */
    private fun nanos(match: Matcher): Long {
        val digits = match.group(FRACTION) ?: return 0
        return BigDecimal("0.$digits").movePointRight(NANOS_DIGITS).setScale(0, RoundingMode.HALF_EVEN).toLong()
    }

    /** The time zone's offset from UTC in seconds: none for `Z`, or `GMT` and `UTC` alone. */
    private fun offsetSeconds(match: Matcher): Long {
        if (match.group(UTC_LETTER) != null || match.group(SIGN) == null) return 0
        fun part(group: Int): Long = match.group(group)?.toLong() ?: 0
        val total = part(OFFSET_HOURS) * SECONDS_PER_HOUR + part(OFFSET_MINUTES) * SECONDS_PER_MINUTE +
            part(OFFSET_SECONDS)
        return if (match.group(SIGN) == "-") -total else total
    }

    /** The nearest moment an iPhone can hold: a Double count of seconds since 2001. */
    private fun asOnIPhone(instant: Instant): Instant {
        val exact = BigDecimal.valueOf(instant.epochSecond - REFERENCE_EPOCH_SECOND)
            .add(BigDecimal.valueOf(instant.nano.toLong(), NANOS_DIGITS))
        val held = BigDecimal(exact.toPlainString().toDouble()).setScale(NANOS_DIGITS, RoundingMode.HALF_EVEN)
        val whole = held.setScale(0, RoundingMode.FLOOR)
        val nanos = held.subtract(whole).movePointRight(NANOS_DIGITS).toLong()
        return Instant.ofEpochSecond(whole.toLong() + REFERENCE_EPOCH_SECOND, nanos)
    }
}
