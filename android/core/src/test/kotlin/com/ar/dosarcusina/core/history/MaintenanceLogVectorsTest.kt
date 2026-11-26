package com.ar.dosarcusina.core.history

import com.ar.dosarcusina.core.capture.LabourLine
import com.ar.dosarcusina.core.readings.Reading
import com.ar.dosarcusina.core.readings.doubleOrNull
import com.ar.dosarcusina.core.readings.moment
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.long
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.time.Instant
import java.time.ZoneId

/**
 * The history's pure rules, as the iOS app answers them in shared/test-vectors/history/ (written by
 * ios/DosarCuSinaTests/HistoryVectorsTests.swift): the maintenance log ([MaintenanceLog]) and what a line of
 * work is that is never a part ([LabourLine], over capture's lexicon). The store's actions are run against the
 * same folder by the store's tests.
 */
object HistoryVectors : VectorFolder(
    folderName = "history",
    files = setOf("actions", "entry-shapes", "labour", "maintenance-log", "paper-identity", "titles", "visit-kinds"),
    writtenBy = "the iOS HistoryVectorsTests with TEST_RUNNER_HISTORY_VECTORS_WRITE=1",
)

class MaintenanceLogVectorsTest {
    private val bucharest: ZoneId = ZoneId.of("Europe/Bucharest")

    @Test
    fun `each file of answers has its test`() {
        val files = HistoryVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
        assertEquals(HistoryVectors.files, files.map { it.nameWithoutExtension }.toSet())
    }

    private fun seconds(case: JsonObject, key: String): Instant = Instant.ofEpochSecond(case.long(key))

    private fun items(case: JsonObject): List<HistoryItemSnapshot> = case.getValue("items").jsonArray.map {
        val item = it.jsonObject
        HistoryItemSnapshot(
            componentKey = item.textOrNull("componentKey"), name = item.text("name"),
            occurredAt = seconds(item, "occurredAt"), metricReading = item.doubleOrNull("metricReading"),
        )
    }

    private fun readings(case: JsonObject): List<Reading> = case.getValue("readings").jsonArray.map {
        val reading = it.jsonObject
        Reading(moment(reading.text("at")), reading.text("metric").toDouble(), reading.bool("startsCounter"))
    }

    @TestFactory
    fun maintenanceLog(): List<DynamicTest> = HistoryVectors.tests("maintenance-log", { it.text("name") }) { case ->
        val items = items(case)
        val readings = readings(case)
        val now = seconds(case, "now")
        val current = case.doubleOrNull("currentMetric")
        val tracked = MaintenanceLog.trackedComponents(items)
        assertEquals(case.texts("tracked"), tracked.sorted(), "The parts with history")
        val newest = tracked.map { key -> items.filter { it.componentKey == key }.maxOf { it.occurredAt } }
        assertEquals(case.bool("trackedNewestFirst"), newest.zipWithNext().all { (a, b) -> a >= b })
        assertEquals(case.doubleOrNull("monthlyRate"), MaintenanceLog.monthlyRate(readings), "The pace")
        for (element in case.getValue("components").jsonArray) {
            val component = element.jsonObject
            val key = component.text("key")
            assertEquals(
                component.int("occurrences"), MaintenanceLog.occurrences(key, items, now, bucharest).size, key,
            )
            val last = MaintenanceLog.lastOccurrence(key, items, now, bucharest, current, readings)
            assertEquals(component.obj("last")?.let(::occurrence), last?.let(::occurrence), "$key: its last occurrence")
            val typical = MaintenanceLog.typicalInterval(key, items, bucharest, readings)
            assertEquals(component.obj("typical")?.let(::typical), typical, "$key: its typical interval")
            val next = MaintenanceLog.nextEstimate(key, items, now, bucharest, readings, current)
            assertEquals(component.obj("next")?.let(::estimate), next, "$key: its next estimate")
        }
    }

    private fun JsonObject.obj(key: String): JsonObject? = if (isNull(key)) null else getValue(key).jsonObject

    private data class Occurrence(
        val name: String, val date: Long, val metricAtTime: Double?, val metricSince: Double?, val daysSince: Int,
    )

    private fun occurrence(json: JsonObject) = Occurrence(
        json.text("name"), json.long("date"), json.doubleOrNull("metricAtTime"), json.doubleOrNull("metricSince"),
        json.int("daysSince"),
    )

    private fun occurrence(last: ComponentOccurrence) =
        Occurrence(last.name, last.date.epochSecond, last.metricAtTime, last.metricSince, last.daysSince)

    private fun typical(json: JsonObject) = TypicalInterval(
        json.doubleOrNull("metric"), json.textOrNull("days")?.toInt(), json.int("sampleCount"),
    )

    private fun estimate(json: JsonObject) = NextEstimate(
        requireNotNull(CalendarDay.parse(json.text("day"))), json.doubleOrNull("metric"),
        NextEstimate.Basis.entries.first { it.raw == json.text("basis") }, json.int("sampleCount"),
    )

    @TestFactory
    fun labour(): List<DynamicTest> = HistoryVectors.tests("labour", { it.toString().take(LABEL) }) { case ->
        when {
            "line" in case -> assertEquals(case.bool("matches"), LabourLine.matches(case.text("line")))
            "names" in case -> assertEquals(case.texts("work"), LabourLine.work(case.texts("names")))
            // A part's key needs the catalog: the store's tests read those.
            else -> assertTrue("partName" in case)
        }
    }

    private companion object {
        const val LABEL = 60
    }
}
