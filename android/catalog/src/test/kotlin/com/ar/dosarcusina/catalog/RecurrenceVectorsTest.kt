package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.core.readings.Reading
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.RecurrenceInterval
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.io.File
import java.time.ZoneId

/**
 * The iOS app's answers for how a deadline repeats (shared/test-vectors/recurrence/, written by
 * ios/DosarCuSinaTests/RecurrenceVectorsTests.swift), run through this module's [RecurrenceEngine]: every
 * case must give the same answer.
 */
class RecurrenceVectorsTest {
    private val folder: File
        get() {
            val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
            return File(shared, "test-vectors/recurrence")
        }

    private val files = setOf("add", "cycle-start", "first-due", "next-due", "series-start")

    private fun cases(name: String): List<JsonObject> {
        val file = File(folder, "$name.json")
        check(file.isFile) {
            "${file.path} is missing: run the iOS RecurrenceVectorsTests with TEST_RUNNER_RECURRENCE_VECTORS_WRITE=1"
        }
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    private fun tests(name: String, check: (JsonObject) -> Unit): List<DynamicTest> =
        cases(name).mapIndexed { index, case ->
            val label = case.textOrNull("name") ?: case.toString().take(LABEL_LENGTH)
            DynamicTest.dynamicTest("$name #$index: $label") { check(case) }
        }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content

    private fun JsonObject.textOrNull(key: String): String? =
        this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

    private fun JsonObject.day(key: String): CalendarDay = requireNotNull(CalendarDay.parse(text(key)))

    private fun JsonObject.dayOrNull(key: String): CalendarDay? = textOrNull(key)?.let(CalendarDay::parse)

    private fun JsonObject.intOrNull(key: String): Int? = textOrNull(key)?.toInt()

    private fun JsonObject.doubleOrNull(key: String): Double? = textOrNull(key)?.toDouble()

    private fun rule(json: JsonElement): RecurrenceRule = requireNotNull(RecurrenceRule.codec.decode(json))

    private fun values(json: JsonElement): FieldValues = requireNotNull(FieldValues.codec.decode(json))

    private fun interval(json: JsonObject): RecurrenceInterval =
        RecurrenceInterval.of(
            json.text("every").toInt(),
            requireNotNull(RecurrenceInterval.Unit.stored(json.text("unit"))),
        )

    @Test
    fun everyFileOfAnswersIsReadByATest() {
        val present = folder.listFiles { file -> file.extension == "json" }.orEmpty()
            .map { it.nameWithoutExtension }.toSet()
        assertEquals(files, present, "Each file of answers needs its test, and each test its file")
    }

    @TestFactory
    fun nextDue(): List<DynamicTest> = tests("next-due") { case ->
        val readings = case.getValue("readings").jsonArray.map { item ->
            val point = item.jsonObject
            Reading(
                at = requireNotNull(MachineText.moment(point.text("at"))),
                metric = point.text("metric").toDouble(),
                startsCounter = point.text("startsCounter").toBooleanStrict(),
                isEstimate = point.text("isEstimate").toBooleanStrict(),
            )
        }
        val context = RecurrenceContext(
            assetValues = values(case.getValue("values")),
            readings = readings,
            currentMetric = case.doubleOrNull("currentMetric"),
            seriesDayOfMonth = case.intOrNull("seriesDayOfMonth"),
            missedCyclesStayOwed = case.text("missedCyclesStayOwed").toBooleanStrict(),
        )
        val next = RecurrenceEngine.nextDue(
            case.day("due"), case.day("completedOn"), rule(case.getValue("rule")), context,
            ZoneId.of(case.text("zone")),
        )
        val expected = case["next"]?.takeUnless { it is JsonNull }?.jsonObject
        assertEquals(expected?.dayOrNull("day"), next?.day)
        assertEquals(expected?.doubleOrNull("metric"), next?.metric)
    }

    @TestFactory
    fun seriesStart(): List<DynamicTest> = tests("series-start") { case ->
        val completions = case.getValue("completions").jsonArray.map { item ->
            val step = item.jsonObject
            SeriesStep(step.dayOrNull("cycle"), step.dayOrNull("next"))
        }
        val interval = interval(case.getValue("interval").jsonObject)
        val start = RecurrenceEngine.seriesStart(case.day("current"), completions, interval)
        assertEquals(case.day("start"), start)
        assertEquals(case.text("seriesDayOfMonth").toInt(), start.day)
    }

    @TestFactory
    fun cycleStart(): List<DynamicTest> = tests("cycle-start") { case ->
        assertEquals(case.dayOrNull("start"), RecurrenceEngine.cycleStart(case.day("due"), rule(case.getValue("rule"))))
    }

    @TestFactory
    fun firstDue(): List<DynamicTest> = tests("first-due") { case ->
        val blueprint = requireNotNull(ObligationBlueprint.codec.decode(case.getValue("blueprint")))
        assertEquals(
            case.dayOrNull("day"),
            RecurrenceEngine.firstDue(blueprint, values(case.getValue("values")), case.day("today")),
        )
    }

    @TestFactory
    fun adding(): List<DynamicTest> = tests("add") { case ->
        val interval = interval(case)
        assertEquals(case.text("heldTo").toInt(), interval.every)
        assertEquals(case.day("result"), RecurrenceEngine.add(interval, case.day("day"), case.intOrNull("dayOfMonth")))
    }

    private companion object {
        /** How much of a case without a name labels its test. */
        const val LABEL_LENGTH = 80
    }
}
