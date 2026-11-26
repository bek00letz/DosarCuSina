package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp

/** One physical pixel, for separators and outlines. */
@Composable
fun hairlineWidth(): Dp = with(LocalDensity.current) { 1f.toDp() }

/** A hairline across the width, a separator between rows and above a pinned bar (`DS.Hairline`). */
@Composable
fun DSHairline(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(hairlineWidth())
            .background(DS.colors.separator)
            .clearAndSetSemantics {},
    )
}

/** A one-pixel outline along [shape], separating a surface from its background (`dsHairlineBorder`). */
@Composable
fun Modifier.dsHairlineBorder(shape: Shape): Modifier = border(hairlineWidth(), DS.colors.separator, shape)

/**
 * A state that fills its screen (empty, error, locked), centred while it fits and scrolling when
 * the largest font sizes make it taller than the screen, so nothing is ever cut off.
 */
@Composable
fun DSCenteredScroll(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .heightIn(min = maxHeight)
                .dsReadableWidth(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) { content() }
    }
}

/**
 * The one readable-width rule for every screen, as the iPhone app's `dsReadableWidth`: the content
 * is centred and grows no wider than [width], scaled with the font size, so a tablet or a wide
 * window keeps lines that read well. Put it on a screen's scrolling content and the pinned bar.
 */
@Composable
fun Modifier.dsReadableWidth(width: DSReadableWidth = DSReadableWidth.TEXT): Modifier {
    val scale = LocalDensity.current.fontScale.coerceAtLeast(1f)
    return fillMaxWidth()
        .wrapContentWidth(Alignment.CenterHorizontally)
        .widthIn(max = width.width * scale)
        .fillMaxWidth()
}
