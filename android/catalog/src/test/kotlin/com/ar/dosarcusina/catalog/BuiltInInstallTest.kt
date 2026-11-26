package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderAsset
import com.ar.dosarcusina.archive.binder.BinderTemplate
import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MachineText
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.UUID

/** Installing the built-ins, as the iOS app's `TemplateStore.installBuiltIns` and its tests pin it. */
class BuiltInInstallTest {
    private val catalog = Catalog.builtIn
    private val now: Instant = requireNotNull(MachineText.moment("2026-11-26T10:00:00Z"))
    private val earlier: Instant = requireNotNull(MachineText.moment("2026-01-01T00:00:00Z"))

    /** A binder whose built-ins were installed by this catalog, then [choose] made the person's choices. */
    private fun installed(choose: (BinderTemplate) -> BinderTemplate = { it }): Binder {
        val plan = BuiltInInstall.plan(catalog, Binder(), earlier)
        return Binder(templates = plan.templates.map(choose), locks = plan.startingLocks)
    }

    private fun asset(templateKey: String, values: FieldValues) = BinderAsset(
        id = UUID.randomUUID(), templateKey = templateKey, name = "Mașina de spălat", parentId = null,
        symbolOverride = null, tintOverride = null, notes = null,
        values = KeptObject.made(values, FieldValues.codec),
        customFacts = KeptList.made(emptyList(), CustomFact.codec, CustomFact::id), photo = null, isExample = false,
        createdAt = earlier, updatedAt = earlier,
    )

    private fun oldBuiltIn(key: String) = catalog.all.first().template(null, earlier).copy(key = key, name = key)

    @Test
    fun anEmptyBinderGetsEveryBuiltInAsNobodysChange() {
        val plan = BuiltInInstall.plan(catalog, Binder(), now)
        assertEquals(catalog.all.map { it.key }, plan.templates.map { it.key })
        assertEquals((0 until catalog.all.size).toList(), plan.templates.map { it.homeOrder }, "In the catalog's order")
        for ((template, definition) in plan.templates.zip(catalog.all)) {
            assertEquals(ChangeTime.UNKNOWN, template.updatedAt, "${template.key} starts with no change time")
            assertEquals(now, template.createdAt)
            assertEquals(definition.isOnHomeByDefault, template.isOnHome)
            assertNull(template.boxGrouping)
            assertTrue(template.isBuiltIn)
            assertEquals(catalog.version, template.version)
            assertEquals(definition.sections, template.sections.items)
        }
        assertEquals(catalog.all.associate { it.key to it.isSensitiveByDefault }, plan.startingLocks)
        assertTrue(plan.removedTemplates.isEmpty())
    }

    @Test
    fun aBinderAtThisCatalogStaysAsItIs() {
        val plan = BuiltInInstall.plan(catalog, installed(), now)
        assertFalse(plan.changesAnything)
        assertTrue(plan.startingLocks.isEmpty())
    }

    @Test
    fun anOlderCatalogsBuiltInsTakeThisOnesKeepingThePersonsChoices() {
        val choicesAt: Instant = requireNotNull(MachineText.moment("2026-06-01T00:00:00Z"))
        val binder = installed { template ->
            if (template.key != "vehicle") return@installed template
            template.copy(
                version = catalog.version - 1, name = "Mașini vechi", sections = KeptList.made(
                    emptyList(), com.ar.dosarcusina.archive.v3.FieldSection.codec,
                    com.ar.dosarcusina.archive.v3.FieldSection::key,
                ),
                homeOrder = 7, isOnHome = false, boxGrouping = "grouped", updatedAt = choicesAt,
            )
        }
        val plan = BuiltInInstall.plan(catalog, binder, now)
        val vehicle = plan.templates.single()
        assertEquals("vehicle", vehicle.key)
        assertEquals(catalog.definition("vehicle")!!.name, vehicle.name)
        assertEquals(catalog.definition("vehicle")!!.sections, vehicle.sections.items)
        assertEquals(catalog.version, vehicle.version)
        assertEquals(7, vehicle.homeOrder, "Its place is the person's")
        assertFalse(vehicle.isOnHome, "Whether it shows is the person's")
        assertEquals("grouped", vehicle.boxGrouping, "Its box is the person's")
        assertEquals(choicesAt, vehicle.updatedAt, "An upgrade is the app's step: no change time moves")
        assertEquals(earlier, vehicle.createdAt)
        assertTrue(plan.startingLocks.isEmpty(), "Its lock is the phone's, untouched")
    }

    @Test
    fun aBuiltInMadeIntoACategoryOfOnesOwnIsPutBack() {
        val binder = installed {
            if (it.key == "pet") it.copy(isBuiltIn = false, version = 0, name = "Animale ale mele") else it
        }
        val pet = BuiltInInstall.plan(catalog, binder, now).templates.single()
        assertTrue(pet.isBuiltIn)
        assertEquals(catalog.definition("pet")!!.name, pet.name)
    }

    @Test
    fun aNewerCatalogInTheBinderLeavesEveryBuiltInAlone() {
        val binder = installed { if (it.key == "home") it.copy(version = catalog.version + 1) else it }
        val missing = binder.copy(templates = binder.templates.filter { it.key != "bike" } +
            binder.templates.first { it.key == "vehicle" }.copy(key = "pet", isBuiltIn = false, version = 0))
        val plan = BuiltInInstall.plan(catalog, missing, now)
        assertFalse(plan.changesAnything, "Nothing installed, upgraded or put back by an older build")
    }

    @Test
    fun builtInsMissingFromABinderGoAfterItsCategories() {
        val binder = installed().let { all ->
            all.copy(templates = all.templates.filter { it.key != "espresso" }, locks = all.locks - "espresso")
        }
        val plan = BuiltInInstall.plan(catalog, binder, now)
        val espresso = plan.templates.single()
        assertEquals("espresso", espresso.key)
        assertEquals(binder.templates.maxOf { it.homeOrder } + 1, espresso.homeOrder)
        assertEquals(mapOf("espresso" to false), plan.startingLocks)
    }

    @Test
    fun aBuiltInInstalledAgainKeepsTheLockThisPhoneChose() {
        val binder = installed().let { all ->
            all.copy(templates = all.templates.filter { it.key != "health" }, locks = all.locks + ("health" to false))
        }
        val plan = BuiltInInstall.plan(catalog, binder, now)
        assertEquals("health", plan.templates.single().key)
        assertTrue(plan.startingLocks.isEmpty(), "The phone already chose a lock for health")
    }

    @Test
    fun aReplacedCategoryHandsItsSectionsOverWithTheirFieldsRenamed() {
        val warrantyEnds = CalendarDay(2027, 6, 15)
        val washer = asset(
            "warranty",
            FieldValues(
                mapOf(
                    "warranty.expiry" to FieldValue.Day(warrantyEnds),
                    "warranty.brand" to FieldValue.Text("Bosch"),
                    "warranty.note" to FieldValue.Text("Păstrează cutia"),
                ),
            ),
        )
        val binder = installed().let { all ->
            all.copy(
                templates = all.templates.filter { it.key != "purchase" } + oldBuiltIn("warranty"),
                assets = listOf(washer),
            )
        }
        val plan = BuiltInInstall.plan(catalog, binder, now)
        assertEquals(setOf("warranty"), plan.removedTemplates)
        assertEquals(listOf("purchase"), plan.templates.map { it.key }, "Its successor is installed")
        val moved = plan.assets.single()
        assertEquals(washer.id, moved.id)
        assertEquals("purchase", moved.templateKey)
        assertEquals(FieldValue.Day(warrantyEnds), moved.values.value["purchase.warrantyUntil"])
        assertEquals(FieldValue.Text("Bosch"), moved.values.value["purchase.brand"])
        assertEquals(
            FieldValue.Text("Păstrează cutia"), moved.values.value["warranty.note"], "A key nothing renames stays",
        )
        assertNull(moved.values.value["warranty.expiry"])
    }

    @Test
    fun aRetiredCategoryWithSectionsBecomesTheirOwn() {
        val binder = installed().let { all ->
            all.copy(templates = all.templates + oldBuiltIn("rental"), assets = listOf(asset("rental", FieldValues())))
        }
        val plan = BuiltInInstall.plan(catalog, binder, now)
        val rental = plan.templates.single()
        assertEquals("rental", rental.key)
        assertFalse(rental.isBuiltIn)
        assertEquals(0, rental.version)
        assertTrue(plan.removedTemplates.isEmpty())
    }

    @Test
    fun aRetiredCategoryWithoutSectionsGoesOnceTheBinderHasAllArrived() {
        val binder = installed().let { all -> all.copy(templates = all.templates + oldBuiltIn("rental")) }
        val arriving = BuiltInInstall.plan(catalog, binder, now, binderIsWhole = false)
        assertFalse(arriving.changesAnything, "Its sections may still be coming")
        assertEquals(setOf("rental"), BuiltInInstall.plan(catalog, binder, now, binderIsWhole = true).removedTemplates)
    }

    @Test
    fun theFirstCopyOfAKeyIsTheOneRead() {
        val binder = installed()
        val vehicle = binder.templates.first { it.key == "vehicle" }
        // A second copy, made later, from an older catalog: until copies are joined, the first is read.
        val copy = vehicle.copy(version = catalog.version - 1, createdAt = now)
        val plan = BuiltInInstall.plan(catalog, binder.copy(templates = binder.templates + copy), now)
        assertFalse(plan.changesAnything)
    }
}
