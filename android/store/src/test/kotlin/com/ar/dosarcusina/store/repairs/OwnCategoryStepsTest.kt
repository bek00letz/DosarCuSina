package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.catalog.Behavior
import com.ar.dosarcusina.catalog.Box
import com.ar.dosarcusina.catalog.BoxGrouping
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.CategorySwitches
import com.ar.dosarcusina.catalog.CategorySwitches.Counter
import com.ar.dosarcusina.catalog.CategorySwitches.Service
import com.ar.dosarcusina.catalog.Listing
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.templates.CategoryBinder
import com.ar.dosarcusina.store.templates.behavior
import com.ar.dosarcusina.store.templates.chosenGrouping
import com.ar.dosarcusina.store.templates.groupsSections
import com.ar.dosarcusina.store.templates.withBehavior
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.ZoneId

/**
 * The repairs for categories of one's own: an older one box becomes the grouping, a service gets the
 * visits its switch gives, and a service's rule an earlier version copied into its note is offered
 * for removal. The iOS app's `OwnCategoriesBelongTests.anOlderOneBoxBecomesTheGroupingAndLooksTheSame`,
 * `CategoryOffersAndVisitsTests.ownCategoryVisitsStep` and `DataRepairTests.aServiceRuleKeptAsANoteIsOffered`.
 * Every value is a placeholder.
 */
class OwnCategoryStepsTest {
    private val house = CategoryBinder()
    private val store = house.store
    private val binder = house.binder

    @Test
    fun anOlderOneBoxBecomesTheGroupingAndLooksTheSame() {
        val tools = store.createCustom("Unelte", "hammer", CategorySwitches.DEFAULTS)
        val split = store.createCustom("Rulote", "car.side.rear.open", CategorySwitches(hasBills = true))
        val likeWarranties = store.createCustom("Scule", "wrench.and.screwdriver.fill", CategorySwitches.DEFAULTS)
        binder.unit.performPrivate { step ->
            // As an earlier version kept „O cutie pentru toate”, and as a backup brings one that
            // behaves like Garanții, with an old change time each.
            fun row(pk: Long) = requireNotNull(step.row(Tables.templates, pk))
            val older = row(tools.pk)
            step.update(older.withBehavior(older.behavior.copy(box = Box.WHOLE_CATEGORY)).copy(updatedAt = then))
            val chosen = row(split.pk)
            step.update(
                chosen.withBehavior(chosen.behavior.copy(box = Box.WHOLE_CATEGORY)).copy(boxGroupingRaw = "separate"),
            )
            step.update(
                row(likeWarranties.pk).withBehavior(Behavior(box = Box.WHOLE_CATEGORY, listing = Listing.BY_WARRANTY)),
            )
        }
        house.add("Bormașina", tools.key)

        repairs(binder).detect()

        val after = house.stored(tools)
        assertEquals(Box.PER_SECTION, after.behavior.box)
        assertTrue(after.chosenGrouping == BoxGrouping.GROUPED && after.groupsSections, "The same one box")
        assertEquals(then, after.updatedAt, "Nothing anyone sees changed: no change time")
        val kept = house.stored(split)
        assertTrue(
            kept.behavior.box == Box.PER_SECTION && kept.chosenGrouping == BoxGrouping.SEPARATE,
            "A grouping chosen stays",
        )
        assertEquals(Role.HOME, kept.behavior.role, "Its bills' part stays")
        assertEquals(Box.WHOLE_CATEGORY, house.stored(likeWarranties).behavior.box, "One like Garanții keeps its box")
        assertEquals(Box.WHOLE_CATEGORY, house.template(BuiltInTemplates.Key.DOCUMENTS).behavior.box)
        assertTrue(DataRepairs.step(DataRepairStepId.OWN_CATEGORY_BOXES).runsByItself)

        val before = binder.database()
        repairs(binder).detect()
        assertEquals(before, binder.database(), "Twice is once")
    }

    @Test
    fun aCategoryOfOnesOwnWithAServiceGetsItsSwitchsVisitsByItself() {
        val boats = store.createCustom(
            "Bărci",
            "sailboat.fill",
            CategorySwitches(service = Service(Counter.ENGINE_HOURS)),
        )
        val notes = store.createCustom("Caiete", "book", CategorySwitches.DEFAULTS)
        val stated = store.createCustom("Unelte", "hammer", CategorySwitches(service = Service(Counter.TIME)))
        binder.unit.performPrivate { step ->
            // As an earlier version stored them: no kind, and a kind the person's binder states.
            val boat = requireNotNull(step.row(Tables.templates, boats.pk))
            step.update(boat.withBehavior(boat.behavior.copy(visit = VisitKind.NONE)))
            val tool = requireNotNull(step.row(Tables.templates, stated.pk))
            step.update(tool.withBehavior(tool.behavior.copy(visit = VisitKind.REPAIR)))
        }

        val changed = binder.unit.perform { OwnCategoryVisitsStep.runByItself(it, context()) }

        assertEquals(1, changed)
        assertEquals(VisitKind.SERVICE, house.stored(boats).behavior.visit)
        assertEquals(VisitKind.NONE, house.stored(notes).behavior.visit, "Without the switch, no visits")
        assertEquals(VisitKind.REPAIR, house.stored(stated).behavior.visit, "A kind already stated stays")
        assertEquals(0, binder.unit.perform { OwnCategoryVisitsStep.runByItself(it, context()) }, "Twice is once")
        assertTrue(DataRepairs.step(DataRepairStepId.OWN_CATEGORY_VISITS).runsByItself)
    }

    @Test
    fun aServiceRuleKeptAsANoteIsOfferedAndThePersonsOwnStays() {
        fun deadline(notes: String, counter: Counter): Obligation = binder.unit.perform { step ->
            step.insert(
                Obligation(
                    title = "Revizie periodică", kindRaw = "maintenance", dueDayISO = "2027-05-03",
                    blueprintKey = CategorySwitches.serviceBlueprintKey(counter), notes = notes,
                ),
            )
        }
        // Written with a phone's region: the digits grouped by a comma.
        val copied = deadline("La 10,000 de km sau o dată pe an, ce vine întâi.", Counter.KILOMETRES)
        val hours = deadline("La 100 de ore de motor sau o dată pe an, ce vine întâi.", Counter.ENGINE_HOURS)
        val monthly = deadline("O dată la 12 luni.", Counter.TIME)
        val own = deadline("Uleiul de la Service Exemplu SRL.", Counter.KILOMETRES)
        val changed = deadline("La 10.000 de km sau o dată pe an, ce vine întâi. Și filtrul.", Counter.KILOMETRES)

        val found = applyTwice(binder, DataRepairStepId.SERVICE_NOTES) {
            assertEquals(null, binder.stored(copied).notes)
            assertEquals(null, binder.stored(hours).notes)
            assertEquals(null, binder.stored(monthly).notes)
            assertEquals("Uleiul de la Service Exemplu SRL.", binder.stored(own).notes, "A note the person wrote stays")
            assertTrue(
                binder.stored(changed).notes.orEmpty().endsWith("Și filtrul."),
                "A note the person changed stays",
            )
        }
        assertEquals(3, found.size)
        assertTrue(found.all { it.subject is DataRepairSubject.ServiceNote })
    }

    private fun context() = DataRepairContext(ZoneId.of("Europe/Bucharest"), binder.now, Catalog.builtIn, binder.locks)

    private companion object {
        val then = noon("2026-06-01")
    }
}
