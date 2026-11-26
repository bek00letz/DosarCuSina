package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.repairs.DataRepairStepId
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Obligation
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * What launch does to the binder, each step its own app-made unit, a failed one logged by its kind
 * and the next still run (the iOS app's `LaunchData` and `ChangeOriginTests.aFailedLaunchStepIsLogged`).
 */
class LaunchDataTest {
    private class SaveFailed : Exception("Placeholder household value: B-123-ABC")

    private val today = noon("2026-11-10")
    private val binder = TestBinderStore(now = today)
    private val launch = binder.launch

    @Test
    fun theBuiltInsComeInAsTheAppsOwnStepAndOnlyOnce() {
        assertEquals(emptyList<LaunchData.LaunchStep>(), launch.prepare(today))
        val templates = binder.snapshot().all(Tables.templates)
        assertEquals(
            Catalog.builtIn.all.map { it.key },
            templates.map { it.key },
            "Every built-in, in the catalog's order",
        )
        assertTrue(templates.all { it.isBuiltIn && it.updatedAt == ChangeTime.UNKNOWN }, "None with a change time")
        val before = binder.database()
        assertFalse(launch.installBuiltIns(noon("2026-11-11")), "Already installed: nothing changes")
        assertEquals(before, binder.database())
    }

    @Test
    fun aBuiltInStartsWithTheCatalogsLockUnlessThisPhoneChoseOne() {
        val locked = Catalog.builtIn.all.filter { it.isSensitiveByDefault }.map { it.key }
        assertTrue(locked.isNotEmpty(), "The catalog locks some categories")
        // This phone opened one of them before (a built-in installed again after starting over).
        binder.store.locks.set(false, locked.first(), today)
        launch.prepare(today)
        val answers = binder.locks.locked(binder.snapshot().all(Tables.templates))
        assertFalse(answers.getValue(locked.first()), "This phone's choice stays")
        for (key in locked.drop(1)) assertTrue(answers.getValue(key), "$key starts locked, as the catalog says")
        assertTrue(answers.filterKeys { it !in locked }.values.none { it }, "The others start open")
    }

    @Test
    fun aFailedStepIsLoggedByItsKindAndTheNextOnesStillRun() {
        binder.unit.failNextCommitForTesting(SaveFailed())
        assertEquals(listOf(LaunchData.LaunchStep.BUILT_IN_CATEGORIES), launch.prepare(today))
        assertEquals(emptyList<Any>(), binder.snapshot().all(Tables.templates), "Taken back whole")
        val entry = binder.log.entries.single()
        assertEquals(
            PersistenceLog.Entry(
                PersistenceLog.Level.ERROR,
                "Installing the built-in categories",
                SaveFailed::class.qualifiedName!!,
            ),
            entry,
        )
        assertFalse("B-123-ABC" in entry.toString(), "Never a value")

        assertEquals(emptyList<LaunchData.LaunchStep>(), launch.prepare(today))
        assertEquals(
            Catalog.builtIn.all.size,
            binder.snapshot().all(Tables.templates).size,
            "Tried again at the next launch",
        )
    }

    @Test
    fun whatADeletionLetGoGoesBackToACopyOfItsHolder() {
        val car = binder.unit.perform { step -> step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle")) }
        val deadline = binder.unit.perform { step -> step.insert(Obligation(title = "ITP", asset = car.pk)) }
        // The database lets go by itself, as another device's deletion arrives, and a copy of the car is here.
        val copy = runBlocking {
            val stored = binder.stored(car)
            binder.store.database.assets().delete(stored)
            binder.store.database.assets().insert(Asset(id = stored.id, name = stored.name, templateKey = "vehicle"))
        }
        assertEquals(null, binder.stored(deadline).asset)
        assertEquals(car.id, binder.stored(deadline).assetID, "The id of what held it stays")
        val changed = binder.stored(deadline).updatedAt

        assertEquals(emptyList<LaunchData.LaunchStep>(), launch.prepare(today))
        assertEquals(copy, binder.stored(deadline).asset, "Back with the copy")
        assertEquals(changed, binder.stored(deadline).updatedAt, "As the app's own step: no change time")
        assertFalse(launch.rehome(), "Nothing left to put back")
    }

    @Test
    fun theRepairListLooksOnceTheBuiltInsAreIn() {
        // A first-version ITP: its blueprint is found only once the vehicle's category is installed.
        val car = binder.unit.performPrivate { step ->
            step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle"))
        }
        binder.unit.performPrivate { step ->
            step.insert(Obligation(title = "ITP", kindRaw = "legal", dueDayISO = "2027-05-01", asset = car.pk))
        }
        assertEquals(emptyList<LaunchData.LaunchStep>(), launch.prepare(today))
        assertEquals(
            listOf(DataRepairStepId.FIRST_VERSION_DEADLINES),
            binder.repairs.pending.map { it.step },
            "Waiting for the owner",
        )
        assertEquals(binder.repairs.pending, binder.repairs.announcement, "And the calm prompt says so")
        assertEquals(LaunchData.LaunchStep.entries.last(), LaunchData.LaunchStep.REPAIR_LIST, "After the built-ins")
    }
}
