package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Text in one of the design system's styles, as the iPhone app's `dsFont`: the style's size and
 * tracking, its colour (secondary styles in the secondary label colour) unless [color] says
 * otherwise, and [numeric] for tabular digits where digits line up. It wraps by default, so large
 * text is never cut off; a [maxLines] limit ends in an ellipsis.
 */
@Composable
fun DSText(
    text: String,
    style: DSTextStyle,
    modifier: Modifier = Modifier,
    color: Color? = null,
    numeric: Boolean = false,
    fontWeight: FontWeight? = null,
    textAlign: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) {
    val colors = DS.colors
    val drawn = style.style(MaterialTheme.typography, numeric)
    Text(
        text = text,
        modifier = modifier,
        style = if (fontWeight != null) drawn.copy(fontWeight = fontWeight) else drawn,
        color = color ?: if (style.isSecondary) colors.secondaryLabel else colors.label,
        textAlign = textAlign,
        maxLines = maxLines,
        overflow = if (maxLines == Int.MAX_VALUE) TextOverflow.Clip else TextOverflow.Ellipsis,
    )
}

/**
 * A symbol, decorative by default (the words beside it say what it means), sized [size] at the
 * standard text size and growing with the font scale up to [DSControl.LARGEST_DECORATION_SCALE].
 */
@Composable
fun DSIcon(symbol: DSSymbol, tint: Color, modifier: Modifier = Modifier, size: Dp = DSIconSize.standard) {
    Image(
        imageVector = symbol.vector,
        contentDescription = null,
        modifier = modifier.size(decorationSize(size)),
        colorFilter = ColorFilter.tint(tint),
    )
}

/** [size] scaled with the phone's font size, up to [DSControl.LARGEST_DECORATION_SCALE]. */
@Composable
fun decorationSize(size: Dp): Dp {
    val scale = LocalDensity.current.fontScale.coerceIn(1f, DSControl.LARGEST_DECORATION_SCALE)
    return size * scale
}

/** The sizes a symbol is drawn at. */
object DSIconSize {
    val small: Dp = 16.dp
    val standard: Dp = 20.dp
    val large: Dp = 28.dp
    val hero: Dp = 48.dp
}
