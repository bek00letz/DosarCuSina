package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.attention.BoxStatus
import com.ar.dosarcusina.core.urgency.UrgencyTone

/**
 * How a box's line reads at a glance, as the iPhone app's `DSBoxTone`: a symbol and a semantic
 * colour that always travel with the words, so colour is never the only signal.
 */
enum class DSBoxTone(val status: DSStatus?, val symbol: DSSymbol) {
    ALL_GOOD(DSStatus.DONE, DSSymbol.DONE),
    PENDING(DSStatus.SOON, DSSymbol.SOON),
    ALARMING(DSStatus.OVERDUE, DSSymbol.OVERDUE),

    /** Neutral facts such as „12 contacte”. */
    NEUTRAL(null, DSSymbol.PEOPLE),
    ;

    companion object {
        /** A box's tone from its status, by the urgency's tone: red only when late past its grace. */
        fun of(status: BoxStatus): DSBoxTone = when {
            status.entry == null -> ALL_GOOD
            status.urgencyTone == UrgencyTone.OVERDUE -> ALARMING
            else -> PENDING
        }
    }
}

/** The one status line under a box or a hero, as the iPhone app's `DSStatusLine`; digits tabular. */
@Composable
fun DSStatusLine(text: String, tone: DSBoxTone, modifier: Modifier = Modifier) {
    val colors = DS.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(DSSpace.xxs + 2.dp), verticalAlignment = Alignment.Top) {
        DSIcon(tone.symbol, tone.status?.let(colors.status::of) ?: colors.secondaryLabel, size = DSIconSize.small)
        DSText(
            text,
            DSTextStyle.SUBHEADLINE,
            color = tone.status?.let(colors.statusText::of) ?: colors.secondaryLabel,
            numeric = true,
            fontWeight = if (tone == DSBoxTone.ALARMING) FontWeight.SemiBold else null,
            maxLines = LINE_LIMIT,
        )
    }
}

/**
 * How the binder's boxes are laid out, by the room the grid has, as the iPhone app's
 * `DSBoxGrid.plan`: the one rule for every phone and window, never a model or a size of one. At
 * the largest font sizes one box a row; on a compact width (a phone, a narrow window) two, as tall
 * as their words; on a wider one (a tablet, a wide window) square boxes, three a row when the room
 * is taller than wide and four when it is wider.
 */
object DSBoxGrid {
    /** Where a compact width ends (Material's window size classes). */
    val compactWidthLimit: Dp = 600.dp

    data class Plan(val columns: Int, val squares: Boolean)

    fun plan(roomWidth: Dp, roomHeight: Dp, fontScale: Float): Plan = when {
        fontScale >= DSControl.ACCESSIBILITY_FONT_SCALE -> Plan(columns = 1, squares = false)
        roomWidth < compactWidthLimit -> Plan(columns = 2, squares = false)
        roomWidth > roomHeight -> Plan(columns = WIDE_COLUMNS, squares = true)
        else -> Plan(columns = TALL_COLUMNS, squares = true)
    }

    private const val WIDE_COLUMNS = 4
    private const val TALL_COLUMNS = 3
}

/**
 * At least as tall as it is wide when [isOn] ([DSBoxGrid.Plan.squares]): a square, or taller when
 * its content needs more (larger text), never cut.
 */
fun Modifier.dsAtLeastSquare(isOn: Boolean): Modifier = if (!isOn) this else layout { measurable, constraints ->
    val placeable = if (constraints.hasBoundedWidth) {
        val width = constraints.maxWidth
        measurable.measure(Constraints.fixed(width, maxOf(width, measurable.minIntrinsicHeight(width))))
    } else {
        measurable.measure(constraints)
    }
    layout(placeable.width, placeable.height) { placeable.placeRelative(0, 0) }
}

private const val LINE_LIMIT = 3
