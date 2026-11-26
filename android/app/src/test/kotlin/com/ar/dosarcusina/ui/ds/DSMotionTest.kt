package com.ar.dosarcusina.ui.ds

import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.TweenSpec
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.math.PI
import kotlin.math.sqrt

/** Motion: springs, short, and a short fade with the phone's "remove animations" on. */
class DSMotionTest {
    @Test
    fun `every motion is a spring between 0,2 and 0,4 seconds, as on the iPhone`() {
        DSMotion.entries.forEach { motion ->
            val spec = motion.spec<Float>(reduceMotion = false)
            assertTrue(spec is SpringSpec<*>, "$motion is a spring")
            // A spring's perceived duration is one period of its undamped motion: 2π / √stiffness.
            val seconds = 2 * PI / sqrt(motion.stiffness.toDouble())
            assertTrue(seconds in 0.2..0.4, "$motion lasts $seconds s")
            assertTrue(motion.dampingRatio in 0.8f..1f, "$motion barely bounces")
        }
    }

    @Test
    fun `the springs are the iPhone app's, carried over by duration and bounce`() {
        assertSpring(DSMotion.QUICK, duration = 0.22, bounce = 0.0)
        assertSpring(DSMotion.STANDARD, duration = 0.32, bounce = 0.08)
        assertSpring(DSMotion.EMPHASIZED, duration = 0.4, bounce = 0.18)
    }

    @Test
    fun `with remove animations on, every motion is the same short fade`() {
        val fade = TweenSpec<Float>(DSMotion.REDUCED_FADE_MILLIS, easing = LinearOutSlowInEasing)
        DSMotion.entries.forEach { motion -> assertEquals(fade, motion.spec<Float>(reduceMotion = true), "$motion") }
        assertTrue(DSMotion.REDUCED_FADE_MILLIS in 150..250)
    }

    @Test
    fun `with remove animations on, things arrive and leave by fading, never travelling`() {
        val fade = DSMotion.reducedFade<Float>()
        DSEdge.entries.forEach { edge ->
            assertEquals(fadeIn(fade), DSMotion.STANDARD.enter(edge, reduceMotion = true))
            assertEquals(fadeOut(fade), DSMotion.STANDARD.exit(edge, reduceMotion = true))
            assertNotEquals(fadeIn(fade), DSMotion.STANDARD.enter(edge, reduceMotion = false), "it travels otherwise")
        }
    }

    @Test
    fun `a pushed screen cross-fades with remove animations on`() {
        val fade = DSMotion.reducedFade<Float>()
        listOf(true, false).forEach { back ->
            val transform = DSMotion.STANDARD.navigation(back, reduceMotion = true)
            assertEquals(fadeIn(fade), transform.targetContentEnter)
            assertEquals(fadeOut(fade), transform.initialContentExit)
        }
    }

    @Test
    fun `progress waits before it shows`() {
        assertEquals(400L, DSMotion.PROGRESS_DELAY_MILLIS)
    }

    @Test
    fun `slides start a whole piece away, from the edge they come from`() {
        assertEquals(-120, DSEdge.TOP.offset(120))
        assertEquals(120, DSEdge.BOTTOM.offset(120))
    }

    private fun assertSpring(motion: DSMotion, duration: Double, bounce: Double) {
        val stiffness = (2 * PI / duration).let { it * it }
        assertEquals(stiffness, motion.stiffness.toDouble(), stiffness * 0.01, "$motion's stiffness")
        assertEquals(1 - bounce, motion.dampingRatio.toDouble(), 0.005, "$motion's damping")
    }
}
