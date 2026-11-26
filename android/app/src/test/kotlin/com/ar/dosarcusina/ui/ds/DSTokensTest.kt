package com.ar.dosarcusina.ui.ds

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.readiness.ReadinessStatus
import com.ar.dosarcusina.core.urgency.UrgencyTone
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The design system's tokens: the 4 dp grid, concentric corners, 48 dp targets, real dark mode, contrast. */
class DSTokensTest {
    @Test
    fun `spacing sits on the 4 dp grid, smallest first`() {
        DSSpace.steps.forEach { assertEquals(0f, it.value % 4, "$it is on the grid") }
        assertEquals(DSSpace.steps.sortedBy { it.value }, DSSpace.steps)
    }

    @Test
    fun `a nested corner is the outer radius less the padding, never below the minimum`() {
        assertEquals(6.dp, DSRadius.concentric(DSRadius.card, DSSpace.m))
        assertEquals(DSRadius.concentricMinimum, DSRadius.concentric(DSRadius.control, DSSpace.m))
        assertEquals(10.dp, DSRadius.concentric(DSRadius.card, DSSpace.s, minimum = 2.dp))
    }

    @Test
    fun `a floating bar of one line is a capsule`() {
        assertEquals(DSControl.floatingBar / 2, DSRadius.floatingBar)
    }

    @Test
    fun `every target is at least 48 dp`() {
        assertTrue(DSControl.minimumHitTarget >= 48.dp)
        assertTrue(DSControl.fullWidthButton >= DSControl.minimumHitTarget)
        assertTrue(DSControl.floatingBar >= DSControl.minimumHitTarget)
    }

    @Test
    fun `the dark theme is its own, never the light one inverted`() {
        val light = DSColors.Light
        val dark = DSColors.Dark
        assertTrue(dark.isDark && !light.isDark)
        assertTrue(dark.background.luminance() < light.background.luminance())
        // A dark surface sits a little above its background, as iOS's does: not the light surface inverted.
        assertTrue(dark.surface.luminance() > dark.background.luminance())
        assertTrue(light.surface.luminance() > light.background.luminance())
        assertEquals(light.status.later, dark.status.later, "a neutral grey reads on both")
    }

    @Test
    fun `one accent, the app's own, in every theme`() {
        assertEquals(Color(0xFF007AFF), DSColors.Light.accent)
        assertEquals(Color(0xFF0A84FF), DSColors.Dark.accent)
        assertEquals(DSColors.Light, DSColors.of(dark = false, highContrast = false))
        assertEquals(DSColors.DarkHighContrast, DSColors.of(dark = true, highContrast = true))
    }

    @Test
    fun `status words keep 4,5 to 1 on a card in every theme`() {
        listOf(DSColors.Light, DSColors.LightHighContrast, DSColors.Dark, DSColors.DarkHighContrast).forEach { colors ->
            DSStatus.entries.forEach { status ->
                val ratio = contrast(colors.statusText.of(status), colors.surface)
                assertTrue(ratio >= 4.5, "$status on ${if (colors.isDark) "dark" else "light"}: $ratio")
            }
            assertTrue(contrast(colors.label, colors.surface) >= 7.0)
            assertTrue(contrast(colors.accent.compositeOver(colors.surface), colors.surface) >= 3.0, "the accent reads")
        }
    }

    @Test
    fun `the design system draws a tone and never decides one`() {
        assertEquals(DSStatus.OVERDUE, DSStatus.of(UrgencyTone.OVERDUE))
        assertEquals(DSStatus.SOON, DSStatus.of(UrgencyTone.SOON))
        assertEquals(DSStatus.LATER, DSStatus.of(UrgencyTone.CALM))
        assertNull(DSStatus.urgent(UrgencyTone.CALM))
        assertEquals(DSStatus.OVERDUE, DSStatus.of(ReadinessStatus.PROBLEM))
        assertEquals(DSStatus.SOON, DSStatus.of(ReadinessStatus.WARNING))
        assertEquals(DSStatus.DONE, DSStatus.of(ReadinessStatus.OK))
        // An optional check, one ticked by hand and one not in the binder stay neutral.
        listOf(ReadinessStatus.SUGGESTED, ReadinessStatus.REMINDER, ReadinessStatus.MISSING)
            .forEach { assertNull(DSStatus.of(it), "$it") }
    }

    @Test
    fun `the type scale ends in tabular figures where digits line up`() {
        val typography = androidx.compose.material3.Typography()
        DSTextStyle.entries.forEach { style ->
            assertEquals(DSTextStyle.TABULAR_FIGURES, style.style(typography, numeric = true).fontFeatureSettings)
            assertTrue(style.style(typography).fontSize.isSp, "$style follows the font size")
        }
    }

    /** WCAG's contrast ratio between two opaque colours. */
    private fun contrast(a: Color, b: Color): Double {
        val (light, dark) = listOf(a.luminance(), b.luminance()).sortedDescending()
        return (light + 0.05) / (dark + 0.05)
    }
}
