package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MonthDay
import com.ar.dosarcusina.core.values.RecurrenceInterval
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.util.UUID

/**
 * One box for a category's sections, or one each: what is offered, what the catalog says, and the
 * person's order kept around it. The pure parts of the iOS app's `BoxGroupingTests`, and the first
 * due day of a deadline with fixed dates (`RecurrenceEngine`).
 */
class BoxGroupingTest {
    @Test
    fun groupingIsOfferedFromTwoSectionsAndTheWayBackAlways() {
        val cars = Behavior(visit = VisitKind.SERVICE)
        assertNull(BoxGrouping.offer(cars, BoxGrouping.SEPARATE, 1), "One car has nothing to group")
        assertEquals(BoxGrouping.GROUPED, BoxGrouping.offer(cars, BoxGrouping.SEPARATE, 2))
        assertEquals(BoxGrouping.SEPARATE, BoxGrouping.offer(cars, BoxGrouping.GROUPED, 1))
        assertEquals(BoxGrouping.SEPARATE, BoxGrouping.offer(cars, BoxGrouping.GROUPED, 5))
        assertNull(
            BoxGrouping.offer(Behavior(box = Box.WHOLE_CATEGORY), BoxGrouping.SEPARATE, 5),
            "Acte has one box already",
        )
        assertNull(BoxGrouping.offer(Behavior(box = Box.INSIDE_OTHER), BoxGrouping.SEPARATE, 5), "Tenants have none")
    }

    @Test
    fun theCatalogSaysWhereEachStartsAndThePersonsChoiceWins() {
        fun behavior(key: String) = Behavior.of(requireNotNull(Catalog.builtIn.definition(key)).behavior)
        assertEquals(
            BoxGrouping.SEPARATE,
            BoxGrouping.of(behavior(BuiltInTemplates.Key.VEHICLE), null),
            "A box for each car",
        )
        assertEquals(BoxGrouping.GROUPED, BoxGrouping.of(behavior(BuiltInTemplates.Key.PLANTS), null), "One Plante box")
        assertEquals(BoxGrouping.GROUPED, BoxGrouping.of(behavior(BuiltInTemplates.Key.VEHICLE), "grouped"))
        assertEquals(BoxGrouping.SEPARATE, BoxGrouping.of(behavior(BuiltInTemplates.Key.PLANTS), "separate"))
        val newer = BoxGrouping.of(behavior(BuiltInTemplates.Key.VEHICLE), "byColour")
        assertEquals(BoxGrouping.SEPARATE, newer, "A newer choice reads as the catalog's")
        assertEquals(
            BoxGrouping.SEPARATE,
            BoxGrouping.of(behavior(BuiltInTemplates.Key.DOCUMENTS), "grouped"),
            "Acte keeps its one box",
        )

        val plants = behavior(BuiltInTemplates.Key.PLANTS)
        assertEquals(Box.PER_SECTION, plants.box)
        assertEquals(Role.HOME, plants.mayBelongTo)
        assertEquals(SectionPocket.PLANTS, plants.parentPocket)
        assertEquals(true, plants.goesUnderTheOnlyOne)
        assertEquals(false, plants.hasPocketOfItsOwn)
    }

    @Test
    fun theOneBoxStandsWhereTheFirstOfItsSectionsStoodAndGivesThemBack() {
        val car1 = BinderBoxID.Section(UUID.fromString("00000000-0000-4000-8000-0000000000c1"))
        val car2 = BinderBoxID.Section(UUID.fromString("00000000-0000-4000-8000-0000000000c2"))
        val flat = BinderBoxID.Section(UUID.fromString("00000000-0000-4000-8000-0000000000f1"))
        val saved = listOf(flat, BinderBoxID.Agenda, car2, BinderBoxID.Category("documents"), car1)
        val grouped = BinderLayout.regrouped(saved, "vehicle", listOf(car1, car2), grouped = true)
        assertEquals(
            listOf(flat, BinderBoxID.Agenda, BinderBoxID.Category("vehicle"), BinderBoxID.Category("documents")),
            grouped,
        )
        val split = BinderLayout.regrouped(grouped, "vehicle", listOf(car1, car2), grouped = false)
        assertEquals(listOf(flat, BinderBoxID.Agenda, car1, car2, BinderBoxID.Category("documents")), split)
        assertEquals(
            listOf(BinderBoxID.Agenda),
            BinderLayout.regrouped(listOf(BinderBoxID.Agenda), "vehicle", listOf(car1), true),
        )
    }

    @Test
    fun aBoxIsWrittenInTheSavedOrderAsTheIPhoneWritesIt() {
        val id = UUID.fromString("0B6C6F43-0000-4000-8000-0000000000AA")
        assertEquals("asset:0b6c6f43-0000-4000-8000-0000000000aa", BinderBoxID.Section(id).storageKey)
        for (box in listOf(BinderBoxID.Section(id), BinderBoxID.Category("plants"), BinderBoxID.Agenda)) {
            assertEquals(box, BinderBoxID.of(box.storageKey))
        }
        assertEquals(BinderBoxID.Section(id), BinderBoxID.of("asset:0B6C6F43-0000-4000-8000-0000000000AA"))
        assertNull(BinderBoxID.of("category:"))
        assertNull(BinderBoxID.of("asset:nu"))
        assertNull(BinderBoxID.of("shelf"))
    }

    @Test
    fun aFixedDateIsTheNextOnOrAfterTheDay() {
        val may = listOf(MonthDay(5, 25))
        assertEquals(CalendarDay(2027, 5, 25), RecurrenceEngine.nextFixedDate(CalendarDay(2026, 11, 2), may))
        assertEquals(
            CalendarDay(2027, 5, 25),
            RecurrenceEngine.nextFixedDate(CalendarDay(2027, 5, 25), may),
            "The day itself",
        )
        assertEquals(CalendarDay(2028, 5, 25), RecurrenceEngine.nextFixedDateAfter(CalendarDay(2027, 5, 25), may))
        assertEquals(
            CalendarDay(2027, 5, 25),
            RecurrenceEngine.firstDue(
                Catalog.builtIn.household.rentalDeclaration,
                FieldValues(),
                CalendarDay(2026, 11, 2),
            ),
        )
        assertEquals(
            CalendarDay(2028, 2, 29),
            RecurrenceEngine.add(RecurrenceInterval.years(1), CalendarDay(2027, 2, 28), dayOfMonth = 29),
        )
    }
}
