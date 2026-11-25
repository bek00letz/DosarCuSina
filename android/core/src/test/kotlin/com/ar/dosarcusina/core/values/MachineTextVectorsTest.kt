package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.time.Instant

/** Text for machines (ISO days, digests, moments, machine JSON), pinned against the iOS app's answers. */
class MachineTextVectorsTest {
    @TestFactory
    fun `days, digests and padding are written as on the iPhone`(): List<DynamicTest> =
        Vectors.tests("machine-text", { label(it, "padded", "isoDay", "isoMonthDay", "hex") }) { case ->
            val written = when {
                case.containsKey("padded") ->
                    case.ints("padded").let { (number, width) -> MachineText.padded(number.toLong(), width) }
                case.containsKey("isoDay") ->
                    case.ints("isoDay").let { (year, month, day) -> MachineText.isoDay(year, month, day) }
                case.containsKey("isoMonthDay") ->
                    case.ints("isoMonthDay").let { (month, day) -> MachineText.isoMonthDay(month, day) }
                else -> MachineText.hex(case.ints("hex").map { it.toByte() }.toByteArray())
            }
            assertEquals(case.text("text"), written)
        }

    @TestFactory
    fun `a moment reads in every form the iPhone reads`(): List<DynamicTest> =
        Vectors.tests("machine-moment-read", { label(it, "input") }) { case ->
            val read = MachineText.moment(case.text("input"))
            if (case.isNull("moment")) {
                assertNull(read, "Not a moment on the iPhone")
                return@tests
            }
            assertNotNull(read, "A moment on the iPhone")
            val moment = requireNotNull(read)
            assertSameMoment(case.getValue("moment").jsonObject.let { it.long("seconds") to it.long("micros") }, moment)
            assertEquals(case.text("written"), MachineText.moment(moment))
        }

    @TestFactory
    fun `a moment is written in UTC to the second`(): List<DynamicTest> =
        Vectors.tests("machine-moment-write", { label(it, "written") }) { case ->
            val moment = case.getValue("moment").jsonObject
            val instant = Instant.ofEpochSecond(moment.long("seconds"), moment.long("micros") * NANOS_PER_MICRO)
            assertEquals(case.text("written"), MachineText.moment(instant))
        }

    @TestFactory
    fun `machine JSON is written byte for byte as on the iPhone`(): List<DynamicTest> =
        Vectors.tests("machine-json-write", { label(it, "input") }) { case ->
            val tree = MachineText.parse(case.text("input"))
            assertEquals(case.text("compact"), MachineText.json(tree, MachineText.JsonLayout.COMPACT))
            assertEquals(case.text("readable"), MachineText.json(tree, MachineText.JsonLayout.READABLE))
        }

    @TestFactory
    fun `a JSON number is the same value as on the iPhone`(): List<DynamicTest> =
        Vectors.tests("json-numbers", { label(it, "input") }) { case ->
            val tree = MachineText.parse(case.text("input")) as JsonPrimitive
            val number = if (tree.isString || tree is JsonNull || isBool(tree)) null else JsonNumber.read(tree.content)
            assertEquals(case.textOrNull("kind"), kindOf(tree, number))
            // A number is written again as what it reads as; anything else as it is.
            val written = when (number) {
                is JsonNumber.Whole -> MachineText.number(number.value)
                is JsonNumber.Fraction -> MachineText.number(number.value)
                JsonNumber.Unreadable -> return@tests
                null -> tree
            }
            assertEquals(case.text("written"), MachineText.json(written))
        }

    private fun isBool(value: JsonPrimitive): Boolean =
        !value.isString && (value.content == "true" || value.content == "false")

    /** What the iOS app's `JSONValue` reads a value as. */
    private fun kindOf(value: JsonPrimitive, number: JsonNumber?): String? = when {
        value is JsonNull -> "null"
        value.isString -> "string"
        isBool(value) -> "bool"
        number is JsonNumber.Whole -> "int"
        number is JsonNumber.Fraction -> "number"
        else -> null
    }

    @TestFactory
    fun `a Double is written as on the iPhone`(): List<DynamicTest> =
        Vectors.tests("json-doubles", { label(it, "value") }) { case ->
            // Swift's description reads back as the same Double exactly.
            val value = case.text("value").toDouble()
            assertEquals(case.text("written"), MachineText.json(MachineText.number(value)))
        }

    /** Whole seconds and the microseconds after them; a microsecond apart is the same, as a Double holds it. */
    private fun assertSameMoment(expected: Pair<Long, Long>, actual: Instant) {
        val wanted = expected.first * MICROS_PER_SECOND + expected.second
        val got = actual.epochSecond * MICROS_PER_SECOND + Math.round(actual.nano / NANOS_PER_MICRO.toDouble())
        assertTrue(Math.abs(wanted - got) <= 1, "Expected $expected, read $actual")
    }

    private companion object {
        const val NANOS_PER_MICRO = 1_000L
        const val MICROS_PER_SECOND = 1_000_000L
    }
}
