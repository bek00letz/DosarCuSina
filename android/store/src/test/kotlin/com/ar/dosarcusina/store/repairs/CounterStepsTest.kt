package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.sections.AssetActions
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.keptValues
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The repairs of counter readings: a reading that lost its digits is offered back, one ten times off its
 * neighbours is offered for removal, a visit's saved estimate is offered for removal, and a hero value
 * that isn't what the readings say is worked out again; each only once applied, once (the iOS app's
 * `DataRepairTests`, its counter part, and `NewCounterTests`' repair). Placeholder data only.
 */
class CounterStepsTest {
    private val long = noon("2025-06-01")
    private val binder = TestBinderStore().also { it.launch.installBuiltIns(noon("2026-01-01")) }

    private fun golf(km: Double): Asset {
        val row = binder.earlier { database ->
            database.assets().insert(
                Asset(name = "VW Golf 2018", templateKey = "vehicle", updatedAt = long)
                    .with("vehicle.odometer" to FieldValue.Number(km)),
            )
        }
        return requireNotNull(binder.stored(Tables.assets, row))
    }

    private fun reading(value: Double, day: String, car: Asset): MeasurementLog {
        val row = binder.earlier { database ->
            database.readings().insert(
                MeasurementLog(
                    kindRaw = "odometer", value = value, unit = "km", recordedAt = noon(day), asset = car.pk,
                    updatedAt = long,
                ),
            )
        }
        return requireNotNull(binder.stored(Tables.readings, row))
    }

    private fun values(car: Asset): List<Double> =
        binder.snapshot().all(Tables.readings).filter { it.asset == car.pk }.map { it.value }.sorted()

    private fun odometer(car: Asset): FieldValue? = binder.stored(car).keptValues.value["vehicle.odometer"]

    /** The owner's car: 45.724 km became 457 when an earlier version read its own field back. */
    @Test
    fun aReadingThatLostItsDigitsIsOfferedBack() {
        val car = golf(457.0)
        reading(45_724.0, "2026-01-10", car)
        val wrong = reading(457.0, "2026-02-01", car)
        val found = applyTwice(binder, DataRepairStepId.COUNTER_OUTLIERS) {
            assertEquals(45_724.0, binder.stored(wrong).value)
            assertEquals(FieldValue.Number(45_724.0), odometer(car))
            assertEquals(long, binder.stored(wrong).updatedAt, "A repair isn't the person's change")
        }
        assertEquals(
            listOf(
                DataRepairSubject.Reading(
                    wrong.id, 457.0, 45_724.0, MeasurementUnit.KILOMETRES, "VW Golf 2018", CalendarDay(2026, 2, 1),
                ),
            ),
            found.map { it.subject },
        )
        val ids = found.map { it.id }
        assertEquals(listOf("counter-outliers:${RepairReading.key(wrong.id)}:457.0"), ids, "The iOS app's id")
        assertTrue(repairs(binder).detect().isEmpty(), "The hero value is right too, so nothing else is offered")
    }

    @Test
    fun aReadingTenTimesOffBothNeighboursIsOfferedForRemoval() {
        val car = golf(47_000.0)
        reading(45_000.0, "2026-01-10", car)
        reading(4_600_000.0, "2026-02-10", car)
        reading(47_000.0, "2026-03-10", car)
        val found = applyTwice(binder, DataRepairStepId.COUNTER_OUTLIERS) {
            assertEquals(listOf(45_000.0, 47_000.0), values(car))
        }
        assertEquals(listOf(null), found.map { (it.subject as DataRepairSubject.Reading).to })
        assertTrue(found.single().id.endsWith(":4600000.0"), "Written as Swift writes the number")
    }

    @Test
    fun aNewCarsFirstSmallReadingIsLeftAlone() {
        val car = golf(1_000.0)
        reading(100.0, "2026-01-10", car)
        reading(1_000.0, "2026-06-10", car)
        assertTrue(repairs(binder).detect().isEmpty())
    }

    @Test
    fun aRepairNeverTakesTheNewCountersFirstReadingForALostDigit() {
        val car = binder.unit.perform { step -> step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle")) }
        val actions = { day: String -> AssetActions(binder.unit, now = { noon(day) }) }
        actions("2026-01-10").recordReading(car, 45_724.0, ReadingSource.PERSON)
        val newCounter = LowerReadingAnswer.NEW_COUNTER
        actions("2026-03-01").recordReading(car, 4_572.0, ReadingSource.PERSON, lowerReading = newCounter)
        actions("2026-04-01").recordReading(car, 5_000.0, ReadingSource.PERSON)
        assertTrue(repairs(binder).detect().none { it.step == DataRepairStepId.COUNTER_OUTLIERS })
    }

    @Test
    fun aVisitsRoundEstimateAboveTheNextReadingIsOffered() {
        val car = golf(45_950.0)
        reading(45_000.0, "2026-01-10", car)
        val visit = binder.earlier { database ->
            database.history().insert(
                HistoryEntry(
                    kindRaw = "maintenance", title = "Revizie", occurredAt = noon("2026-03-01"),
                    metricReading = 46_000.0, asset = car.pk, updatedAt = long,
                ),
            )
        }
        reading(46_000.0, "2026-03-01", car)
        reading(45_950.0, "2026-04-01", car)
        val found = applyTwice(binder, DataRepairStepId.ESTIMATED_VISIT_READINGS) {
            assertNull(binder.stored(Tables.history, visit)?.metricReading, "The visit stays; its guessed reading goes")
            assertEquals(listOf(45_000.0, 45_950.0), values(car))
        }
        assertEquals(DataRepairGroup.ESTIMATES_KEPT_AS_READINGS, DataRepairs.step(found.single().step).group)
    }

    @Test
    fun aHeroValueThatDiffersFromItsReadingsIsOffered() {
        val car = golf(457.0)
        reading(45_724.0, "2026-01-10", car)
        val found = applyTwice(binder, DataRepairStepId.HERO_FROM_READINGS) {
            assertEquals(FieldValue.Number(45_724.0), odometer(car))
        }
        assertEquals(
            listOf(DataRepairSubject.Hero(car.id, 457.0, 45_724.0, MeasurementUnit.KILOMETRES, "VW Golf 2018")),
            found.map { it.subject },
        )
        assertEquals("hero-from-readings:${RepairReading.key(car.id)}:457.0:45724.0", found.single().id)
    }

    @Test
    fun aMissingHeroValueIsOfferedWithItsReadings() {
        val car = binder.earlier { database ->
            database.assets().insert(Asset(name = "VW Golf 2018", templateKey = "vehicle", updatedAt = long))
        }
        val stored = requireNotNull(binder.stored(Tables.assets, car))
        reading(45_724.0, "2026-01-10", stored)
        val found = applyTwice(binder, DataRepairStepId.HERO_FROM_READINGS) {
            assertEquals(FieldValue.Number(45_724.0), odometer(stored))
        }
        assertEquals(null, (found.single().subject as DataRepairSubject.Hero).from)
        assertTrue(found.single().id.endsWith(":-1.0:45724.0"))
    }

    @Test
    fun examplesAreLeftAlone() {
        val car = binder.earlier { database ->
            database.assets().insert(Asset(name = "VW Golf 2018", templateKey = "vehicle", isExample = true))
        }
        val stored = requireNotNull(binder.stored(Tables.assets, car))
        reading(45_724.0, "2026-01-10", stored)
        reading(457.0, "2026-02-01", stored)
        assertTrue(repairs(binder).detect().isEmpty())
    }
}
