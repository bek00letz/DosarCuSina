package com.ar.dosarcusina.core.wording

import com.ar.dosarcusina.core.attention.AttentionVectors
import com.ar.dosarcusina.core.urgency.AttentionUrgency
import com.ar.dosarcusina.core.urgency.Consequence
import com.ar.dosarcusina.core.urgency.day
import com.ar.dosarcusina.core.urgency.obj
import com.ar.dosarcusina.core.urgency.profile
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.ints
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.long
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.time.Instant
import java.time.ZoneId

/**
 * The app's words, the iOS app's answers in shared/test-vectors/wording/, by
 * ios/DosarCuSinaTests/WordingVectorsTests.swift.
 */
object WordingVectors : VectorFolder(
    folderName = "wording",
    files = setOf(
        "counts", "currency-name", "days", "distance", "due-lines", "lead", "moments", "money", "times", "units",
        "when",
    ),
    writtenBy = "the iOS WordingVectorsTests with TEST_RUNNER_WORDING_VECTORS_WRITE=1",
)

/** Android writes every word the iOS app writes, word for word, from the same String Catalogs. */
class WordingVectorsTest {
    @Test
    fun `every file of answers is read by a test`() {
        val present = WordingVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
            .map { it.nameWithoutExtension }.toSet()
        assertEquals(WordingVectors.files, present, "Each file of answers needs its test, and each test its file")
    }

    @TestFactory
    fun `counts of days, weeks, months and years`(): List<DynamicTest> =
        WordingVectors.tests("counts", { "${it.text("unit")} ${it.int("count")}" }) { case ->
            val count = case.int("count")
            val text = when (case.text("unit")) {
                "days" -> DayCount.phrase(count)
                "weeks" -> CalendarCount.weeks(count)
                "months" -> CalendarCount.months(count)
                else -> CalendarCount.years(count)
            }
            assertEquals(case.text("text"), text)
        }

    @TestFactory
    fun `how far a day is, and in how long`(): List<DynamicTest> =
        WordingVectors.tests("distance", { "${it.int("days")} from ${it.text("today")}" }) { case ->
            val distance = DurationWording.distance(case.int("days"), day(case.text("today")))
            assertEquals(case.text("distance"), distance)
            assertEquals(case.text("inside"), DurationWording.inside(distance))
            assertEquals(case.text("insideStartingSentence"), DurationWording.inside(distance, startsSentence = true))
        }

    @TestFactory
    fun `a reminder's lead`(): List<DynamicTest> =
        WordingVectors.tests("lead", { label(it, "days") }) { case ->
            assertEquals(case.text("text"), DurationWording.lead(case.int("days")))
        }

    @TestFactory
    fun `when a deadline is`(): List<DynamicTest> =
        WordingVectors.tests("when", { "${it.text("urgency")} ${it.int("daysRemaining")}" }) { case ->
            val urgency = AttentionUrgency.entries.first { it.stored == case.text("urgency") }
            val today = day(case.text("today"))
            assertEquals(case.text("phrase"), WhenWording.phrase(urgency, case.int("daysRemaining"), today))
            assertEquals(case.text("standalone"), WhenWording.standalone(urgency, case.int("daysRemaining"), today))
        }

    @TestFactory
    fun `amounts of money`(): List<DynamicTest> =
        WordingVectors.tests("money", { "${it.text("amount")} ${it.text("currency")}" }) { case ->
            val money = requireNotNull(Money.of(case.text("amount"), case.text("currency")))
            assertEquals(case.text("formatted"), money.formatted())
            assertEquals(case.text("formattedCompact"), money.formattedCompact())
        }

    @TestFactory
    fun `a currency's name`(): List<DynamicTest> =
        WordingVectors.tests("currency-name", { label(it, "code") }) { case ->
            assertEquals(case.text("name"), MoneyWording.currencyName(case.text("code")))
        }

    @TestFactory
    fun `a number with its unit`(): List<DynamicTest> =
        WordingVectors.tests("units", { "${it.text("value")} ${it.textOrNull("unit")} ${it.ints("fractionDigits")}" }) {
            val (fewest, most) = it.ints("fractionDigits")
            val unit = if (it.isNull("unit")) null else MeasurementUnit.of(it.text("unit"))
            assertEquals(it.text("text"), UnitWording.written(it.text("value").toDouble(), unit, fewest, most))
        }

    @TestFactory
    fun `a day in every style`(): List<DynamicTest> =
        WordingVectors.tests("days", { label(it, "day") }) { case ->
            val day = day(case.text("day"))
            assertEquals(case.text("dayText"), DosarFormat.day(day))
            assertEquals(case.text("longDay"), DosarFormat.longDay(day))
            assertEquals(case.text("dayMonth"), DosarFormat.dayMonth(day))
            assertEquals(case.text("monthYear"), DosarFormat.monthYear(day))
            assertEquals(case.text("cardExpiry"), DosarFormat.cardExpiry(day))
        }

    @TestFactory
    fun `a moment in a time zone`(): List<DynamicTest> =
        WordingVectors.tests("moments", { "${it.long("seconds")} in ${it.text("zone")}" }) { case ->
            val moment = Instant.ofEpochSecond(case.long("seconds"))
            val zone = ZoneId.of(case.text("zone"))
            assertEquals(case.text("dayText"), DosarFormat.write(moment, DateStyle.DAY, zone))
            assertEquals(case.text("longDay"), DosarFormat.write(moment, DateStyle.LONG_DAY, zone))
            assertEquals(case.text("dayMonth"), DosarFormat.write(moment, DateStyle.DAY_MONTH, zone))
            assertEquals(case.text("monthYear"), DosarFormat.write(moment, DateStyle.MONTH_YEAR, zone))
            assertEquals(case.text("numericDay"), DosarFormat.write(moment, DateStyle.NUMERIC_DAY, zone))
            assertEquals(case.text("time"), DosarFormat.time(moment, zone))
        }

    @TestFactory
    fun `a time of day`(): List<DynamicTest> =
        WordingVectors.tests("times", { label(it, "minuteOfDay") }) { case ->
            assertEquals(case.text("text"), DosarFormat.time(case.int("minuteOfDay")))
        }

    @TestFactory
    fun `due lines of weeks, months and years, and why they matter`(): List<DynamicTest> =
        WordingVectors.tests("due-lines", { label(it, "kind", "consequence") }) { case ->
            if (case.containsKey("consequence")) {
                val consequence = Consequence.stored(case.text("consequence"))
                assertEquals(case.text("text"), DueWording.consequence(consequence))
                return@tests
            }
            val kind = ObligationKind.stored(case.text("kind"))
            assertEquals(case.text("text"), DueWording.line(kind, day(case.text("due")), day(case.text("today"))))
        }

    @TestFactory
    fun `due lines and a passport's lines`(): List<DynamicTest> =
        AttentionVectors.tests("due-line", { label(it, "kind", "due") + " on " + it.text("today") }) { case ->
            val today = day(case.text("today"))
            val due = day(case.text("due"))
            if (case.containsKey("kind")) {
                assertEquals(case.text("text"), DueWording.line(ObligationKind.stored(case.text("kind")), due, today))
                return@tests
            }
            val lines = DueWording.travelLines(due, profile(case.obj("reminders")).urgencyRule, today)
            if (case.isNull("texts")) assertNull(lines) else assertEquals(case.texts("texts"), lines)
        }
}
