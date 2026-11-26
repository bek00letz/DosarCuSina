package com.ar.dosarcusina.store.readings

import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.readings.ReadingBasis
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.NumberKind
import com.ar.dosarcusina.core.values.RomanianNumber
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.MeasurementLog
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.io.File
import java.time.Instant

/**
 * The iOS app's answers for recording and taking away a reading (shared/test-vectors/readings/, written
 * by ios/DosarCuSinaTests/ReadingVectorsTests.swift), run through this store's own actions: the question
 * asked before the unit opens, and every reading of the section after the step, as saved. `:core`'s
 * `ReadingVectorsTest` runs the same cases through the engine alone.
 */
class RecordingVectorsTest {
    /** One reading as saved: its moment, value, unit, kind, whether it starts a counter, and its basis. */
    private data class Row(
        val at: Instant,
        val value: Double,
        val unit: String,
        val kind: String,
        val startsCounter: Boolean,
        val basis: String?,
    )

    private fun cases(name: String): List<JsonObject> {
        val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
        val file = File(shared, "test-vectors/readings/$name.json")
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content

    private fun JsonObject.textOrNull(key: String) = this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

    private fun JsonObject.double(key: String) = text(key).toDouble()

    private fun JsonObject.bool(key: String) = text(key).toBooleanStrict()

    private fun moment(text: String): Instant = requireNotNull(MachineText.moment(text))

    private fun swiftName(case: Enum<*>): String = case.name.lowercase().split("_")
        .mapIndexed { index, part -> if (index == 0) part else part.replaceFirstChar { it.uppercase() } }
        .joinToString("")

    /** A section of no category keeping the case's readings, and each reading's row by its key. */
    private fun section(binder: TestBinderStore, case: JsonObject): Pair<Asset, Map<String, Long>> =
        binder.unit.performPrivate { step ->
            val asset = step.insert(Asset(name = "Secțiune Exemplu", templateKey = "test.readings"))
            val rows = case.getValue("readings").jsonArray.associate { item ->
                val reading = item.jsonObject
                val log = step.insert(
                    MeasurementLog(
                        kindRaw = reading.text("kind"), value = reading.double("value"), unit = reading.text("unit"),
                        recordedAt = moment(reading.text("at")), startsCounter = reading.bool("startsCounter"),
                        basisRaw = reading.textOrNull("basis"), asset = asset.pk,
                    ),
                )
                reading.text("key") to log.pk
            }
            asset to rows
        }

    /** The section's readings as saved, by the case's key ("new" for the one the step recorded). */
    private fun saved(binder: TestBinderStore, asset: Asset, rows: Map<String, Long>, new: Long?): Map<String, Row> {
        val keys = rows.entries.associate { (key, row) -> row to key }
        return HouseholdReadings.readings(binder.snapshot(), asset.pk).associate { log ->
            val key = if (log.pk == new) "new" else keys.getValue(log.pk)
            key to Row(log.recordedAt, log.value, log.unit, log.kindRaw, log.startsCounter, log.basisRaw)
        }
    }

    private fun expected(case: JsonObject): Map<String, Row> = case.getValue("after").jsonArray.associate { item ->
        val reading = item.jsonObject
        reading.text("key") to Row(
            moment(reading.text("at")), reading.double("value"), reading.text("unit"), reading.text("kind"),
            reading.bool("startsCounter"), reading.textOrNull("basis"),
        )
    }

    private fun plan(binder: TestBinderStore, case: JsonObject, asset: Asset, rows: Map<String, Long>):
        PlannedSectionReading? {
        val planned = case.getValue("planned").jsonObject
        val value = planned.textOrNull("value")?.toDouble() ?: planned.textOrNull("typed")?.let { typed ->
            RomanianNumber.value(typed, NumberKind.entries.first { it.key == planned.text("numberKind") })?.toDouble()
        } ?: return null
        val replaced = planned.getValue("replaces").jsonArray
            .mapTo(mutableSetOf()) { rows.getValue(it.jsonPrimitive.content) }
        return HouseholdReadings.plan(
            view = binder.snapshot(),
            asset = asset.pk,
            value = value,
            at = moment(planned.text("at")),
            source = ReadingSource.entries.first { swiftName(it) == planned.text("source") },
            unit = planned.textOrNull("unit")?.let(MeasurementUnit::of),
            kind = planned.textOrNull("kind")?.let(MeasurementKind::stored),
            basis = ReadingBasis.stored(planned.textOrNull("basis")),
            replaces = { it.pk in replaced },
        )
    }

    @TestFactory
    fun recording(): List<DynamicTest> = cases("recording").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val asking = TestBinderStore()
            val (asset, rows) = section(asking, case)
            val planned = plan(asking, case, asset, rows)
            if (planned == null) {
                assertNull(case["plannedAs"]?.takeUnless { it is JsonNull })
                return@dynamicTest
            }
            val question = case["question"]?.takeUnless { it is JsonNull }?.jsonObject
            if (question == null) {
                HouseholdReadings.askAboutReading(asking.snapshot(), planned, answer = null)
            } else {
                val asked = assertThrows(LowerReadingAsked::class.java) {
                    HouseholdReadings.askAboutReading(asking.snapshot(), planned, answer = null)
                }.question
                assertEquals(question.double("previous"), asked.previous)
                assertEquals(moment(question.text("previousAt")), asked.previousAt)
                assertEquals(question.textOrNull("unit"), asked.unit?.key)
                val answers = question.getValue("answers").jsonArray.map { it.jsonPrimitive.content }
                assertEquals(answers, asked.answers.map(::swiftName))
                // Inside a unit too, before anything is written.
                val before = asking.database()
                assertThrows(LowerReadingAsked::class.java) {
                    asking.unit.perform { step -> HouseholdReadings.recordReading(step, planned, answer = null) }
                }
                assertEquals(before, asking.database(), "Nothing is saved when it asks")
            }
            for (item in case.getValue("outcomes").jsonArray) {
                val outcome = item.jsonObject
                val answer = outcome.textOrNull("answer")
                    ?.let { name -> LowerReadingAnswer.entries.first { swiftName(it) == name } }
                val binder = TestBinderStore()
                val (section, keys) = section(binder, case)
                val step = requireNotNull(plan(binder, case, section, keys))
                val made = binder.unit.perform { HouseholdReadings.recordReading(it, step, answer) }
                assertEquals(outcome.bool("recorded"), made != null)
                assertEquals(expected(outcome), saved(binder, section, keys, made?.pk), "After answering $answer")
            }
        }
    }

    @TestFactory
    fun deleting(): List<DynamicTest> = cases("deleting").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val binder = TestBinderStore()
            val (asset, rows) = section(binder, case)
            val gone = rows.getValue(case.text("delete"))
            val log = requireNotNull(binder.stored(Tables.readings, gone))
            binder.unit.perform { step -> HouseholdReadings.deleteReading(step, log) }
            assertEquals(expected(case), saved(binder, asset, rows, new = null))
        }
    }
}
