package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

/** One step for the person is one unit of work: everything is kept, or nothing (the iOS app's `UnitOfWorkTests`). */
class UnitOfWorkTest {
    private class ForcedFailure : Exception("Forced")

    private class LateQuestion : Exception("Asked too late"), StepQuestion

    private val binder = TestBinderStore()
    private val unit = binder.unit

    private fun count(table: Table<*>): Int = binder.snapshot().all(table).size

    @Test
    fun aFailureKeepsNothingOfTheStep() {
        var afterCommitRan = false
        assertThrows<ForcedFailure> {
            unit.perform { step ->
                val car = step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle"))
                step.insert(Obligation(title = "RCA", kindRaw = "insurance", dueDayISO = "2027-01-10", asset = car.pk))
                unit.afterCommit { afterCommitRan = true }
                throw ForcedFailure()
            }
        }
        assertEquals(0, count(Tables.assets))
        assertEquals(0, count(Tables.obligations))
        assertFalse(afterCommitRan, "Nothing that waits for the save runs when it fails")
        assertFalse(unit.isOpen)
    }

    @Test
    fun aFailedSaveKeepsNothingAndTheNextUnitWorks() {
        unit.failNextCommitForTesting(ForcedFailure())
        assertThrows<ForcedFailure> { unit.perform { step -> step.insert(Asset(name = "VW Golf 2018")) } }
        assertEquals(0, count(Tables.assets))
        unit.perform { step -> step.insert(Asset(name = "VW Golf 2018")) }
        assertEquals(1, count(Tables.assets))
    }

    @Test
    fun aUnitOpenedInsideAnotherJoinsIt() {
        assertThrows<ForcedFailure> {
            unit.perform {
                unit.perform { step -> step.insert(Asset(name = "VW Golf 2018")) }
                assertEquals(0, count(Tables.assets), "The inner unit didn't save on its own")
                throw ForcedFailure()
            }
        }
        assertEquals(0, count(Tables.assets))
    }

    @Test
    fun nothingIsWrittenUntilTheUnitSavesItWithItsCardNumbersMasked() {
        val boat = unit.perform { step ->
            val boat = step.insert(Asset(
                name = "Barca de pe lac",
                templateKey = "other",
                notes = "Card 4111 1111 1111 1111",
            ))
            assertEquals(
                emptyList<Asset>(),
                runBlocking { binder.store.database.assets().all() },
                "Nothing written yet",
            )
            assertEquals(boat, step.row(Tables.assets, boat.pk), "The step sees its own change")
            boat
        }
        assertEquals(
            "Card •••• 1111",
            binder.stored(boat).notes,
            "Saved through the unit, so only the last four digits stay",
        )
    }

    @Test
    fun anotherThreadsSaveWaitsAndIsNotTakenBackWithAFailedStep() {
        val inside = CountDownLatch(1)
        val trying = AtomicBoolean(false)
        val other = Thread {
            inside.await()
            trying.set(true)
            unit.perform { step -> step.insert(Provider(name = "Service Exemplu SRL")) }
        }
        other.start()
        assertThrows<ForcedFailure> {
            unit.perform { step ->
                step.insert(Asset(name = "VW Golf 2018"))
                inside.countDown()
                // The other save waits on the store's write lock, outside this step.
                val parked = setOf(Thread.State.WAITING, Thread.State.TIMED_WAITING)
                while (!trying.get() || other.state !in parked) Thread.onSpinWait()
                assertEquals(0, count(Tables.providers), "It hasn't slipped in")
                throw ForcedFailure()
            }
        }
        other.join()
        assertEquals(0, count(Tables.assets), "The failed step kept nothing")
        assertEquals(1, count(Tables.providers), "The other save, on its own, was kept")
    }

    @Test
    fun aFileAFailedStepKeptGoesAndOneNoRecordNamesGoesAfterASave() {
        assertThrows<ForcedFailure> {
            unit.perform { step ->
                step.insert(Asset(name = "Casa", photoData = step.keep(picture(7, 7))))
                throw ForcedFailure()
            }
        }
        assertEquals(emptyList<String>(), binder.store.files.folder.list().orEmpty().toList())
        val home = unit.perform { step -> step.insert(Asset(name = "Casa", photoData = step.keep(picture(7, 7)))) }
        assertEquals(listOf(picture(7, 7).sha256), binder.store.files.folder.list().orEmpty().toList())
        unit.perform { step -> step.update(binder.stored(home).copy(photoData = null)) }
        assertEquals(
            emptyList<String>(),
            binder.store.files.folder.list().orEmpty().toList(),
            "Nothing names it any more",
        )
    }

    @Test
    fun workAfterASaveRunsOnceItIsKeptAndAFailureThereIsLogged() {
        val ran = mutableListOf<String>()
        unit.perform { step ->
            step.insert(Asset(name = "Casa"))
            unit.afterCommit { ran += "first" }
            unit.afterCommit { error("Not this one") }
            unit.afterCommit { ran += "third" }
            assertEquals(emptyList<String>(), ran, "Not before the save")
        }
        assertEquals(listOf("first", "third"), ran)
        assertEquals(
            listOf(PersistenceLog.Entry(
                PersistenceLog.Level.ERROR,
                "Work after a save",
                "java.lang.IllegalStateException",
            )),
            binder.log.entries,
        )
        unit.afterCommit { ran += "now" }
        assertEquals("now", ran.last(), "With no unit open, at once")
    }

    @Test
    fun aQuestionAskedAfterTheStepWroteIsLogged() {
        assertThrows<LateQuestion> {
            unit.perform { step ->
                step.insert(Asset(name = "Casa"))
                throw LateQuestion()
            }
        }
        val entry = binder.log.entries.single()
        assertEquals(PersistenceLog.Level.FAULT, entry.level)
        assertTrue(entry.kind.endsWith("LateQuestion"))
        assertThrows<LateQuestion> { unit.perform { throw LateQuestion() } }
        assertEquals(1, binder.log.entries.size, "Asked before anything was written: as it should be")
    }

    @Test
    fun aStepIsGoodOnlyWhileItsWorkRuns() {
        val kept = unit.perform { step -> step }
        assertThrows<IllegalStateException> { kept.all(Tables.assets) }
    }

    @Test
    fun aRecordGetsItsRowAsItIsMadeAndNoRowIsGivenTwice() {
        val first = unit.perform { step ->
            val car = step.insert(Asset(name = "VW Golf 2018"))
            val deadline = step.insert(Obligation(title = "ITP", asset = car.pk))
            assertEquals(car.pk, deadline.asset)
            car
        }
        unit.perform { step -> step.delete(binder.stored(first)) }
        val second = unit.perform { step -> step.insert(Asset(name = "Dacia Logan 2015")) }
        assertTrue(second.pk > first.pk, "A row a deleted record had is never given again")
    }

    @Test
    fun aCategoryMadeLockedIsLockedBeforeItIsSaved() {
        val boats = unit.perform { step ->
            val boats = step.insert(CategoryTemplate(key = "custom.boats", name = "Bărci"))
            step.lockMadeWith(boats, locked = true)
            boats
        }
        val saved = binder.stored(boats)
        assertTrue(binder.locks.isSensitive(saved), "Locked on this phone")
        assertEquals(binder.now, saved.lockedEverywhereAt, "And on every phone: the lock travels")
        assertThrows<IllegalArgumentException> { unit.perform { step -> step.lockMadeWith(saved, false) } }
    }

    @Test
    fun deletingARecordLetsGoOfEveryLinkToIt() {
        val (car, tyres) = unit.perform { step ->
            val car = step.insert(Asset(name = "VW Golf 2018"))
            val child = step.insert(Asset(name = "Anvelope", parent = car.pk))
            val firm = step.insert(Provider(name = "Service Exemplu SRL"))
            step.setLinked(Tables.providerAssets, firm.pk, listOf(car.pk))
            car to child
        }
        unit.perform { step -> step.delete(binder.stored(car)) }
        assertNull(binder.stored(tyres).parent, "What was filed under it stays, its link let go")
        assertEquals(
            emptyList<Long>(),
            binder.snapshot().linked(Tables.providerAssets, 1),
            "The firm no longer looks after it",
        )
    }
}
