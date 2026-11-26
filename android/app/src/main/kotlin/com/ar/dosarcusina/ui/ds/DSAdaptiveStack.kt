package com.ar.dosarcusina.ui.ds

import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection

/**
 * Side by side when every piece fits on one line at its natural width, one under the other
 * otherwise, as the iPhone app's `DSAdaptiveStack`: the one layout for a row that has to give way
 * to large text or a narrow screen (a label and its value, a value and its buttons). It decides by
 * measuring, never by the font size, so short content stays on one line even at the largest
 * sizes and long content moves down at any size; nothing is cut off or pushed past the edge.
 *
 * Side by side, the first piece takes the room the others leave; stacked, each is offered the
 * whole width and lines up by [stackedAlignment].
 */
@Composable
fun DSAdaptiveStack(
    modifier: Modifier = Modifier,
    spacing: Dp = DSSpace.s,
    stackedSpacing: Dp = spacing,
    stackedAlignment: Alignment.Horizontal = Alignment.Start,
    content: @Composable () -> Unit,
) {
    Layout(content = content, modifier = modifier) { measurables, constraints ->
        val gap = spacing.roundToPx()
        val stackedGap = stackedSpacing.roundToPx()
        val naturals = measurables.map { it.maxIntrinsicWidth(constraints.maxHeight) }
        val available = if (constraints.hasBoundedWidth) constraints.maxWidth else null
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        if (AdaptiveArrangement.fitsSideBySide(naturals, gap, available)) {
            val placeables = measureRow(measurables, naturals, gap, loose)
            val size = AdaptiveArrangement.rowSize(placeables.map { IntSize(it.width, it.height) }, gap, available)
            layout(size.width, size.height) {
                var x = 0
                placeables.forEach { piece ->
                    piece.placeRelative(x, (size.height - piece.height) / 2)
                    x += piece.width + gap
                }
            }
        } else {
            val placeables = measurables.map { it.measure(loose) }
            val width = available ?: (placeables.maxOfOrNull { it.width } ?: 0)
            val height = placeables.sumOf { it.height } + stackedGap * (placeables.size - 1).coerceAtLeast(0)
            layout(width, height) {
                var y = 0
                placeables.forEach { piece ->
                    piece.placeRelative(stackedAlignment.align(piece.width, width, LayoutDirection.Ltr), y)
                    y += piece.height + stackedGap
                }
            }
        }
    }
}

/** Side by side: the pieces after the first at their natural width, the first in what is left. */
private fun measureRow(
    measurables: List<Measurable>,
    naturals: List<Int>,
    gap: Int,
    constraints: Constraints,
): List<Placeable> {
    if (measurables.isEmpty()) return emptyList()
    val others = measurables.drop(1).mapIndexed { index, piece ->
        piece.measure(constraints.copy(maxWidth = naturals[index + 1]))
    }
    val firstWidth = if (constraints.hasBoundedWidth) {
        (constraints.maxWidth - others.sumOf { it.width } - gap * others.size).coerceAtLeast(0)
    } else {
        naturals.first()
    }
    return listOf(measurables.first().measure(constraints.copy(maxWidth = firstWidth))) + others
}

/** The decisions behind [DSAdaptiveStack], apart from Compose so they are tested. */
object AdaptiveArrangement {
    /** Whether pieces of [naturalWidths], [gap] apart, fit side by side in [available] (unbounded: always). */
    fun fitsSideBySide(naturalWidths: List<Int>, gap: Int, available: Int?): Boolean {
        if (available == null) return true
        val row = naturalWidths.sum() + gap * (naturalWidths.size - 1).coerceAtLeast(0)
        return row <= available
    }

    /** A row's size: the width offered (or what its pieces take) and its tallest piece. */
    fun rowSize(pieces: List<IntSize>, gap: Int, available: Int?): IntSize {
        val taken = pieces.sumOf { it.width } + gap * (pieces.size - 1).coerceAtLeast(0)
        return IntSize(available ?: taken, pieces.maxOfOrNull { it.height } ?: 0)
    }
}
