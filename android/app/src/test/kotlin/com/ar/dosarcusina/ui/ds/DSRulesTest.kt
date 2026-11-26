package com.ar.dosarcusina.ui.ds

import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.urgency.AttentionUrgency
import com.ar.dosarcusina.core.values.CalendarDay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The design system's own rules, apart from drawing: layouts that give way, the grid, the badges' words. */
class DSRulesTest {
    private val today = CalendarDay(2026, 11, 26)

    @Test
    fun `pieces sit side by side only while they fit at their natural width`() {
        assertTrue(AdaptiveArrangement.fitsSideBySide(listOf(100, 60), gap = 12, available = 172))
        assertFalse(AdaptiveArrangement.fitsSideBySide(listOf(100, 60), gap = 12, available = 171))
        assertTrue(AdaptiveArrangement.fitsSideBySide(listOf(500, 500), gap = 12, available = null))
        assertEquals(IntSize(300, 40), AdaptiveArrangement.rowSize(listOf(IntSize(100, 40), IntSize(60, 20)), 12, 300))
    }

    @Test
    fun `a toast's button stays beside its words while it takes no more than half the width`() {
        assertTrue(ToastArrangement.fitsBeside(buttonWidth = 100, width = 212, gap = 12))
        assertFalse(ToastArrangement.fitsBeside(buttonWidth = 101, width = 212, gap = 12))
        assertTrue(ToastArrangement.fitsBeside(buttonWidth = 0, width = 10, gap = 12), "no button, nothing moves")
    }

    @Test
    fun `the grid gives two boxes a row on a phone, square boxes on a tablet, one at the largest text`() {
        assertEquals(DSBoxGrid.Plan(2, squares = false), DSBoxGrid.plan(390.dp, 800.dp, fontScale = 1f))
        assertEquals(DSBoxGrid.Plan(3, squares = true), DSBoxGrid.plan(800.dp, 1200.dp, fontScale = 1f))
        assertEquals(DSBoxGrid.Plan(4, squares = true), DSBoxGrid.plan(1200.dp, 800.dp, fontScale = 1f))
        assertEquals(DSBoxGrid.Plan(1, squares = false), DSBoxGrid.plan(1200.dp, 800.dp, fontScale = 2f))
    }

    @Test
    fun `a page's extra actions: none, one as itself, two or more in a menu`() {
        assertEquals(DSMoreActionsLayout.NOTHING, DSMoreActionsLayout.of(0))
        assertEquals(DSMoreActionsLayout.DIRECT, DSMoreActionsLayout.of(1))
        assertEquals(DSMoreActionsLayout.MENU, DSMoreActionsLayout.of(2))
    }

    @Test
    fun `an expiry says Valabil until it needs the person, then how far it is`() {
        assertEquals("Valabil", DSDueText.expiry(AttentionUrgency.LATER, 400, today))
        assertEquals("Expiră azi", DSDueText.expiry(AttentionUrgency.TODAY, 0, today))
        assertEquals("Expiră mâine", DSDueText.expiry(AttentionUrgency.SOON, 1, today))
        assertEquals("Expiră în 5 zile", DSDueText.expiry(AttentionUrgency.SOON, 5, today))
        assertEquals("Expirat de 3 zile", DSDueText.expiry(AttentionUrgency.OVERDUE, -3, today))
        assertEquals("În 5 zile", DSDueText.due(AttentionUrgency.SOON, 5, today))
    }

    @Test
    fun `a field's problem shows once the person leaves it, or at once after a refused save`() {
        val problem = DSValidation.Invalid("Completează acest câmp.")
        assertEquals(DSValidation.Valid, DSValidationVisibility.shown(problem, hasLeftField = false, reveal = false))
        assertEquals(problem, DSValidationVisibility.shown(problem, hasLeftField = true, reveal = false))
        assertEquals(problem, DSValidationVisibility.shown(problem, hasLeftField = false, reveal = true))
    }

    @Test
    fun `every refused save is another attempt, so the form goes to its first problem each time`() {
        val first = DSValidationReveal().revealed()
        assertTrue(first.isOn)
        assertEquals(2, first.revealed().attempt)
        assertFalse(DSValidationReveal().isOn)
        assertEquals("Completează acest câmp.", DSValidation.requiredMissing.message)
    }
}
