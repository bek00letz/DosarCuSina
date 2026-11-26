package com.ar.dosarcusina.ui.ds

import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.IntOffset

/**
 * Motion, as the iPhone app's `DS.Motion` (ios/Shared/DSMotion.swift): every movement is a spring,
 * short (0.2 to 0.4 s) and interruptible, velocity kept. With the phone's "remove animations" on
 * (`LocalReduceMotion`), movement becomes a short fade instead of travel or scale. The one place an
 * animation's spec is made: screens ask for a kind of motion, never a curve (the `DosarMotion`
 * detekt rule).
 *
 * Each spring is the iPhone's, carried over by its perceived duration and bounce: stiffness
 * (2π / duration)², damping ratio 1 − bounce.
 */
enum class DSMotion(val dampingRatio: Float, val stiffness: Float) {
    /** Presses, toggles, small state flips (0.22 s, no bounce). */
    QUICK(dampingRatio = 1f, stiffness = 816f),

    /** The default for content changes: rows appearing, sections expanding (0.32 s, a little bounce). */
    STANDARD(dampingRatio = 0.92f, stiffness = 385f),

    /** Things that arrive from off-screen: toasts, banners (0.4 s). */
    EMPHASIZED(dampingRatio = 0.82f, stiffness = 247f),
    ;

    /** The spec for a value animated with this motion, or the short fade when [reduceMotion]. */
    fun <T> spec(reduceMotion: Boolean): FiniteAnimationSpec<T> =
        if (reduceMotion) reducedFade() else spring(dampingRatio = dampingRatio, stiffness = stiffness)

    /** Arrives from [edge], sliding and fading in; a plain fade when [reduceMotion]. */
    fun enter(edge: DSEdge, reduceMotion: Boolean): EnterTransition {
        if (reduceMotion) return fadeIn(reducedFade())
        val slide = slideInVertically(spring<IntOffset>(dampingRatio, stiffness)) { height -> edge.offset(height) }
        return slide + fadeIn(spec(reduceMotion = false))
    }

    /** Leaves towards [edge], sliding and fading out; a plain fade when [reduceMotion]. */
    fun exit(edge: DSEdge, reduceMotion: Boolean): ExitTransition {
        if (reduceMotion) return fadeOut(reducedFade())
        val slide = slideOutVertically(spring<IntOffset>(dampingRatio, stiffness)) { height -> edge.offset(height) }
        return slide + fadeOut(spec(reduceMotion = false))
    }

    /**
     * A screen pushed on a tab: it slides in from the end while the one under it moves a little
     * aside and fades; a cross-fade with "remove animations". [back] for going back.
     */
    fun navigation(back: Boolean, reduceMotion: Boolean): ContentTransform {
        if (reduceMotion) return fadeIn(reducedFade()) togetherWith fadeOut(reducedFade())
        val slide = spring<IntOffset>(dampingRatio, stiffness)
        val fade = spec<Float>(reduceMotion = false)
        return if (back) {
            slideInHorizontally(slide) { -it / UNDER_SHIFT } + fadeIn(fade) togetherWith
                slideOutHorizontally(slide) { it } + fadeOut(fade)
        } else {
            slideInHorizontally(slide) { it } + fadeIn(fade) togetherWith
                slideOutHorizontally(slide) { -it / UNDER_SHIFT } + fadeOut(fade)
        }
    }

    companion object {
        /** How far the screen under a pushed one moves aside: a quarter of its width. */
        private const val UNDER_SHIFT = 4

        /** The fade used instead of movement with "remove animations" on. */
        const val REDUCED_FADE_MILLIS: Int = 180

        /** How long work may take before a progress indicator shows (`DSDelayedProgress`). */
        const val PROGRESS_DELAY_MILLIS: Long = 400

        /** The fade, for a value of any kind. */
        fun <T> reducedFade(): FiniteAnimationSpec<T> = tween(REDUCED_FADE_MILLIS, easing = LinearOutSlowInEasing)
    }
}

/** Where something slides from or to. */
enum class DSEdge {
    TOP,
    BOTTOM,
    ;

    /** How far off its place it starts, for a piece [height] tall. */
    fun offset(height: Int): Int = if (this == TOP) -height else height
}

/**
 * Whether the phone asks for no animations ("remove animations", Android's Reduce Motion), set by
 * [DosarTheme] from the system's setting. Every animation of the design system reads it.
 */
val LocalReduceMotion = staticCompositionLocalOf { false }
