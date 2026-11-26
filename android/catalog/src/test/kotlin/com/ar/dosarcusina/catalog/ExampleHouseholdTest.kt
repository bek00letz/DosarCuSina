package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.values.CalendarDay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The example household the build carries is the one the iOS app declares (shared/catalog/examples/,
 * written by `ExampleHouseholdExportTests`), read whole, and every step names what the steps before it
 * made: a category the catalog has, a section, a firm, a deadline its section's category has.
 */
class ExampleHouseholdTest {
    private val household = ExampleHousehold.builtIn

    @Test
    fun theStepsHoldTogether() {
        val sections = HashMap<String, String>()
        val firms = HashSet<String>()
        for (step in household.steps) {
            when (step) {
                is ExampleStep.Section -> {
                    assertNotNull(Catalog.builtIn.definition(step.category), step.ref)
                    step.parent?.let { assertTrue(it in sections, "${step.ref}'s parent comes first") }
                    assertNull(sections.put(step.ref, step.category), "${step.ref} is made once")
                }
                is ExampleStep.Firm -> {
                    assertTrue(sections.keys.containsAll(step.linkedTo), step.ref)
                    firms += step.ref
                }
                is ExampleStep.Record ->
                    assertTrue(step.section in sections && firms.containsAll(step.firms), step.title)
                is ExampleStep.PastCompletion -> {
                    val blueprints = Catalog.builtIn.definition(sections.getValue(step.section))?.blueprints.orEmpty()
                    assertTrue(blueprints.any { it.key == step.deadline }, step.deadline)
                }
                is ExampleStep.Reading -> assertTrue(step.section in sections, step.kind)
            }
        }
        assertEquals(12, sections.size, "The twelve sections the iOS household has")
    }

    @Test
    fun aDayIsCountedFromTheDayTheExamplesLoad() {
        val today = CalendarDay(2026, 11, 26)
        assertEquals(FieldValue.Day(CalendarDay(2027, 4, 25)), ExampleValue.DayFromToday(150).on(today))
        assertEquals(FieldValue.Text("B-123-ABC"), ExampleValue.Kept(FieldValue.Text("B-123-ABC")).on(today))
    }

    @Test
    fun aStepThisBuildDoesntMakeIsABrokenBuild() {
        assertThrows(CatalogError::class.java) { ExampleHousehold.read("""{"steps": [{"party": {}}]}""") }
        assertThrows(CatalogError::class.java) { ExampleHousehold.read("""{"steps": [{"section": {}, "firm": {}}]}""") }
    }
}
