package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/** Romanian numbers, money's stored form, units and folding, pinned against the iOS app's answers. */
class NumberVectorsTest {
    @TestFactory
    fun `a number reads as the iPhone reads it, for every kind`(): List<DynamicTest> =
        Vectors.tests("romanian-number-read", { "${label(it, "input")} (${it.textOrNull("unit") ?: "-"})" }) { case ->
            val origin = if (case.text("origin") == "typed") NumberOrigin.TYPED else NumberOrigin.DOCUMENT
            val unit = case.textOrNull("unit")?.let { MeasurementUnit.of(it) }
            for (kind in NumberKind.entries) {
                val expected = case.getValue(kind.key).jsonObject
                val read = RomanianNumber.read(case.text("input"), kind, origin, unit)
                assertEquals(describe(expected), describe(read), "${kind.key}: ${case.text("input")}")
            }
        }

    @TestFactory
    fun `the machine form reads only as written`(): List<DynamicTest> =
        Vectors.tests("romanian-number-canonical", { label(it, "input") }) { case ->
            val read = RomanianNumber.canonical(case.text("input"))
            assertEquals(case.textOrNull("value"), read?.let(DecimalText::write))
        }

    @TestFactory
    fun `a number is written the Romanian way and reads back`(): List<DynamicTest> =
        Vectors.tests("romanian-number-format", { "${label(it, "value")} ${it.ints("fractionDigits")}" }) { case ->
            val value = requireNotNull(RomanianNumber.canonical(case.text("value")))
            val (fewest, most) = case.ints("fractionDigits")
            val text = RomanianNumber.format(value, fewest, most, case.bool("groupsDigits"))
            assertEquals(case.text("text"), text)
            val readBack = RomanianNumber.value(text, NumberKind.METER_INDEX)
            assertEquals(case.textOrNull("readsBack"), readBack?.let(DecimalText::write))
        }

    @TestFactory
    fun `money keeps its amount as a decimal and its currency in capitals`(): List<DynamicTest> =
        Vectors.tests("money", { label(it, "amountString", "json") }) { case ->
            if (case.containsKey("json")) {
                val read = Money.fromJson(MachineText.parse(case.text("json")))
                assertEquals(case.textOrNull("written"), read?.let { MachineText.json(it.toJson()) })
                return@tests
            }
            val money = Money.of(case.text("amountString"), case.text("currency"))
            if (case.isNull("money")) {
                assertNull(money)
                return@tests
            }
            val expected = case.getValue("money").jsonObject
            assertEquals(expected.text("amount"), money?.amount?.let(DecimalText::write))
            assertEquals(expected.text("currency"), money?.currency)
            assertEquals(expected.text("written"), money?.amountString)
        }

    @TestFactory
    fun `a unit is known by its key in every spelling`(): List<DynamicTest> =
        Vectors.tests("measurement-unit", { label(it, "input") }) { case ->
            val unit = MeasurementUnit.of(case.text("input"))
            if (case.isNull("unit")) {
                assertNull(unit)
            } else {
                val expected = case.getValue("unit").jsonObject
                assertEquals(expected.text("key"), unit?.key)
                assertEquals(expected.text("label"), unit?.label)
                assertEquals(expected.bool("isCatalog"), unit?.isCatalog)
            }
            assertEquals(case.text("storedKey"), MeasurementUnit.storedKey(case.text("input")))
        }

    @TestFactory
    fun `text folds as on the iPhone`(): List<DynamicTest> =
        Vectors.tests("romanian-text-fold", { label(it, "input") }) { case ->
            assertEquals(case.text("folded"), RomanianText.fold(case.text("input")))
        }

    private fun described(value: String, ambiguous: Boolean, needsCheck: Boolean): String =
        "$value ambiguous=$ambiguous needsCheck=$needsCheck"

    private fun describe(expected: JsonObject): String =
        expected.textOrNull("problem")
            ?: described(expected.text("value"), expected.bool("ambiguous"), expected.bool("needsCheck"))

    private fun describe(read: RomanianNumber.Outcome): String = when (read) {
        is RomanianNumber.Outcome.Refused -> read.problem.key
        is RomanianNumber.Outcome.Read ->
            described(DecimalText.write(read.reading.value), read.reading.isAmbiguous, read.reading.needsCheck)
    }
}
