package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId

/** Days kept as days, pinned against the iOS app's answers. Placeholder data only. */
class CalendarDayVectorsTest {
    private fun day(text: String): CalendarDay = requireNotNull(CalendarDay.parse(text)) { "Not a day: $text" }

    @TestFactory
    fun `a day reads as the iPhone reads it, kept as written`(): List<DynamicTest> =
        Vectors.tests("calendar-day-parse", { label(it, "input") }) { case ->
            val read = CalendarDay.parse(case.text("input"))
            if (case.isNull("day")) {
                assertNull(read)
            } else {
                val parts = case.ints("day")
                assertEquals(CalendarDay(parts[0], parts[1], parts[2]), read)
                assertEquals(case.text("written"), read?.isoString)
                assertEquals(case.bool("isOnCalendar"), read?.isOnCalendar)
                assertEquals(case.text("onCalendar"), read?.onCalendar?.isoString)
            }
            assertEquals(case.textOrNull("storedDay"), StoredDay.day(case.text("input"))?.let(StoredDay::text))
        }

    @TestFactory
    fun `a day from outside is one the calendar has`(): List<DynamicTest> =
        Vectors.tests("calendar-day-valid", { label(it, "input") }) { case ->
            val (year, month, dayOfMonth) = case.ints("input")
            assertEquals(case.textOrNull("day"), CalendarDay.valid(year, month, dayOfMonth)?.isoString)
        }

    @TestFactory
    fun `months clamp to the month's end and a series keeps its day`(): List<DynamicTest> =
        Vectors.tests("calendar-day-months", { label(it, "start", "daysInMonth") }) { case ->
            if (case.containsKey("daysInMonth")) {
                for (entry in case.getValue("daysInMonth").jsonArray.map { it.jsonObject }) {
                    val length = CalendarDay(entry.int("year"), entry.int("month"), 1).daysInMonth()
                    assertEquals(entry.int("daysInMonth"), length, entry.toString())
                }
                return@tests
            }
            val dayOfMonth = if (case.isNull("dayOfMonth")) null else case.int("dayOfMonth")
            val moved = day(case.text("start")).addingMonths(case.int("months"), dayOfMonth)
            assertEquals(case.text("day"), moved.isoString)
        }

    @TestFactory
    fun `days are counted on the calendar`(): List<DynamicTest> =
        Vectors.tests("calendar-day-days", { label(it, "start") }) { case ->
            val start = day(case.text("start"))
            if (case.containsKey("addDays")) {
                assertEquals(case.text("day"), start.addingDays(case.int("addDays")).isoString)
            } else {
                assertEquals(case.int("days"), start.daysTo(day(case.text("end"))))
            }
        }

    @TestFactory
    fun `days sort by their numbers`(): List<DynamicTest> =
        Vectors.tests("calendar-day-order", { label(it, "left", "earliest", "days") }) { case ->
            when {
                case.containsKey("days") ->
                    assertEquals(case.texts("sorted"), case.texts("days").map(::day).sorted().map { it.isoString })
                case.containsKey("earliest") -> assertEquals(case.text("earliest"), CalendarDay.EARLIEST.isoString)
                else -> {
                    val left = day(case.text("left"))
                    val right = day(case.text("right"))
                    assertEquals(case.bool("isBefore"), left < right)
                    assertEquals(case.bool("isEqual"), left == right)
                }
            }
        }

    @TestFactory
    fun `a month and day reads and falls in a year`(): List<DynamicTest> =
        Vectors.tests("month-day", { label(it, "input", "monthDay") }) { case ->
            if (case.containsKey("input")) {
                assertEquals(case.textOrNull("monthDay"), MonthDay.parse(case.text("input"))?.isoString)
            } else {
                val monthDay = requireNotNull(MonthDay.parse(case.text("monthDay")))
                assertEquals(case.text("day"), monthDay.day(case.int("year")).isoString)
            }
        }

    @TestFactory
    fun `the app's calendar counts as the iPhone's`(): List<DynamicTest> =
        Vectors.tests("app-calendar", { label(it, "week", "start", "moment", "identifier") }) { case ->
            when {
                case.containsKey("identifier") -> {
                    assertEquals("gregorian", case.text("identifier"))
                    assertEquals(case.text("locale"), DosarLocale.locale.toString())
                    assertEquals(case.int("firstWeekday"), foundationWeekday(DosarCalendar.firstDayOfWeek))
                    assertEquals(case.int("minimumDaysInFirstWeek"), DosarCalendar.MINIMUM_DAYS_IN_FIRST_WEEK)
                }
                case.containsKey("week") -> {
                    val day = day(case.text("week"))
                    assertEquals(case.int("weekday"), foundationWeekday(DosarCalendar.dayOfWeek(day)))
                    assertEquals(case.int("weekOfYear"), DosarCalendar.weekOfYear(day))
                    assertEquals(case.int("yearForWeekOfYear"), DosarCalendar.yearForWeekOfYear(day))
                }
                case.containsKey("start") -> {
                    val moment = day(case.text("start")).moment(case.int("minute"), ZoneId.of(case.text("zone")))
                    val key = "${case.text("start")} ${case.text("zone")} ${case.int("minute")}"
                    val expected = ANSWERED_DIFFERENTLY[key]
                    assertEquals(expected ?: case.long("moment"), moment.epochSecond)
                }
                else -> {
                    val moment = Instant.ofEpochSecond(case.long("moment"))
                    val found = DosarCalendar.day(moment, ZoneId.of(case.text("zone")))
                    assertEquals(case.text("day"), found.isoString)
                }
            }
        }

    @Test
    fun `the phone's time zone is read each time`() {
        val before = java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("Pacific/Kiritimati"))
            val far = DosarCalendar.zone()
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("Pacific/Pago_Pago"))
            val other = DosarCalendar.zone()
            assertEquals(ZoneId.of("Pacific/Kiritimati"), far)
            assertEquals(ZoneId.of("Pacific/Pago_Pago"), other)
            // 2026-11-02T08:00:00Z is the 2nd in one and the 1st in the other.
            val moment = Instant.ofEpochSecond(1_793_606_400)
            assertEquals("2026-11-02", DosarCalendar.day(moment, far).isoString)
            assertEquals("2026-11-01", DosarCalendar.day(moment).isoString)
        } finally {
            java.util.TimeZone.setDefault(before)
        }
    }

    private companion object {
        /**
         * The short, written list of cases Android answers differently from the iPhone, on
         * purpose, each with why: the day, zone and minute, and Android's moment.
         *
         * - Lord Howe Island's clocks skip half an hour (02:00–02:30) when summer time starts.
         *   `CalendarDay.moment(atMinute:)` means the first minute after the gap, 02:30, which
         *   Android gives; Foundation's `nextDate` finds no 02:00 that day and gives the next
         *   day's, a day late. A question for the owner, in the pull request.
         */
        val ANSWERED_DIFFERENTLY: Map<String, Long> = mapOf(
            "2026-10-04 Australia/Lord_Howe 120" to 1_791_041_400L,
        )
    }

    /** Foundation counts weekdays from Sunday, 1, to Saturday, 7. */
    private fun foundationWeekday(day: DayOfWeek): Int = day.value % DayOfWeek.entries.size + 1
}
