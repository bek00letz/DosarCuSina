package com.ar.dosarcusina.store.templates

import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.catalog.Behavior
import com.ar.dosarcusina.catalog.BinderBoxID
import com.ar.dosarcusina.catalog.BoxGrouping
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.catalog.SectionPocket
import com.ar.dosarcusina.store.LaunchData
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.locks.LockLowering
import com.ar.dosarcusina.store.locks.confirmed
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.time.Instant

/** A box order kept in memory, as the screens keep it on the phone. */
class MemoryBoxOrder(override var saved: List<BinderBoxID> = emptyList()) : BoxOrder {
    override fun save(order: List<BinderBoxID>) {
        saved = order
    }
}

/** A binder with the built-ins installed, its category store, and ways to add sections to it. */
class CategoryBinder(now: Instant = noon("2026-11-03")) {
    val binder = TestBinderStore(now = now)
    val store = TemplateStore(binder.unit, binder.locks)

    init {
        binder.launch.installBuiltIns(now)
    }

    fun template(key: String): CategoryTemplate = requireNotNull(store.template(key)) { key }

    /** The category as stored now. */
    fun stored(template: CategoryTemplate): CategoryTemplate = binder.stored(template)

    /** A section of [key], filed under [parent], made at [at] so sections order by when they were made. */
    fun add(
        name: String,
        key: String,
        parent: Asset? = null,
        isExample: Boolean = false,
        at: Instant = binder.now,
    ): Asset =
        binder.unit.perform { step ->
            step.insert(
                Asset(name = name, templateKey = key, parent = parent?.pk, isExample = isExample, createdAt = at),
            )
        }

    fun asset(asset: Asset): Asset = binder.stored(asset)
}

/**
 * Ordering, showing, grouping, locking, making and deleting categories, and finding one by its part.
 * The iOS app's `TemplateStoreTests`, `BoxGroupingTests`, `SectionLocksTests` and `ChangeOriginTests`,
 * below the screens. Every value is a placeholder.
 */
class TemplateStoreTest {
    private val house = CategoryBinder()
    private val store = house.store

    @Test
    fun categoriesOfOnesOwnAreRealCategoriesThatGoLast() {
        val tools = store.createCustom(
            "Scule", "wrench.and.screwdriver.fill", "orange",
            listOf(FieldSection(
                "tools",
                "Unealtă",
                listOf(FieldDefinition("tools.serial", "Serie", "text", role = "identifier")),
            )),
        )
        assertTrue(tools.key.startsWith(TemplateStore.CUSTOM_KEY_PREFIX))
        assertEquals(Catalog.builtIn.all.size, tools.homeOrder)
        assertEquals(listOf("tools"), house.stored(tools).parts.sections.map { it.key })

        house.add("Bormașină", tools.key)
        assertEquals(1, assertThrows<TemplateStoreError.InUse> { store.delete(tools) }.assetCount)
        assertThrows<TemplateStoreError.BuiltInCannotBeDeleted> { store.delete(
            house.template(BuiltInTemplates.Key.VEHICLE),
        ) }
    }

    @Test
    fun deletingOnesOwnCategoryIsTakenBackWithItsPlace() {
        val notes = store.createCustom("Caiete", "book", listOf(SectionPocket.UPCOMING, SectionPocket.DOCUMENTS))
        val before = house.binder.database()
        val receipt = store.delete(notes)
        assertNull(store.template(notes.key))
        receipt.undo()
        assertEquals(before, house.binder.database(), "Back as it was, its place on the binder included")
    }

    @Test
    fun reorderingFollowsAListsMoves() {
        val first = store.all()[0].key
        store.move(setOf(0), 3)
        assertEquals(first, store.all()[2].key)
        assertEquals(Catalog.builtIn.all.indices.toList(), store.all().map { it.homeOrder })
        val two = store.all().take(2).map { it.key }
        store.move(setOf(0, 1), 5)
        assertEquals(
            two,
            store.all().subList(3, 5).map { it.key },
            "Two at once land together before the one at the place",
        )
    }

    @Test
    fun onlyThePersonsChoicesAreAChangeOfABuiltIn() {
        val pets = house.template(BuiltInTemplates.Key.PET)
        assertEquals(ChangeTime.UNKNOWN, pets.updatedAt, "Installed by the catalog, changed by nobody")
        store.setOnHome(pets, !pets.isOnHome)
        assertEquals(house.binder.now, house.stored(pets).updatedAt)
        assertEquals(!pets.isOnHome, house.stored(pets).isOnHome)
    }

    @Test
    fun theCatalogSaysWhereEachStartsAndThePersonsChoiceWins() {
        val cars = house.template(BuiltInTemplates.Key.VEHICLE)
        val homes = house.template(BuiltInTemplates.Key.HOME)
        val plants = house.template(BuiltInTemplates.Key.PLANTS)
        assertEquals(BoxGrouping.SEPARATE, cars.grouping, "A box for each car")
        assertEquals(BoxGrouping.GROUPED, plants.grouping, "One Plante box")
        assertTrue(cars.chosenGrouping == null && plants.chosenGrouping == null, "Nobody chose yet")

        store.setGrouping(cars, BoxGrouping.GROUPED)
        store.setGrouping(plants, BoxGrouping.SEPARATE)
        assertTrue(house.stored(cars).groupsSections)
        assertFalse(house.stored(plants).groupsSections)
        assertFalse(house.stored(homes).groupsSections, "Per category: the homes keep a box each")
        assertEquals(house.binder.now, house.stored(cars).updatedAt, "One of a built-in's own choices, like its place")

        // Reversible, and kept even when it is what the catalog says.
        store.setGrouping(cars, BoxGrouping.SEPARATE)
        assertEquals(BoxGrouping.SEPARATE, house.stored(cars).chosenGrouping)
    }

    @Test
    fun aNewerCatalogKeepsTheChoice() {
        val cars = house.template(BuiltInTemplates.Key.VEHICLE)
        store.setGrouping(cars, BoxGrouping.GROUPED)
        house.binder.unit.perform { step ->
            val row = requireNotNull(step.row(Tables.templates, cars.pk))
            step.update(row.copy(builtInVersion = row.builtInVersion - 1))
        }
        assertTrue(house.binder.launch.installBuiltIns(house.binder.now))
        val upgraded = house.stored(cars)
        assertEquals(Catalog.builtIn.version, upgraded.builtInVersion)
        assertEquals(BoxGrouping.GROUPED, upgraded.chosenGrouping)
    }

    @Test
    fun aCategoryWithOneBoxOrNoneHasNoChoice() {
        val documents = house.template(BuiltInTemplates.Key.DOCUMENTS)
        val tenancy = house.template(BuiltInTemplates.Key.TENANCY)
        val before = house.binder.database()
        store.setGrouping(documents, BoxGrouping.GROUPED)
        store.setGrouping(tenancy, BoxGrouping.GROUPED)
        assertEquals(before, house.binder.database())
        assertEquals(BoxGrouping.SEPARATE, house.stored(documents).grouping)
    }

    @Test
    fun theOrderIsKeptAroundTheOneBoxOnceTheChoiceIsSaved() {
        val cars = house.template(BuiltInTemplates.Key.VEHICLE)
        val golf = house.add("VW Golf 2018", cars.key, at = noon("2026-01-01"))
        val logan = house.add("Dacia Logan", cars.key, at = noon("2026-02-01"))
        val flat = house.add("Apartament Exemplu", BuiltInTemplates.Key.HOME)
        val order = MemoryBoxOrder(
            listOf(
                BinderBoxID.Section(flat.id),
                BinderBoxID.Section(logan.id),
                BinderBoxID.Agenda,
                BinderBoxID.Section(golf.id),
            ),
        )
        store.setGrouping(cars, BoxGrouping.GROUPED, order)
        assertEquals(
            listOf(BinderBoxID.Section(flat.id), BinderBoxID.Category(cars.key), BinderBoxID.Agenda),
            order.saved,
        )
        store.setGrouping(cars, BoxGrouping.SEPARATE, order)
        assertEquals(
            listOf(
                BinderBoxID.Section(flat.id),
                BinderBoxID.Section(golf.id),
                BinderBoxID.Section(logan.id),
                BinderBoxID.Agenda,
            ),
            order.saved,
            "Each box again, oldest first, where the one box stood",
        )
        val untouched = order.saved
        store.setGrouping(cars, BoxGrouping.SEPARATE, order)
        assertEquals(untouched, order.saved, "No change, no move")
    }

    @Test
    fun lockingTravelsAndOpeningTakesTheConfirmation() {
        val cars = house.template(BuiltInTemplates.Key.VEHICLE)
        store.setSensitive(cars, true)
        val locked = house.stored(cars)
        assertTrue(house.binder.locks.isSensitive(locked))
        assertEquals(house.binder.now, locked.lockedEverywhereAt, "Locking it is written on its record")

        assertThrows<LockLowering.Needed> { store.setSensitive(cars, false) }
        assertTrue(house.binder.locks.isSensitive(house.stored(cars)), "Nothing changed")
        house.binder.now = noon("2026-11-04")
        store.setSensitive(cars, false, confirmed())
        assertFalse(house.binder.locks.isSensitive(house.stored(cars)))
        assertEquals(locked, house.stored(cars), "Opening changes no record: it stays on this phone")
    }

    @Test
    fun aCategoryMadeLockedStaysLocked() {
        val notebook = store.createCustom("Caiet", "book", "gray", emptyList(), isSensitive = true)
        val stored = house.stored(notebook)
        assertTrue(house.binder.locks.isSensitive(stored))
        assertEquals(house.binder.now, stored.lockedEverywhereAt, "One of one's own made locked is locked everywhere")
        val open = store.createCustom("Caiet deschis", "book", "gray", emptyList())
        assertFalse(house.binder.locks.isSensitive(house.stored(open)))
    }

    @Test
    fun aCategoryIsFoundByThePartItPlaysABuiltInFirst() {
        assertEquals(BuiltInTemplates.Key.MEMBER, store.template(withRole = Role.HOLDER)?.key)
        assertEquals(BuiltInTemplates.Key.VEHICLE, store.template(withRole = Role.VEHICLE)?.key)
        val people = store.createCustom("Oameni", "person", listOf(SectionPocket.DOCUMENTS))
        house.binder.unit.perform { step ->
            val row = requireNotNull(step.row(Tables.templates, people.pk))
            step.update(row.withBehavior(row.behavior.copy(role = Role.HOLDER)))
        }
        assertEquals(BuiltInTemplates.Key.MEMBER, store.template(withRole = Role.HOLDER)?.key, "A built-in comes first")
        assertEquals(setOf(BuiltInTemplates.Key.MEMBER, people.key), store.keys(playing = Role.HOLDER))
        val byKey = store.templatesByKey()
        assertEquals(BuiltInTemplates.Key.MEMBER, byKey.key(withRole = Role.HOLDER))
        assertTrue(byKey.plays(Role.SUBSCRIPTION, BuiltInTemplates.Key.SUBSCRIPTION))
        assertEquals(Behavior.STANDARD, byKey.behavior(of = "custom.not-installed"))
    }
}
