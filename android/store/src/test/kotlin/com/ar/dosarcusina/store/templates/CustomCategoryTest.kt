package com.ar.dosarcusina.store.templates

import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.catalog.Behavior
import com.ar.dosarcusina.catalog.Box
import com.ar.dosarcusina.catalog.BoxGrouping
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.CategorySwitches
import com.ar.dosarcusina.catalog.CategorySwitches.Counter
import com.ar.dosarcusina.catalog.CategorySwitches.Service
import com.ar.dosarcusina.catalog.Listing
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.obligations.ObligationStatus
import com.ar.dosarcusina.store.obligations.status
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * A category of one's own made, changed and taken back through its switches: its deadlines asked
 * about first, nothing filed lost, its grouping the one a box's menu sets, and its sections standing
 * on their own where it no longer belongs. The iOS app's `CustomCategoryBehaviourTests`,
 * `OwnCategoriesBelongTests` and `CategoryOffersAndVisitsTests`, below the screens. Every value is a
 * placeholder.
 */
class CustomCategoryTest {
    private val house = CategoryBinder()
    private val store = house.store

    private fun engineHours(every: Int? = null) = CategorySwitches(service = Service(Counter.ENGINE_HOURS, every))

    /** A section with its first service on [due], as the add flow makes it. */
    private fun section(
        name: String,
        category: CategoryTemplate,
        serviceKey: String,
        due: String,
    ): Pair<Asset, Obligation> {
        val asset = house.add(name, category.key)
        val blueprint = house.stored(category).parts.blueprints.single { it.key == serviceKey }
        val rule = requireNotNull(blueprint.recurrence?.let(RecurrenceRule.codec::decode))
        val service = house.binder.unit.perform { step ->
            step.insert(
                Obligation(
                    title = blueprint.title,
                    blueprintKey = blueprint.key,
                    kindRaw = blueprint.kind,
                    dueDayISO = due,
                    asset = asset.pk,
                )
                    .withKeptRecurrence(KeptObject.made(rule, RecurrenceRule.codec)),
            )
        }
        return asset to service
    }

    private fun stored(obligation: Obligation): Obligation = house.binder.stored(obligation)

    private fun rule(obligation: Obligation): RecurrenceRule = stored(obligation).keptRecurrence.value

    private fun metric(every: Double) = RecurrenceRule.Metric(every, "h", 1, "year")

    // One box is the grouping

    @Test
    fun oneBoxForAllIsTheCategorysGroupingBothWays() {
        val boats = store.createCustom("Bărci", "sailboat.fill", CategorySwitches(grouping = BoxGrouping.GROUPED))
        assertEquals(Box.PER_SECTION, boats.behavior.box, "Never a box of the whole category's again")
        assertTrue(boats.chosenGrouping == BoxGrouping.GROUPED && boats.groupsSections)
        assertEquals(BoxGrouping.GROUPED, boats.switches.grouping)

        store.setGrouping(boats, BoxGrouping.SEPARATE)
        assertEquals(
            BoxGrouping.SEPARATE,
            house.stored(boats).switches.grouping,
            "A box's menu changes what the form reads",
        )

        val receipt = store.editCustom(
            boats,
            "Bărci",
            "sailboat.fill",
            CategorySwitches(grouping = BoxGrouping.GROUPED),
            false,
        )
        assertEquals(BoxGrouping.GROUPED, house.stored(boats).chosenGrouping)
        assertEquals(
            BoxGrouping.SEPARATE,
            house.stored(boats).groupingOffer(3),
            "Split again from the box, as any other",
        )
        receipt.undo()
        assertEquals(BoxGrouping.SEPARATE, house.stored(boats).chosenGrouping)

        val alone = store.createCustom("Piane", "music.note", CategorySwitches.DEFAULTS)
        assertTrue(
            alone.chosenGrouping == null && alone.grouping == BoxGrouping.SEPARATE,
            "One each, nothing chosen yet",
        )
    }

    @Test
    fun anOlderOneBoxBecomesTheGroupingAndOneLikeWarrantiesKeepsItsBox() {
        val tools = store.createCustom("Unelte", "hammer", CategorySwitches.DEFAULTS)
        val likeWarranties = store.createCustom("Scule", "wrench.and.screwdriver.fill", CategorySwitches.DEFAULTS)
        house.binder.unit.perform { step ->
            // As an earlier version kept „O cutie pentru toate”, and as a backup brings one that
            // behaves like Garanții.
            step.update(tools.withBehavior(tools.behavior.copy(box = Box.WHOLE_CATEGORY)))
            step.update(likeWarranties.withBehavior(Behavior(box = Box.WHOLE_CATEGORY, listing = Listing.BY_WARRANTY)))
        }
        val older = house.stored(tools)
        assertEquals(BoxGrouping.GROUPED, older.switches.grouping, "Read as one box until it is moved")
        val taken = requireNotNull(store.takeBoxAsGrouping(older))
        assertTrue(taken.behavior.box == Box.PER_SECTION && taken.groupsSections, "The same one box")
        assertNull(taken.behaviorData, "Nothing but the standard behaviour is left")
        assertNull(
            store.takeBoxAsGrouping(house.stored(likeWarranties)),
            "One that behaves like Garanții keeps its box",
        )
        assertNull(
            store.takeBoxAsGrouping(house.template(BuiltInTemplates.Key.DOCUMENTS)),
            "A built-in keeps the catalog's box",
        )

        val scule = house.stored(likeWarranties)
        store.editCustom(
            scule,
            "Scule",
            "wrench.and.screwdriver.fill",
            CategorySwitches(grouping = BoxGrouping.GROUPED),
            false,
        )
        assertEquals(Box.WHOLE_CATEGORY, house.stored(scule).behavior.box, "Asked for one box, it keeps the one it has")
        store.editCustom(
            scule,
            "Scule",
            "wrench.and.screwdriver.fill",
            CategorySwitches(grouping = BoxGrouping.SEPARATE),
            false,
        )
        assertTrue(
            house.stored(scule).behavior.box == Box.PER_SECTION && !house.stored(scule).groupsSections,
            "A box each",
        )
    }

    // The switches and the deadlines

    @Test
    fun turningSwitchesOffHidesNothingGoesAndItAllComesBack() {
        val all = CategorySwitches(hasDocuments = true, hasBills = true, service = Service(Counter.ENGINE_HOURS))
        val boats = store.createCustom("Bărci", "sailboat.fill", all)
        val (boat, service) = section("Barca", boats, "custom.service.engineHours", "2027-05-01")
        val berth = house.add("Loc în port", BuiltInTemplates.Key.SUBSCRIPTION, parent = boat)

        // Off: the switches ask about the running service first.
        val none = CategorySwitches(hasDocuments = false, hasBills = false)
        val effects = store.effects(none, boats)
        assertEquals(listOf(service.pk), effects.pausing.map { it.pk })
        assertTrue(effects.resuming.isEmpty())
        val receipt = store.editCustom(boats, "Bărci", "sailboat.fill", none, changingDeadlines = true)
        val off = house.stored(boats)
        assertTrue("documents" !in off.pocketsRaw && "subscriptions" !in off.pocketsRaw)
        assertTrue(off.parts.sections.isEmpty(), "No counter")
        assertEquals(ObligationStatus.PAUSED, stored(service).status, "Paused, not deleted")
        assertEquals(boat.pk, house.asset(berth).parent)

        // "Anulează" puts the category and the deadline back as they were.
        receipt.undo()
        assertEquals(all, house.stored(boats).switches)
        assertEquals(ObligationStatus.ACTIVE, stored(service).status)

        // Off without touching deadlines, then on again: it asks to resume only what it paused.
        store.editCustom(boats, "Bărci", "sailboat.fill", none, changingDeadlines = false)
        assertEquals(ObligationStatus.ACTIVE, stored(service).status, "Left as it was when the person says so")
        ObligationActions(house.binder.unit).pause(stored(service))
        assertEquals(listOf(service.pk), store.effects(all, house.stored(boats)).resuming.map { it.pk })
        store.editCustom(house.stored(boats), "Bărci", "sailboat.fill", all, changingDeadlines = true)
        assertEquals(ObligationStatus.ACTIVE, stored(service).status)
        assertEquals(all, house.stored(boats).switches)
    }

    @Test
    fun changingWhatAServiceCountsByAsksAboutTheOldOne() {
        val boats = store.createCustom(
            "Bărci",
            "sailboat.fill",
            CategorySwitches(service = Service(Counter.KILOMETRES)),
        )
        val (_, service) = section("Barca", boats, "custom.service.kilometres", "2027-05-01")
        assertEquals(listOf(service.pk), store.effects(engineHours(), boats).pausing.map { it.pk })
        val boxOrParent = CategorySwitches(
            service = Service(Counter.KILOMETRES),
            belongsTo = Role.VEHICLE,
            grouping = BoxGrouping.GROUPED,
        )
        assertTrue(store.effects(boxOrParent, boats).isEmpty, "A box or a parent changes no deadline")
    }

    @Test
    fun aNewIntervalAsksFirstThenCountsFromTheNextServiceAndTheDayStays() {
        val boats = store.createCustom("Bărci", "sailboat.fill", engineHours())
        val (_, service) = section("Barca", boats, "custom.service.engineHours", "2027-05-01")
        val oftener = engineHours(50)
        val effects = store.effects(oftener, boats)
        assertEquals(listOf(service.pk), effects.retiming.map { it.pk })
        assertTrue(effects.pausing.isEmpty() && effects.resuming.isEmpty())

        // Left as it was: the category counts by 50 hours, this deadline still by 100.
        val kept = store.editCustom(boats, "Bărci", "sailboat.fill", oftener, changingDeadlines = false)
        assertEquals(50, house.stored(boats).switches.service?.every)
        assertEquals(metric(100.0), rule(service))
        kept.undo()

        val receipt = store.editCustom(boats, "Bărci", "sailboat.fill", oftener, changingDeadlines = true)
        assertEquals(metric(50.0), rule(service))
        assertEquals(ObligationStatus.ACTIVE, stored(service).status)
        assertEquals("2027-05-01", stored(service).dueDayISO, "The day already set stays")
        assertTrue(store.effects(oftener, house.stored(boats)).isEmpty, "Nothing left to ask")

        receipt.undo()
        assertEquals(metric(100.0), rule(service))
        assertEquals(100, house.stored(boats).switches.service?.every)
    }

    @Test
    fun aDeadlineTurnedBackOnTakesTheIntervalItHasNow() {
        val pianos = store.createCustom("Piane", "music.note", CategorySwitches(service = Service(Counter.TIME)))
        val (_, tuning) = section("Pianul", pianos, "custom.service.yearly", "2027-02-01")
        store.editCustom(pianos, "Piane", "music.note", CategorySwitches(), changingDeadlines = true)
        assertEquals(ObligationStatus.PAUSED, stored(tuning).status)
        store.editCustom(
            pianos,
            "Piane",
            "music.note",
            CategorySwitches(service = Service(Counter.TIME, 6)),
            changingDeadlines = true,
        )
        assertEquals(ObligationStatus.ACTIVE, stored(tuning).status)
        assertEquals(RecurrenceRule.Interval(6, "month", "completion"), rule(tuning))
    }

    @Test
    fun renamingKeepsTheKeyAndTheSections() {
        val boats = store.createCustom("Barci", "sailboat.fill", CategorySwitches.DEFAULTS)
        val boat = house.add("Barca", boats.key)
        store.editCustom(boats, "Bărci", "tent.fill", CategorySwitches.DEFAULTS, changingDeadlines = true)
        val renamed = house.stored(boats)
        assertTrue(renamed.key == boats.key && renamed.name == "Bărci" && renamed.symbol == "tent.fill")
        assertEquals(boats.key, house.asset(boat).templateKey)
    }

    @Test
    fun builtInCategoriesKeepTheirFixedBehaviour() {
        val cars = house.template(BuiltInTemplates.Key.VEHICLE)
        val before = house.binder.database()
        assertThrows<TemplateStoreError.BuiltInBehaviourIsFixed> {
            store.editCustom(cars, "Mașini", "car.fill", CategorySwitches.DEFAULTS, changingDeadlines = false)
        }
        assertEquals(before, house.binder.database())
    }

    @Test
    fun visitsComeWithTheServiceSwitch() {
        val cases = listOf(
            CategorySwitches.DEFAULTS to VisitKind.NONE,
            CategorySwitches(hasBills = true) to VisitKind.NONE,
            CategorySwitches(service = Service(Counter.TIME)) to VisitKind.JOB,
            CategorySwitches(service = Service(Counter.KILOMETRES)) to VisitKind.SERVICE,
            engineHours(100) to VisitKind.SERVICE,
        )
        for ((switches, kind) in cases) {
            val made = store.createCustom("Bărci", "sailboat.fill", switches)
            assertEquals(kind, house.stored(made).behavior.visit, switches.toString())
            assertEquals(switches, house.stored(made).switches)
        }
    }

    // Ține de…

    @Test
    fun belongingToNothingAgainBringsItsSectionsBackOnTheirOwn() {
        val tyres = store.createCustom("Anvelope", "circle.circle", CategorySwitches(belongsTo = Role.VEHICLE))
        val car = house.add("VW Golf 2018", BuiltInTemplates.Key.VEHICLE)
        val winter = house.add("Anvelope de iarnă", tyres.key, parent = car)

        val receipt = store.editCustom(
            tyres,
            "Anvelope",
            "circle.circle",
            CategorySwitches(),
            changingDeadlines = false,
        )
        assertNull(house.asset(winter).parent, "Nowhere would list it under the car now")
        receipt.undo()
        assertEquals(car.pk, house.asset(winter).parent)
        assertEquals(Role.VEHICLE, house.stored(tyres).behavior.mayBelongTo)

        // Another part: off the car, ready for a home.
        store.editCustom(
            house.stored(tyres),
            "Anvelope",
            "circle.circle",
            CategorySwitches(belongsTo = Role.HOME),
            false,
        )
        assertNull(house.asset(winter).parent)
    }

    @Test
    fun theChoicesAreThePartsTheBinderPlays() {
        val played = store.all().map { it.behavior.role }
        assertEquals(listOf(Role.HOME, Role.VEHICLE, Role.HOLDER), CategorySwitches.belongingChoices(played))
        val homesOnly = store.all().filter { it.behavior.role == Role.HOME }.map { it.behavior.role }
        assertEquals(
            listOf(Role.HOME, Role.VEHICLE),
            CategorySwitches.belongingChoices(homesOnly, current = Role.VEHICLE),
        )
    }

    @Test
    fun aGroupedOwnCategoryKeepsItsSectionsInItsBoxWhereverTheyAreFiled() {
        val tyres = store.createCustom(
            "Anvelope", "circle.circle", CategorySwitches(belongsTo = Role.VEHICLE, grouping = BoxGrouping.GROUPED),
        )
        val car = house.add("VW Golf 2018", BuiltInTemplates.Key.VEHICLE)
        assertTrue(house.stored(tyres).hasBox(forSectionUnder = car.pk))
        assertTrue(house.stored(tyres).behavior.hasPocketOfItsOwn, "A pocket named after it on the car's page")
        val separate = store.createCustom("Jante", "circle", CategorySwitches(belongsTo = Role.VEHICLE))
        assertTrue(!house.stored(
            separate,
        ).hasBox(forSectionUnder = car.pk) && house.stored(separate).hasBox(forSectionUnder = null))
        assertEquals(
            1,
            house.binder.snapshot().all(Tables.assets).count { it.templateKey == BuiltInTemplates.Key.VEHICLE },
        )
    }
}
