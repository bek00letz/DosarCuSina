package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.readings.CounterReadings
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.readings.ReadingBasis
import com.ar.dosarcusina.core.readings.Recording
import com.ar.dosarcusina.core.readings.StoredReading
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId

/** A bill's meter index, as the iOS app reads it, and recorded through the one reading path. */
class MeterVectorsTest {
    private val bucharest: ZoneId = ZoneId.of("Europe/Bucharest")

    @TestFactory
    fun `a bill's index`(): List<DynamicTest> = SubscriptionVectors.tests("meter", { label(it, "index") }) { case ->
        val day = case.day("day")
        val reading = SubscriptionMeter.reading(
            index = case.optionalText("index")?.let(::BigDecimal),
            basis = case.optionalText("basis"),
            service = case.optionalText("service"),
            day = day,
        )
        if (case.isNull("reading")) {
            assertNull(reading)
            return@tests
        }
        val expected = case.getValue("reading").jsonObject
        checkNotNull(reading)
        assertEquals(expected.getValue("value").jsonPrimitive.double, reading.value)
        assertEquals(expected.text("kind"), reading.kind.raw)
        assertEquals(expected.text("unit"), reading.unit.key)
        assertEquals(expected.day("day"), reading.day)
        assertEquals(expected.optionalText("basis"), reading.basis?.raw)
        val planned = reading.planned(existing = emptyList(), zone = bucharest)
        assertEquals(Instant.parse(expected.text("at")), planned.at)
        assertEquals(reading.basis, planned.basis)
    }

    private fun stored(key: Long, at: String, value: Double, basis: ReadingBasis? = null) =
        StoredReading(key, Instant.parse(at), value, MeasurementUnit.CUBIC_METRES, MeasurementKind.GAS, basis = basis)

    private val gas: String
        get() = checkNotNull(ServiceKind.services.firstOrNull { it.meter == MeasurementKind.GAS }).key

    @Test
    fun `a bill filed again records its index once`() {
        val day = checkNotNull(CalendarDay.parse("2026-10-05"))
        val reading = checkNotNull(SubscriptionMeter.reading(BigDecimal("12345"), null, gas, day))
        val kept = stored(1, "2026-10-05T09:00:00Z", 12345.0)
        assertTrue(reading.isRecorded(kept, bucharest))
        assertFalse(reading.isRecorded(stored(1, "2026-10-04T09:00:00Z", 12345.0), bucharest), "Another day")
        assertFalse(reading.isRecorded(stored(1, "2026-10-05T09:00:00Z", 12346.0), bucharest), "Another index")
        // Filed again, it replaces the reading the bill recorded before: nothing to ask.
        val planned = reading.planned(listOf(kept), bucharest, replaces = setOf(1))
        assertEquals(setOf(1L), planned.replaces)
        assertTrue(CounterReadings.recording(planned, listOf(kept), null) is Recording.Records)
    }

    @Test
    fun `a lower index is asked about through the one reading path`() {
        val day = checkNotNull(CalendarDay.parse("2026-11-05"))
        val reading = checkNotNull(SubscriptionMeter.reading(BigDecimal("12000"), "read", gas, day))
        val before = listOf(stored(1, "2026-10-05T09:00:00Z", 12345.0))
        val planned = reading.planned(before, bucharest)
        assertTrue(CounterReadings.question(planned, before, null) != null, "A lower counter asks first")
    }

    @Test
    fun `the last index is the cleaned series' last`() {
        val readings = listOf(
            stored(1, "2026-09-05T09:00:00Z", 12000.0),
            stored(2, "2026-10-05T09:00:00Z", 12345.0, ReadingBasis.ESTIMATED),
        )
        val last = checkNotNull(SubscriptionMeter.last(gas, readings, bucharest) { it.key == 2L })
        assertEquals(12345.0, last.value)
        assertEquals(CalendarDay.parse("2026-10-05"), last.day)
        assertTrue(last.isFromDocument)
        assertTrue(last.isEstimate)
        val noMeter = ServiceKind.services.first { it.meter == null }.key
        assertNull(SubscriptionMeter.last(noMeter, readings, bucharest) { false })
        assertNull(SubscriptionMeter.last(gas, emptyList(), bucharest) { false })
    }
}
