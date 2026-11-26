package com.ar.dosarcusina.store.examples

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.wording.RomanianWords
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.sections.AssetActions
import com.ar.dosarcusina.store.templates.TemplateStore
import com.ar.dosarcusina.store.view
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The examples as the person meets them, beside the iOS app's answers ([ExampleVectorsTest]): every
 * record the household makes is an example, loading twice makes one household, the person's own
 * never goes inside one without asking, and the words a screen says come from the app's catalog.
 */
class ExampleDataServiceTest {
    private val now = noon("2026-11-26")
    private val binder = TestBinderStore(now = now).also { it.launch.installBuiltIns(now) }
    private val examples =
        ExampleDataService(binder.unit, binder.launch, TestWording, now = { now }, zone = { bucharest })

    @Test
    fun everyRecordTheHouseholdMakesIsAnExampleAndLoadingTwiceMakesOne() {
        examples.loadExamples()
        val first = binder.database()
        examples.loadExamples()
        assertEquals(first, binder.database(), "Loading twice changes nothing")
        val view = binder.snapshot()
        assertEquals(12, view.all(Tables.assets).size)
        assertTrue(view.all(Tables.assets).all { it.isExample })
        assertTrue(view.all(Tables.obligations).isNotEmpty() && view.all(Tables.obligations).all { it.isExample })
        assertTrue(view.all(Tables.history).all { it.isExample } && view.all(Tables.items).all { it.isExample })
        assertTrue(view.all(Tables.readings).all { it.isExample } && view.all(Tables.providers).all { it.isExample })
        val car = view.all(Tables.assets).single { it.templateKey == "vehicle" }
        val kilometres = view.all(Tables.readings).count { it.asset == car.pk }
        assertEquals(3, kilometres, "The car's kilometres, read three times")
    }

    @Test
    fun somethingOfThePersonsInsideAnExampleAsksFirstInTheAppsWords() {
        examples.loadExamples()
        val car = binder.snapshot().all(Tables.assets).single { it.templateKey == "vehicle" }
        val question = assertThrows(ExampleSectionQuestion::class.java) {
            AssetActions(binder.unit, now = { now }, zone = { bucharest })
                .recordMeasurement(car, MeasurementKind.ODOMETER, value = 150_000.0)
        }
        assertEquals(car.id, question.sectionId)
        assertEquals("Păstrezi „VW Golf” ca a ta?", question.question.written())
        for (word in listOf(question.question, question.explanation, question.instead)) assertTrue(has(word), word.key)

        examples.adopt(car.id)
        assertFalse(binder.snapshot().all(Tables.assets).single { it.pk == car.pk }.isExample)
        assertTrue(binder.snapshot().all(Tables.history).filter { it.asset == car.pk }.none { it.isExample })
    }

    @Test
    fun theToastSaysWhatRemovingDid() {
        examples.loadExamples()
        val removed = ExampleRemoval.remove(examples)
        assertTrue(binder.snapshot().all(Tables.assets).isEmpty())
        assertFalse(ExampleRemoval.isOffered(binder.snapshot().all(Tables.assets)))
        assertEquals("Am șters exemplele.", removed.toast.written())
        assertTrue(has(ExampleRemoval.Removed(removed.receipt, listOf("Apartament Floreasca")).toast))
        removed.receipt.undo()
        assertTrue(ExampleRemoval.isOffered(binder.snapshot().all(Tables.assets)), "Anulează brings them back")
    }

    @Test
    fun anActionInsideAnotherUnitSeesWhatThatUnitMade() {
        val template = requireNotNull(TemplateStore(binder.unit, binder.locks).template("pet"))
        val assets = AssetActions(binder.unit, now = { now }, zone = { bucharest })
        binder.unit.perform(now = now) {
            val pet = assets.create("Max", template, FieldValues(mapOf("pet.weight" to FieldValue.Number(31.5))))
            assertTrue(binder.unit.view().all(Tables.assets).any { it.pk == pet.pk }, "The open step is what it sees")
            assertTrue(binder.snapshot().all(Tables.assets).isEmpty(), "Nothing is saved before the unit ends")
            assets.recordMeasurement(pet, MeasurementKind.BODY_WEIGHT, value = 30.2, at = noon("2026-08-01"))
        }
        assertEquals(2, binder.snapshot().all(Tables.readings).size, "Saved once, both readings")
    }

    private fun has(word: Word): Boolean = RomanianWords.has(word.book, word.key)
}
