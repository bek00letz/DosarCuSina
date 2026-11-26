package com.ar.dosarcusina.store.readings

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.readings.ReadingBasis
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.examples.ExampleSectionQuestion
import com.ar.dosarcusina.store.examples.GrammaticalGender
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.repairs.with
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.sections.AssetActions
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * One way to record a reading: a lower counter asks and saves nothing, an estimate is never stored, a
 * new counter keeps the old readings and shows the new one, taking a reading away hands its counter on,
 * and the hero value follows the readings (the iOS app's `ReadingTests`, `NewCounterTests` and
 * `EstimatedReadingTests`, their parts that need no other action). Placeholder data only.
 */
class ReadingActionsTest {
    private companion object {
        val KM: MeasurementUnit = MeasurementUnit.KILOMETRES

        /** What a lower reading on a counter that is always read offers, the likelier first. */
        val ALWAYS_READ = listOf(
            LowerReadingAnswer.CORRECT_OLD, LowerReadingAnswer.KEEP_ASIDE, LowerReadingAnswer.NEW_COUNTER,
        )
    }

    private val binder = TestBinderStore().also { it.launch.installBuiltIns(noon("2026-01-01")) }

    private fun actions(day: String) = AssetActions(binder.unit, now = { noon(day) })

    /** A car with its first reading, as making a section records its hero value. */
    private fun car(km: Double = 145_000.0, day: String = "2026-01-10", example: Boolean = false): Asset {
        val golf = binder.unit.perform(now = noon(day)) { step ->
            step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle", isExample = example))
        }
        binder.unit.perform(now = noon(day)) { step ->
            val planned = HouseholdReadings.plan(step, golf.pk, km, noon(day), ReadingSource.PERSON, KM)
            HouseholdReadings.recordReading(step, planned, answer = null)
        }
        return binder.stored(golf)
    }

    private fun counterStart(asset: Asset): MeasurementLog? =
        HouseholdReadings.counterStart(binder.snapshot(), asset.pk, KM)

    private fun visit(asset: Asset, day: String, km: Double): HistoryEntry = binder.unit.perform { step ->
        step.insert(
            HistoryEntry(
                kindRaw = "maintenance", title = "Revizie", occurredAt = noon(day), metricReading = km,
                asset = asset.pk,
            ),
        )
    }

    private fun readings(asset: Asset): List<MeasurementLog> =
        HouseholdReadings.readings(binder.snapshot(), asset.pk).sortedWith(compareBy({ it.recordedAt }, { it.pk }))

    private fun odometer(asset: Asset): FieldValue? = binder.stored(asset).keptValues.value["vehicle.odometer"]

    private fun km(asset: Asset, value: Double, day: String, answer: LowerReadingAnswer? = null) =
        actions(day).recordReading(asset, value, ReadingSource.PERSON, lowerReading = answer)

    private fun question(asset: Asset, value: Double, day: String): LowerReadingAsked =
        assertThrows(LowerReadingAsked::class.java) { km(asset, value, day) }

    @Test
    fun aLowerCounterAsksAndSavesNothing() {
        val golf = car(45_724.0)
        val before = binder.database()
        val asked = question(golf, 4_572.0, "2026-03-01").question
        assertEquals(45_724.0, asked.previous)
        assertEquals(noon("2026-01-10"), asked.previousAt)
        assertEquals(MeasurementUnit.KILOMETRES, asked.unit)
        assertEquals(ALWAYS_READ, asked.answers)
        assertEquals(before, binder.database(), "Asked before anything is written")
        assertTrue(binder.log.entries.isEmpty(), "Asked before the unit opened")
    }

    @Test
    fun yesCorrectsTheOldReading() {
        val golf = car(45_724.0)
        km(golf, 4_572.0, "2026-03-01", LowerReadingAnswer.CORRECT_OLD)
        assertEquals(FieldValue.Number(4_572.0), odometer(golf))
        assertEquals(listOf(4_572.0), readings(golf).map { it.value })
    }

    @Test
    fun noKeepsTheNewReadingAside() {
        val golf = car(45_724.0)
        km(golf, 4_572.0, "2026-03-01", LowerReadingAnswer.KEEP_ASIDE)
        assertEquals(FieldValue.Number(45_724.0), odometer(golf), "The hero value is worked out from the readings")
        val series = HouseholdReadings.readingSeries(binder.snapshot(), golf.pk, MeasurementUnit.KILOMETRES)
        assertEquals(45_724.0, series.current)
        assertEquals(listOf(4_572.0), series.setAside.map { it.metric })
    }

    @Test
    fun anEstimateIsNeverStored() {
        val golf = car(45_724.0)
        val before = binder.database()
        assertNull(actions("2026-03-01").recordReading(golf, 46_000.0, ReadingSource.ESTIMATE))
        assertEquals(before, binder.database())
    }

    @Test
    fun aDocumentsReadingIsDatedByTheDocumentAndAnOlderOneNeverLowersTheCounter() {
        val golf = car(45_724.0)
        actions("2026-11-03").recordReading(golf, 40_000.0, ReadingSource.DOCUMENT, at = noon("2025-06-02"))
        assertEquals(FieldValue.Number(45_724.0), odometer(golf), "Earlier, not lower: nothing to ask")
        val document = readings(golf).first()
        assertEquals(noon("2025-06-02"), document.recordedAt)
        assertNull(document.basis, "A paper that doesn't say how it was read says nothing")
        assertEquals(ReadingBasis.READ, readings(golf).last().basis, "The person read the dashboard")
    }

    @Test
    fun aNewCounterKeepsTheOldReadingsAndShowsTheNewOne() {
        val golf = car()
        val asked = question(golf, 1_200.0, "2026-03-01").question
        assertEquals(LowerReadingAnswer.NEW_COUNTER, asked.asks, "Down to about nothing: a new dashboard is likelier")
        km(golf, 1_200.0, "2026-03-01", LowerReadingAnswer.NEW_COUNTER)
        assertEquals(listOf(145_000.0, 1_200.0), readings(golf).map { it.value }, "The old dashboard's reading stays")
        assertEquals(listOf(false, true), readings(golf).map { it.startsCounter })
        assertEquals(FieldValue.Number(1_200.0), odometer(golf), "Kilometraj shows the new dashboard")
        assertEquals(1_200.0, counterStart(golf)?.value)
        val series = HouseholdReadings.readingSeries(binder.snapshot(), golf.pk, MeasurementUnit.KILOMETRES)
        val counters = series.counters.map { counter -> counter.map { it.metric } }
        assertEquals(listOf(listOf(145_000.0), listOf(1_200.0)), counters)
        assertTrue(series.setAside.isEmpty(), "Nothing is set aside: each counter counts on its own")
    }

    @Test
    fun laterReadingsOnTheNewCounterNeverAskAboutTheOldOne() {
        val golf = car()
        km(golf, 1_200.0, "2026-03-01", LowerReadingAnswer.NEW_COUNTER)
        km(golf, 2_500.0, "2026-04-01")
        assertEquals(FieldValue.Number(2_500.0), odometer(golf))
        val asked = question(golf, 2_000.0, "2026-05-01").question
        assertEquals(2_500.0, asked.previous, "Compared with the new counter only")
    }

    @Test
    fun correctingAReadingOnTheNewCounterKeepsTheCounter() {
        val golf = car()
        km(golf, 12_000.0, "2026-03-01", LowerReadingAnswer.NEW_COUNTER)
        // 12.000 was a typo for 1.200: correcting it takes it away, and the new counter passes on.
        km(golf, 1_200.0, "2026-03-02", LowerReadingAnswer.CORRECT_OLD)
        assertEquals(listOf(145_000.0, 1_200.0), readings(golf).map { it.value })
        assertEquals(listOf(false, true), readings(golf).map { it.startsCounter })
        assertEquals(FieldValue.Number(1_200.0), odometer(golf))
    }

    @Test
    fun correctingTheOldReadingClearsTheVisitThatLoggedIt() {
        val golf = car(45_724.0)
        val visit = visit(golf, "2026-01-10", 45_724.0)
        km(golf, 4_572.0, "2026-03-01", LowerReadingAnswer.CORRECT_OLD)
        assertNull(binder.stored(visit).metricReading, "The visit stays; the wrong number goes with its reading")
    }

    @Test
    fun takingTheFirstReadingOfANewCounterAwayHandsItOn() {
        val golf = car()
        val start = requireNotNull(km(golf, 1_200.0, "2026-03-01", LowerReadingAnswer.NEW_COUNTER))
        km(golf, 2_500.0, "2026-04-01")
        binder.unit.perform { step ->
            HouseholdReadings.deleteReading(step, start)
            HeroMetric.sync(step, golf.pk)
        }
        assertEquals(listOf(145_000.0, 2_500.0), readings(golf).map { it.value })
        val starts = readings(golf).map { it.startsCounter }
        assertEquals(listOf(false, true), starts, "The next reading of the new counter starts it")
        assertEquals(FieldValue.Number(2_500.0), odometer(golf))
    }

    @Test
    fun takingBackTheReadingAVisitRecordedWorksTheHeroOutAgain() {
        val golf = car()
        km(golf, 146_000.0, "2026-03-01")
        val visit = visit(golf, "2026-03-01", 146_000.0)
        binder.unit.perform { step -> HouseholdReadings.removeReading(step, recordedBy = binder.stored(visit)) }
        assertEquals(listOf(145_000.0), readings(golf).map { it.value })
        assertEquals(FieldValue.Number(145_000.0), odometer(golf))
    }

    @Test
    fun notANewCounterTakesItBackAndCanBeUndone() {
        val golf = car()
        km(golf, 1_200.0, "2026-03-01", LowerReadingAnswer.NEW_COUNTER)
        val start = requireNotNull(counterStart(golf))
        val receipt = actions("2026-03-05").notANewCounter(start)
        assertNull(counterStart(golf))
        assertEquals(listOf(145_000.0, 1_200.0), readings(golf).map { it.value }, "Nothing is deleted")
        assertEquals(FieldValue.Number(145_000.0), odometer(golf), "One counter again: the lower one is set aside")

        receipt.undo()
        assertEquals(1_200.0, counterStart(golf)?.value)
        assertEquals(FieldValue.Number(1_200.0), odometer(golf))
    }

    @Test
    fun aCarAlwaysAsksAndTheDropDecidesTheOrder() {
        val golf = car(100_000.0)
        km(golf, 103_000.0, "2026-04-10")
        val small = question(golf, 102_900.0, "2026-05-10").question
        assertEquals(ALWAYS_READ, small.answers)
        assertEquals(LowerReadingAnswer.NEW_COUNTER, question(golf, 1_000.0, "2026-05-10").question.asks)
        val far = question(golf, 80_000.0, "2026-05-10").question
        assertEquals(LowerReadingAnswer.NEW_COUNTER, far.asks, "More than a year of driving")
    }

    @Test
    fun aMeasurementOfAnyKindGoesTheOnePath() {
        val rex = binder.unit.perform { step -> step.insert(Asset(name = "Rex", templateKey = "pet")) }
        val actions = actions("2026-03-01")
        val kg = MeasurementUnit.KILOGRAMS
        actions.recordMeasurement(rex, MeasurementKind.BODY_WEIGHT, 12.4, kg, at = noon("2026-02-01"))
        val log = actions.recordMeasurement(rex, MeasurementKind.BODY_WEIGHT, 11.8, kg)
        assertEquals("bodyWeight", log.kindRaw)
        assertEquals("kg", log.unit)
        val weight = binder.stored(rex).keptValues.value["pet.weight"]
        assertEquals(FieldValue.Number(11.8), weight, "A weight is the newest, never asked about")
    }

    @Test
    fun aReadingOfThePersonsIntoAnExampleAsksFirst() {
        val example = car(example = true)
        val before = binder.database()
        val asked = assertThrows(ExampleSectionQuestion::class.java) { km(example, 146_000.0, "2026-03-01") }
        assertEquals(example.id, asked.sectionId)
        assertEquals(GrammaticalGender.FEMININE, asked.gender, "Mașina")
        assertEquals(before, binder.database())
        assertTrue(readings(example).all { it.isExample }, "The example loader's own reading is an example")
    }

    @Test
    fun theHeroLeavesASectionWithoutReadingsInItsUnitAlone() {
        val golf = binder.unit.perform { step ->
            step.insert(
                Asset(name = "VW Golf 2018", templateKey = "vehicle")
                    .with("vehicle.odometer" to FieldValue.Number(12.0)),
            )
        }
        binder.unit.perform { step -> HeroMetric.sync(step, golf.pk) }
        assertEquals(FieldValue.Number(12.0), odometer(golf))
        assertFalse(binder.snapshot().all(Tables.readings).any())
        assertNotNull(HeroMetric.field(HeroMetric.categoryFields(binder.snapshot(), golf)))
    }
}
