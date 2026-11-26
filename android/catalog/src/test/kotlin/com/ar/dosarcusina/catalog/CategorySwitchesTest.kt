package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.binder.BuiltInDefinition
import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * A category of the person's own answers a few plain questions, and each answer is the same data a
 * built-in has: pockets, its part for capture, a counter and a service. The iOS app's
 * `CategorySwitchesTests` and the pure parts of `CategoryOffersAndVisitsTests`. Every value is a
 * placeholder.
 */
class CategorySwitchesTest {
    private val catalog = Catalog.builtIn

    private fun made(switches: CategorySwitches): CategoryParts = switches.parts()

    private fun rule(blueprint: ObligationBlueprint): RecurrenceRule =
        requireNotNull(blueprint.recurrence?.let(RecurrenceRule.codec::decode))

    private fun parts(definition: BuiltInDefinition) =
        CategoryParts(definition.sections, definition.blueprints, definition.pockets, Behavior.of(definition.behavior))

    private fun builtIn(key: String) = requireNotNull(catalog.definition(key))

    private fun metric(every: Double, unit: String) = RecurrenceRule.Metric(every, unit, 1, "year")

    private fun interval(every: Int, unit: String) = JsonObject(
        mapOf(
            "every" to MachineText.number(every.toLong()),
            "type" to JsonPrimitive("afterInterval"),
            "unit" to JsonPrimitive(unit),
        ),
    )

    private val older = CategoryParts(
        sections = listOf(FieldSection("tool", "Unealtă", listOf(FieldDefinition("tool.serial", "Serie", "text")))),
        blueprints = listOf(
            ObligationBlueprint(
                "tool.check", "Verificare", "maintenance", "ownService",
                recurrence = RecurrenceRule.Interval(1, "year", "completion").toJson(),
            ),
        ),
        pockets = listOf("upcoming", "products", "keyFacts"),
    )

    @Test
    fun withNoChangesACategoryKeepsDocumentsAndGetsABoxPerSection() {
        val parts = made(CategorySwitches.DEFAULTS)
        assertTrue(CategorySwitches.DEFAULTS.hasDocuments)
        assertEquals(
            SectionPocket.STANDARD.map { it.raw },
            parts.pockets,
            "The pockets the first version's Altceva… started with",
        )
        assertEquals(Behavior.STANDARD, parts.behavior)
        assertTrue(parts.blueprints.isEmpty())
        assertTrue(parts.sections.isEmpty())
    }

    @Test
    fun documentsAreTheActePocket() {
        assertTrue("documents" in made(CategorySwitches(hasDocuments = true)).pockets)
        assertFalse("documents" in made(CategorySwitches(hasDocuments = false)).pockets)
    }

    @Test
    fun billsAreSubscriptionsUnderAPlaceLikeAHome() {
        val parts = made(CategorySwitches(hasBills = true))
        assertTrue("subscriptions" in parts.pockets)
        assertEquals(Role.HOME, parts.behavior.role)
        val home = builtIn(BuiltInTemplates.Key.HOME)
        assertTrue("subscriptions" in home.pockets && Behavior.of(home.behavior).role == Role.HOME)
        val without = made(CategorySwitches(hasBills = false))
        assertFalse("subscriptions" in without.pockets)
        assertNull(without.behavior.role)
    }

    @Test
    fun aServiceByACounterIsAHeroCounterAndAServiceDeadlineLikeACars() {
        val boat = made(CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS)))
        val counter = boat.sections.flatMap { it.fields }.single { it.role == "heroMetric" }
        assertEquals("custom.counter.h", counter.key)
        assertTrue(counter.type == "metric" && counter.unit == "h" && counter.isEssential)
        val service = boat.blueprints.single()
        assertEquals("custom.service.engineHours", service.key)
        assertEquals(metric(100.0, "h"), rule(service))

        val trailer = made(CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.KILOMETRES)))
        assertEquals("km", trailer.sections.flatMap { it.fields }.single { it.role == "heroMetric" }.unit)
        val car = builtIn(BuiltInTemplates.Key.VEHICLE).blueprints.single { it.key == "vehicle.service" }
        val byKilometres = trailer.blueprints.single()
        assertEquals(car.kind, byKilometres.kind)
        assertEquals(car.reminders, byKilometres.reminders)
        assertEquals(car.firstDue, byKilometres.firstDue)
        assertEquals(metric(10_000.0, "km"), rule(byKilometres))
    }

    @Test
    fun aServiceByTimeHasNoCounter() {
        val piano = made(CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.TIME)))
        assertTrue(piano.sections.isEmpty())
        assertEquals(listOf(RecurrenceRule.Interval(1, "year", "completion")), piano.blueprints.map(::rule))
    }

    @Test
    fun howOftenStartsAtTheCarsNumbersAndLivesInTheDeadlinesOwnRule() {
        assertEquals(10_000, CategorySwitches.Service(CategorySwitches.Counter.KILOMETRES).every)
        assertEquals(100, CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS).every)
        assertEquals(12, CategorySwitches.Service(CategorySwitches.Counter.TIME).every)

        val boat = made(
            CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS, 150)),
        )
        assertEquals(listOf(metric(150.0, "h")), boat.blueprints.map(::rule))
        val trailer = made(
            CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.KILOMETRES, 7_500)),
        )
        assertEquals(listOf(metric(7_500.0, "km")), trailer.blueprints.map(::rule))
        val boiler = made(
            CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.TIME, 6)),
        ).blueprints.single()
        assertEquals(RecurrenceRule.Interval(6, "month", "completion"), rule(boiler))
        assertEquals(interval(6, "month"), boiler.firstDue, "The first one comes after the same interval")
        val piano = made(
            CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.TIME, 24)),
        ).blueprints.single()
        assertEquals(RecurrenceRule.Interval(2, "year", "completion"), rule(piano), "Whole years stay years")
        assertEquals(1, CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS, 0).every, "Never every zero")
    }

    @Test
    fun theSharedServiceAtItsStartingIntervalIsWhatTheRuleMakes() {
        for (counter in CategorySwitches.Counter.entries) {
            val made = CategorySwitches.serviceBlueprint(CategorySwitches.Service(counter))
            assertEquals(catalog.ownCategories.service(counter), made, counter.raw)
            assertEquals(CategorySwitches.serviceBlueprintKey(counter), made.key)
            catalog.ownCategories.counterField(counter)?.let { field ->
                assertEquals(CategorySwitches.counterFieldKey(requireNotNull(counter.unit)), field.key)
            }
        }
        assertNull(catalog.ownCategories.counterField(CategorySwitches.Counter.TIME))
        val file = MachineText.parse(committed(Catalog.File.OWN_CATEGORIES)) as JsonObject
        val starts = (file.getValue("counters") as JsonArray).associate { entry ->
            val counter = entry as JsonObject
            val name = (counter.getValue("counter") as JsonPrimitive).content
            name to (counter.getValue("defaultEvery") as JsonPrimitive).content.toInt()
        }
        assertEquals(
            CategorySwitches.Counter.entries.associate { it.raw to it.defaultEvery },
            starts,
            "Where each interval starts",
        )
    }

    @Test
    fun changingOnlyHowOftenKeepsTheDeadlineAndItsCounter() {
        val before = made(CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS)))
        val after = CategorySwitches(
            service = CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS, 200),
        ).applied(before)
        assertEquals(before.blueprints.map { it.key }, after.blueprints.map { it.key })
        assertEquals(before.sections, after.sections)
        assertEquals(metric(200.0, "h"), rule(after.blueprints.single()))
        assertEquals(
            CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS, 200),
            CategorySwitches.reading(after, BoxGrouping.SEPARATE).service,
        )
    }

    @Test
    fun oneBoxForAllIsTheGroupingNeverABoxOfTheWholeCategorys() {
        val grouped = made(CategorySwitches(grouping = BoxGrouping.GROUPED))
        assertTrue(grouped.behavior.hasSectionBoxes, "Its sections keep boxes of their own, grouped")
        assertEquals(
            made(CategorySwitches(grouping = BoxGrouping.SEPARATE)),
            grouped,
            "The grouping isn't the definition's",
        )
    }

    @Test
    fun belongingIsWhatPlantsSay() {
        for (role in Role.PARENTS) {
            val parts = made(CategorySwitches(belongsTo = role))
            assertEquals(role, parts.behavior.mayBelongTo)
            assertTrue(parts.behavior.goesUnderTheOnlyOne)
            assertTrue(
                parts.behavior.parentPocket == null && parts.behavior.hasPocketOfItsOwn,
                "A pocket named after it",
            )
            val back = CategorySwitches().applied(parts)
            assertTrue(
                back.behavior.mayBelongTo == null && !back.behavior.goesUnderTheOnlyOne,
                "„Nimic” takes both back",
            )
        }
        assertEquals(listOf(Role.HOME, Role.VEHICLE, Role.HOLDER), Role.PARENTS)
        assertNull(CategorySwitches(belongsTo = Role.SUBSCRIPTION).belongsTo, "Only a part that holds sections")
        assertNull(made(CategorySwitches.DEFAULTS).behavior.mayBelongTo)
    }

    @Test
    fun everyAnswerReadsBackFromTheDataItWrote() {
        val services = listOf<CategorySwitches.Service?>(null) + CategorySwitches.Counter.entries.flatMap { counter ->
            listOf(null, 7, 36).map { CategorySwitches.Service(counter, it) }
        }
        val every = listOf(true, false).flatMap { documents ->
            listOf(true, false).flatMap { bills ->
                services.flatMap { service ->
                    (listOf<Role?>(null) + Role.PARENTS).flatMap { belongsTo ->
                        BoxGrouping.entries.map { CategorySwitches(documents, bills, service, belongsTo, it) }
                    }
                }
            }
        }
        for (switches in every) assertEquals(switches, CategorySwitches.reading(made(switches), switches.grouping))
    }

    @Test
    fun applyingWhatACategoryAnswersChangesNothingBuiltInsIncluded() {
        for (definition in catalog.all.map(::parts) + older) {
            assertEquals(definition, CategorySwitches.reading(definition, BoxGrouping.SEPARATE).applied(definition))
        }
    }

    @Test
    fun aSwitchTouchesOnlyWhatItOwns() {
        val switches = CategorySwitches(
            true, true, CategorySwitches.Service(
                CategorySwitches.Counter.KILOMETRES,
            ), Role.VEHICLE, BoxGrouping.GROUPED,
        )
        val changed = switches.applied(older)
        assertEquals(listOf("upcoming", "products", "subscriptions", "documents", "keyFacts"), changed.pockets)
        assertEquals(listOf("tool", CategorySwitches.COUNTER_SECTION_KEY), changed.sections.map { it.key })
        assertEquals(listOf("tool.check", "custom.service.kilometres"), changed.blueprints.map { it.key })
        assertTrue(changed.behavior.mayBelongTo == Role.VEHICLE && changed.behavior.role == Role.HOME)
        assertEquals(older, CategorySwitches.reading(older, BoxGrouping.SEPARATE).applied(changed))
    }

    @Test
    fun aPocketANewerBuildWroteStaysAfterTheOnesThisBuildKnows() {
        val newer = older.copy(pockets = listOf("upcoming", "garden", "keyFacts"))
        assertEquals(
            listOf("upcoming", "documents", "keyFacts", "garden"),
            CategorySwitches(hasDocuments = true).applied(newer).pockets,
        )
    }

    @Test
    fun visitsComeOnlyWithAServiceAJobByTimeAServiceByACounter() {
        val cases = listOf(
            CategorySwitches.DEFAULTS to VisitKind.NONE,
            CategorySwitches(hasBills = true) to VisitKind.NONE,
            CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.TIME)) to VisitKind.JOB,
            CategorySwitches(
                service = CategorySwitches.Service(CategorySwitches.Counter.KILOMETRES),
            ) to VisitKind.SERVICE,
            CategorySwitches(
                service = CategorySwitches.Service(CategorySwitches.Counter.ENGINE_HOURS, 100),
            ) to VisitKind.SERVICE,
        )
        for ((switches, kind) in cases) {
            val parts = made(switches)
            assertEquals(kind, parts.behavior.visit, switches.toString())
            assertEquals(VisitKind.NONE, switches.copy(service = null).applied(parts).behavior.visit)
            val byKilometres = switches.copy(service = CategorySwitches.Service(CategorySwitches.Counter.KILOMETRES))
            assertEquals(VisitKind.SERVICE, byKilometres.applied(parts).behavior.visit)
            assertEquals(parts, CategorySwitches.reading(parts, BoxGrouping.SEPARATE).applied(parts))
        }
        // How often alone leaves a stated kind as it is.
        val piano = made(CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.TIME)))
        val stated = piano.copy(behavior = piano.behavior.copy(visit = VisitKind.REPAIR))
        val oftener = CategorySwitches(service = CategorySwitches.Service(CategorySwitches.Counter.TIME, 6))
        assertEquals(VisitKind.REPAIR, oftener.applied(stated).behavior.visit)
    }

    @Test
    fun aVisitKindReadsByOneRuleOlderAndNewerAlike() {
        assertEquals(VisitKind.VET, Behavior.of(builtIn(BuiltInTemplates.Key.PET).behavior).visit)
        assertEquals(
            VisitKind.NONE,
            Behavior.of(CategoryBehavior(box = "perSection")).visit,
            "No kind stated: no visits",
        )
        assertEquals(VisitKind.JOB, VisitKind.stored(JsonPrimitive("overhaul")), "A newer kind reads as a job done")
        val words = mapOf("mechanic" to VisitKind.SERVICE, "vet" to VisitKind.VET, "doctor" to VisitKind.DOCTOR,
            "handyman" to VisitKind.JOB, "shipwright" to VisitKind.JOB)
        for ((trade, kind) in words) {
            val earlier = MachineText.parse("""{"title":"Am fost","kind":"visit","trade":"$trade"}""")
            assertEquals(kind, VisitKind.stored(earlier), trade)
        }
    }

    @Test
    fun belongingOffersThePartsTheBinderPlaysAndTheOneItSays() {
        val played = catalog.all.map { Behavior.of(it.behavior).role }
        assertEquals(listOf(Role.HOME, Role.VEHICLE, Role.HOLDER), CategorySwitches.belongingChoices(played))
        assertEquals(listOf(Role.HOME), CategorySwitches.belongingChoices(listOf(Role.HOME)))
        assertEquals(
            listOf(Role.HOME, Role.VEHICLE),
            CategorySwitches.belongingChoices(listOf(Role.HOME), current = Role.VEHICLE),
        )
    }

    @Test
    fun anOlderOneBoxBecomesTheGroupingOnlyWhereTheSwitchesWroteIt() {
        val tools = made(
            CategorySwitches.DEFAULTS,
        ).let { it.copy(behavior = it.behavior.copy(box = Box.WHOLE_CATEGORY)) }
        assertEquals(
            BoxTaken(Behavior.STANDARD, BoxGrouping.GROUPED),
            CategorySwitches.boxAsGrouping(tools, false, null),
        )
        val chosen = CategorySwitches.boxAsGrouping(tools, false, BoxGrouping.SEPARATE)
        assertEquals(BoxGrouping.SEPARATE, chosen?.grouping, "A grouping chosen already stays")

        val bills = made(
            CategorySwitches(hasBills = true, service = CategorySwitches.Service(CategorySwitches.Counter.TIME)),
        )
        val older = bills.copy(behavior = bills.behavior.copy(box = Box.WHOLE_CATEGORY))
        assertEquals(
            bills.behavior,
            CategorySwitches.boxAsGrouping(older, false, null)?.behavior,
            "Its part and visits stay",
        )

        val likeWarranties = tools.copy(behavior = tools.behavior.copy(listing = Listing.BY_WARRANTY))
        assertNull(
            CategorySwitches.boxAsGrouping(likeWarranties, false, null),
            "One that behaves like Garanții keeps its box",
        )
        assertNull(CategorySwitches.boxAsGrouping(tools, true, null), "A built-in keeps the catalog's box")
        assertNull(CategorySwitches.boxAsGrouping(made(CategorySwitches.DEFAULTS), false, null), "Twice is once")
    }

    @Test
    fun aBehaviourIsWrittenOverWhatWasStoredOnlyWhereItChanged() {
        val stored = CategoryBehavior(box = "carousel", role = "boat", visit = JsonPrimitive("overhaul"))
        val read = Behavior.of(stored)
        assertEquals(Box.PER_SECTION, read.box)
        assertNull(read.role)
        assertEquals(stored, read.writing(stored), "Read as it is, written as it was")
        val belonging = read.copy(mayBelongTo = Role.HOME, goesUnderTheOnlyOne = true).writing(stored)
        assertEquals(stored.copy(mayBelongTo = "home", goesUnderTheOnlyOne = true), belonging)
        val whole: JsonElement = CategoryBehavior.codec.encode(Behavior(mayBelongTo = Role.HOME).stored)
        assertEquals(
            MachineText.parse(
                """{"addedOnlyUnderParent":false,"box":"perSection","goesUnderTheOnlyOne":false,"listing":"plain",""" +
                    """"mayBelongTo":"home","visit":"none"}""",
            ),
            whole,
            "With nothing stored before, written whole, as the iOS encoder writes it",
        )
    }

    @Test
    fun aSectionIsNamedAfterWhatTheCatalogSaysOrAfterItsCategory() {
        val cars = builtIn(BuiltInTemplates.Key.VEHICLE)
        assertEquals("Mașina", Behavior.sectionName(cars.name, Behavior.of(cars.behavior)))
        assertEquals("Barca", Behavior.sectionName("  Barca ", made(CategorySwitches.DEFAULTS).behavior))
        assertNull(
            made(CategorySwitches.DEFAULTS).behavior.singular,
            "A category of one's own says nothing in a gender",
        )
    }
}
