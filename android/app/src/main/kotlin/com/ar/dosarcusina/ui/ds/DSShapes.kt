package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection

/**
 * A rectangle with continuous corners (a squircle's curve), as the iPhone app's
 * `.rect(cornerRadius:style: .continuous)`: the curve starts further along each edge and bends
 * gradually, so a corner never shows where the straight edge stops. A corner asked larger than
 * the shape allows becomes a capsule's half circle.
 */
class DSContinuousShape(private val radius: Dp) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val asked = with(density) { radius.toPx() }
        val shortest = minOf(size.width, size.height)
        if (asked * CURVE_REACH >= shortest / 2) {
            return RoundedCornerShape(percent = HALF).createOutline(size, layoutDirection, density)
        }
        return Outline.Generic(ContinuousCorners.path(size, asked))
    }

    override fun equals(other: Any?): Boolean = other is DSContinuousShape && other.radius == radius

    override fun hashCode(): Int = radius.hashCode()

    override fun toString(): String = "DSContinuousShape($radius)"

    private companion object {
        const val HALF = 50
    }
}

/** How far along each edge a continuous corner of radius 1 reaches. */
internal const val CURVE_REACH = 1.52866483f

/** The path of a continuous corner, worked out for each corner from the top right, clockwise. */
internal object ContinuousCorners {
    private const val C1 = 1.08849323f
    private const val C2 = 0.86840689f
    private const val JOINT_ALONG = 0.63149399f
    private const val JOINT_ACROSS = 0.07491100f
    private const val MID_ALONG = 0.37282392f
    private const val MID_ACROSS = 0.16905899f

    fun path(size: Size, radius: Float): Path = Path().apply {
        val w = size.width
        val h = size.height
        val r = radius
        moveTo(CURVE_REACH * r, 0f)
        lineTo(w - CURVE_REACH * r, 0f)
        corner(r) { along, across -> (w - along) to across }
        lineTo(w, h - CURVE_REACH * r)
        corner(r) { along, across -> (w - across) to (h - along) }
        lineTo(CURVE_REACH * r, h)
        corner(r) { along, across -> along to (h - across) }
        lineTo(0f, CURVE_REACH * r)
        corner(r) { along, across -> across to along }
        close()
    }

    /**
     * One corner, in its own frame: `along` is the distance from the corner along the edge it
     * leaves, `across` from that edge; [place] turns them into the shape's coordinates.
     */
    private inline fun Path.corner(r: Float, place: (Float, Float) -> Pair<Float, Float>) {
        curve(place(C1 * r, 0f), place(C2 * r, 0f), place(JOINT_ALONG * r, JOINT_ACROSS * r))
        curve(
            place(MID_ALONG * r, MID_ACROSS * r),
            place(MID_ACROSS * r, MID_ALONG * r),
            place(JOINT_ACROSS * r, JOINT_ALONG * r),
        )
        curve(place(0f, C2 * r), place(0f, C1 * r), place(0f, CURVE_REACH * r))
    }

    private fun Path.curve(a: Pair<Float, Float>, b: Pair<Float, Float>, end: Pair<Float, Float>) {
        cubicTo(a.first, a.second, b.first, b.second, end.first, end.second)
    }
}

/** The design system's shapes, one per radius, so every surface of a kind has the same corners. */
object DSShapes {
    val card: Shape = DSContinuousShape(DSRadius.card)
    val control: Shape = DSContinuousShape(DSRadius.control)
    val fullWidthButton: Shape = DSContinuousShape(DSRadius.fullWidthButton)
    val notice: Shape = DSContinuousShape(DSRadius.notice)
    val badge: Shape = DSContinuousShape(DSRadius.badge)
    val floatingBar: Shape = DSContinuousShape(DSRadius.floatingBar)

    /** A shape nested [padding] inside one of [outer] radius: concentric with it ([DSRadius.concentric]). */
    fun concentric(outer: Dp, padding: Dp): Shape = DSContinuousShape(DSRadius.concentric(outer, padding))
}
