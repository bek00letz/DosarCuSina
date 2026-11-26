package com.ar.dosarcusina.core.readings

import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.NumberKind
import com.ar.dosarcusina.core.values.RomanianNumber
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.time.Instant

/**
 * The readings and counters rules' answers, in shared/test-vectors/readings/, written by
 * ios/DosarCuSinaTests/ReadingVectorsTests.swift: the series counter by counter, how far a drop is, the
 * answers a lower reading offers, the counter repair's verdicts, and what recording and taking away a
 * reading do to a section's readings.
 */
object ReadingVectors : VectorFolder(
    folderName = "readings",
    files = setOf(
        "counter-outliers", "deleting", "measurement-kind", "reading-distance", "reading-drop", "reading-series",
        "recording",
    ),
    writtenBy = "the iOS ReadingVectorsTests with TEST_RUNNER_READING_VECTORS_WRITE=1",
)

/** An enum's case as Swift names it: `WAS_ESTIMATE` is `wasEstimate`. */
fun swiftName(case: Enum<*>): String =
    case.name.lowercase().split("_")
        .mapIndexed { index, part -> if (index == 0) part else part.replaceFirstChar { it.uppercase() } }
        .joinToString("")

fun JsonObject.double(key: String): Double = getValue(key).jsonPrimitive.content.toDouble()

fun JsonObject.doubleOrNull(key: String): Double? = if (isNull(key)) null else double(key)

fun moment(text: String): Instant = requireNotNull(MachineText.moment(text)) { "Not a moment: $text" }

/** A series' reading as a case writes it. */
fun point(case: JsonObject): Reading =
    Reading(moment(case.text("at")), case.double("metric"), case.bool("startsCounter"), case.bool("isEstimate"))

fun points(case: JsonObject, key: String): List<Reading> = case.getValue(key).jsonArray.map { point(it.jsonObject) }

/** A section's reading as a case writes it. */
fun log(case: JsonObject): StoredReading = StoredReading(
    key = case.int("key").toLong(),
    at = moment(case.text("at")),
    value = case.double("value"),
    unit = MeasurementUnit.of(case.text("unit")),
    kind = MeasurementKind.stored(case.text("kind")),
    startsCounter = case.bool("startsCounter"),
    basis = ReadingBasis.stored(case.textOrNull("basis")),
)

fun logs(case: JsonObject): List<StoredReading> = case.getValue("readings").jsonArray.map { log(it.jsonObject) }

/** The key a case gives the reading a step records. */
const val NEW = 1_000_000L

/** A section's readings as a case's `after` writes them, by key ("new" for the one recorded). */
fun after(case: JsonObject): Map<String, StoredReading> = case.getValue("after").jsonArray.associate { item ->
    val reading = item.jsonObject
    val key = reading.text("key")
    key to StoredReading(
        key = if (key == "new") NEW else key.toLong(),
        at = moment(reading.text("at")),
        value = reading.double("value"),
        unit = MeasurementUnit.of(reading.text("unit")),
        kind = MeasurementKind.stored(reading.text("kind")),
        startsCounter = reading.bool("startsCounter"),
        basis = ReadingBasis.stored(reading.textOrNull("basis")),
    )
}

fun byKey(readings: List<StoredReading>): Map<String, StoredReading> =
    readings.associateBy { if (it.key == NEW) "new" else it.key.toString() }

/** [readings] once [gone] is taken away, as the store takes one away: the counter it started handed on first. */
fun deleting(readings: List<StoredReading>, gone: StoredReading): List<StoredReading> {
    val heir = CounterReadings.handsCounterTo(gone, readings)?.key
    return readings.filter { it.key != gone.key }.map { if (it.key == heir) it.copy(startsCounter = true) else it }
}

/** What recording [planned] with [answer] leaves of [readings], as the store carries it out. */
fun recorded(planned: PlannedReading, readings: List<StoredReading>, answer: LowerReadingAnswer?): List<StoredReading> =
    when (val recording = CounterReadings.recording(planned, readings, answer)) {
        Recording.NotStored -> readings
        is Recording.Asks -> error("Asks again with ${answer?.let(::swiftName)}: ${recording.question}")
        is Recording.Records -> {
            val made = StoredReading(
                NEW, planned.at, planned.value, planned.unit, planned.kind, recording.startsCounter, planned.basis,
            )
            var now = readings + made
            for (old in recording.removes) now = deleting(now, now.first { it.key == old.key })
            val marked = recording.marksEstimated.map { it.key }.toSet()
            now.map { if (it.key in marked) it.copy(basis = ReadingBasis.ESTIMATED) else it }
        }
    }

/** The plan a case's `planned` makes on [readings]; null when its typed text isn't a number. */
fun planned(case: JsonObject, readings: List<StoredReading>): PlannedReading? {
    val planned = case.getValue("planned").jsonObject
    val value = planned.doubleOrNull("value") ?: planned.textOrNull("typed")?.let { typed ->
        val kind = NumberKind.entries.first { it.key == planned.text("numberKind") }
        RomanianNumber.value(typed, kind)?.toDouble()
    } ?: return null
    return PlannedReading.plan(
        value = value,
        at = moment(planned.text("at")),
        source = ReadingSource.entries.first { swiftName(it) == planned.text("source") },
        unit = planned.textOrNull("unit")?.let(MeasurementUnit::of),
        existing = readings,
        kind = planned.textOrNull("kind")?.let(MeasurementKind::stored),
        basis = ReadingBasis.stored(planned.textOrNull("basis")),
        replaces = planned.getValue("replaces").jsonArray.mapTo(mutableSetOf()) { it.jsonPrimitive.content.toLong() },
    )
}

fun answer(text: String?): LowerReadingAnswer? =
    text?.let { name -> LowerReadingAnswer.entries.first { swiftName(it) == name } }

class ReadingVectorsTest {
    @Test
    fun everyFileOfAnswersIsReadByATest() {
        val present = ReadingVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
            .map { it.nameWithoutExtension }.toSet()
        assertEquals(ReadingVectors.files, present, "Each file of answers needs its test, and each test its file")
    }

    @TestFactory
    fun measurementKinds(): List<DynamicTest> =
        ReadingVectors.tests("measurement-kind", { label(it, "raw", "stored", "forUnit") }, ::checkKind)

    private fun checkKind(case: JsonObject) {
        when {
            "raw" in case -> {
                val kind = MeasurementKind.stored(case.text("raw"))
                assertEquals(case.text("raw"), kind.raw)
                assertEquals(case.textOrNull("defaultUnit"), kind.defaultUnit?.key)
                assertEquals(case.bool("isCumulative"), kind.isCumulative)
                assertEquals(case.bool("mayBeEstimated"), kind.mayBeEstimated)
                val offered = LowerReadingAnswer.offered(kind, likelyNewCounter = false)
                assertEquals(case.texts("offered"), offered.map(::swiftName))
                val likely = LowerReadingAnswer.offered(kind, likelyNewCounter = true)
                assertEquals(case.texts("offeredLikelyNewCounter"), likely.map(::swiftName))
            }
            "stored" in case -> assertEquals(case.text("kind"), MeasurementKind.stored(case.text("stored")).raw)
            "forUnit" in case -> {
                val kind = MeasurementKind.forUnit(MeasurementUnit.of(case.textOrNull("forUnit")))
                assertEquals(case.text("kind"), kind.raw)
            }
            else -> assertEquals(case.texts("allAnswers"), LowerReadingAnswer.entries.map(::swiftName))
        }
    }

    @TestFactory
    fun theSeries(): List<DynamicTest> = ReadingVectors.tests("reading-series", { it.text("name") }) { case ->
        val series = ReadingSeries(points(case, "readings"), cumulative = case.bool("cumulative"))
        val counters = case.getValue("counters").jsonArray
            .map { counter -> counter.jsonArray.map { point(it.jsonObject) } }
        assertEquals(counters, series.counters)
        assertEquals(points(case, "counted"), series.readings)
        assertEquals(points(case, "setAside"), series.setAside)
        assertEquals(points(case, "corrected"), series.corrected)
        assertEquals(case.texts("counterStarts").map(::moment), series.counterStarts)
        assertEquals(case.doubleOrNull("current"), series.current)
        if (case.isNull("progress")) {
            assertNull(series.progress())
        } else {
            val progress = case.getValue("progress").jsonObject
            assertEquals(Progress(progress.double("distance"), progress.double("days")), series.progress())
        }
        assertEquals(case.bool("madeAgain"), ReadingSeries(series.readings, case.bool("cumulative")) == series)
    }

    @TestFactory
    fun distances(): List<DynamicTest> = ReadingVectors.tests("reading-distance", { it.text("name") }) { case ->
        val series = ReadingSeries(points(case, "readings"))
        val from = case.getValue("from").jsonObject.let { Reading(moment(it.text("at")), it.double("metric")) }
        val to = case.getValue("to").jsonObject.let { Reading(moment(it.text("at")), it.double("metric")) }
        assertEquals(case.double("distance"), series.distance(from, to))
        assertEquals(case.int("counterAtFrom"), series.counter(from.at))
        assertEquals(case.int("counterAtTo"), series.counter(to.at))
    }

    @TestFactory
    fun drops(): List<DynamicTest> =
        ReadingVectors.tests("reading-drop", { "${it.text("highest")} to ${it.text("value")}" }) { case ->
        val drop = ReadingDrop(case.double("highest"), case.double("value"), ReadingSeries(points(case, "readings")))
        assertEquals(case.text("size"), swiftName(drop.size))
    }

    @TestFactory
    fun outliers(): List<DynamicTest> = ReadingVectors.tests("counter-outliers", { label(it, "values") }) { case ->
        val values = case.getValue("values").jsonArray.map { it.jsonPrimitive.content.toDouble() }
        val expected = case.getValue("verdicts").jsonArray.associate { item ->
            val verdict = item.jsonObject
            verdict.int("index") to if ("remove" in verdict) {
                CounterOutliers.Verdict.Remove
            } else {
                CounterOutliers.Verdict.Correct(verdict.double("correctTo"))
            }
        }
        assertEquals(expected, CounterOutliers.verdicts(values))
    }

    @TestFactory
    fun recording(): List<DynamicTest> = ReadingVectors.tests("recording", { it.text("name") }) { case ->
        val readings = logs(case)
        val planned = planned(case, readings)
        if (case.isNull("plannedAs")) {
            assertNull(planned, "Typed text that isn't a number plans nothing")
            return@tests
        }
        assertNotNull(planned)
        planned!!
        val plannedAs = case.getValue("plannedAs").jsonObject
        assertEquals(plannedAs.double("value"), planned.value)
        assertEquals(plannedAs.textOrNull("unit"), planned.unit?.key)
        assertEquals(plannedAs.text("kind"), planned.kind.raw)
        assertEquals(plannedAs.textOrNull("basis"), planned.basis?.raw)
        assertEquals(plannedAs.bool("isStored"), planned.isStored)
        assertEquals(plannedAs.bool("continuesCounter"), planned.continuesCounter)

        val asked = CounterReadings.question(planned, readings, answer = null)
        if (case.isNull("question")) {
            assertNull(asked)
        } else {
            val question = case.getValue("question").jsonObject
            assertNotNull(asked)
            assertEquals(question.double("previous"), asked!!.previous)
            assertEquals(moment(question.text("previousAt")), asked.previousAt)
            assertEquals(question.double("value"), asked.value)
            assertEquals(question.textOrNull("unit"), asked.unit?.key)
            assertEquals(question.texts("answers"), asked.answers.map(::swiftName))
            assertTrue(CounterReadings.recording(planned, readings, null) is Recording.Asks)
        }

        for (item in case.getValue("outcomes").jsonArray) {
            val outcome = item.jsonObject
            val answer = answer(outcome.textOrNull("answer"))
            val made = CounterReadings.recording(planned, readings, answer)
            val with = outcome.textOrNull("answer")
            assertEquals(outcome.bool("recorded"), made is Recording.Records, "Recorded with $with")
            val left = recorded(planned, readings, answer)
            assertEquals(after(outcome), byKey(left), "What is left with ${outcome.textOrNull("answer")}")
            assertEquals(outcome.doubleOrNull("current"), CounterReadings.current(left, planned.unit))
            assertEquals(
                outcome.getValue("setAside").jsonArray.map { it.jsonPrimitive.content.toDouble() },
                CounterReadings.series(left, planned.unit).setAside.map { it.metric },
            )
            assertEquals(outcome.doubleOrNull("counterStart"), CounterReadings.counterStart(left, planned.unit)?.value)
        }
    }

    @TestFactory
    fun deleting(): List<DynamicTest> = ReadingVectors.tests("deleting", { it.text("name") }) { case ->
        val readings = logs(case)
        val gone = readings.first { it.key == case.int("delete").toLong() }
        assertEquals(after(case), byKey(deleting(readings, gone)))
        assertFalse(gone.key in deleting(readings, gone).map { it.key })
    }
}
