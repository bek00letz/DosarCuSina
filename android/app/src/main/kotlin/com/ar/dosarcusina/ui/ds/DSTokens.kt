package com.ar.dosarcusina.ui.ds

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Spacing on a 4 dp grid, as the iPhone app's `DS.Space` (ios/Shared/DSLayout.swift). Use the
 * named steps; never a raw number.
 */
object DSSpace {
    /** 4 dp: between an icon and its label, inside dense rows. */
    val xxs: Dp = 4.dp

    /** 8 dp: between related lines of text, chip gaps. */
    val xs: Dp = 8.dp

    /** 12 dp: between rows inside a card. */
    val s: Dp = 12.dp

    /** 16 dp: card padding and the screen's side margin. */
    val m: Dp = 16.dp

    /** 20 dp: between a section header and the card under it. */
    val l: Dp = 20.dp

    /** 24 dp: between sections. */
    val xl: Dp = 24.dp

    /** 32 dp: around empty and error states. */
    val xxl: Dp = 32.dp

    /** Every step, smallest first: the grid the tokens test checks. */
    val steps: List<Dp> = listOf(xxs, xs, s, m, l, xl, xxl)
}

/**
 * Sizes for things people tap, as the iPhone app's `DS.Control`, at Android's own measure: the
 * smallest target is 48 dp (Material's and the accessibility scanner's), not iOS's 44 pt.
 */
object DSControl {
    /** The smallest tap target. A borderless button's label is its whole target. */
    val minimumHitTarget: Dp = 48.dp

    /** The height of a full-width button: its label with room above and below. */
    val fullWidthButton: Dp = 52.dp

    /** The smallest height of a bar that floats over the content (the toast): its button with a little room. */
    val floatingBar: Dp = minimumHitTarget + DSSpace.xxs * 2

    /** The side of a row's icon well (`DSIconWell`) at the standard text size. */
    val iconWell: Dp = 36.dp

    /** The smallest height of a box on the binder's grid. */
    val boxMinHeight: Dp = 168.dp

    /**
     * The largest font scale a symbol beside words grows to (an icon well, a box's artwork): it
     * follows the text up to here and stops, so the words beside it keep the row's width at the
     * largest sizes, as `DS.Control.largestDecorationSize` does on the iPhone.
     */
    const val LARGEST_DECORATION_SCALE: Float = 1.3f

    /** From this font scale on, the binder's grid shows one box a row (iOS's accessibility sizes). */
    const val ACCESSIBILITY_FONT_SCALE: Float = 1.5f
}

/**
 * Corner radii, as the iPhone app's `DS.Radius`. Compose's rounded corners are circular arcs;
 * the shapes the design system draws use [DSShapes], which keep the same radii everywhere.
 */
object DSRadius {
    /** Top-level cards, boxes and sheets' content blocks. */
    val card: Dp = 22.dp

    /** Text fields, tiles inside cards, icon wells on rows. */
    val control: Dp = 12.dp

    /** Full-width buttons: a little rounder than a field. */
    val fullWidthButton: Dp = 14.dp

    /** An inline notice. */
    val notice: Dp = 16.dp

    /** Small badges that are not capsules. */
    val badge: Dp = 8.dp

    /** A bar that floats over the content (the toast): half its smallest height, a capsule on one line. */
    val floatingBar: Dp = DSControl.floatingBar / 2

    /** The smallest radius [concentric] gives. */
    val concentricMinimum: Dp = 4.dp

    /**
     * The radius a child needs to stay concentric with its container: inner = outer − padding,
     * never below [minimum]. The one way a nested corner is worked out.
     */
    fun concentric(outer: Dp, padding: Dp, minimum: Dp = concentricMinimum): Dp =
        maxOf(outer - padding, minimum)
}

/** How wide a screen's content grows on a tablet or a wide window, as `DS.ReadableWidth`. */
enum class DSReadableWidth(val width: Dp) {
    /** Text, forms and a section's or a deadline's page. */
    TEXT(672.dp),

    /** A grid of boxes (the binder): wider, for more columns, still never edge to edge. */
    GRID(1024.dp),
}
