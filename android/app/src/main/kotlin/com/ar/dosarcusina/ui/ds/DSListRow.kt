package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.semantics

/**
 * A standard row, as the iPhone app's `DSListRow`: an optional icon well, a title, an optional
 * subtitle and a trailing value or control, at least 48 dp tall at every font size. When the
 * trailing piece doesn't fit beside the title it moves under it instead of squeezing it
 * ([DSAdaptiveStack]). Make it tappable with the modifier (`clickable`); it reads as one element
 * to TalkBack either way.
 */
@Composable
fun DSListRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    symbol: DSSymbol? = null,
    tint: Color? = null,
    showsChevron: Boolean = false,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = DS.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = DSControl.minimumHitTarget)
            .semantics(mergeDescendants = true) {}
            .padding(vertical = DSSpace.xs),
        horizontalArrangement = Arrangement.spacedBy(DSSpace.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when {
            leading != null -> leading()
            symbol != null -> DSIconWell(symbol, tint ?: colors.accent)
        }
        DSAdaptiveStack(modifier = Modifier.weight(1f), spacing = DSSpace.s, stackedSpacing = DSSpace.xxs) {
            Column(verticalArrangement = Arrangement.spacedBy(TITLE_GAP)) {
                DSText(title, DSTextStyle.HEADLINE)
                subtitle?.let { DSText(it, DSTextStyle.SUBHEADLINE) }
            }
            trailing?.invoke()
        }
        if (showsChevron) DSIcon(DSSymbol.CHEVRON, colors.tertiaryLabel, size = DSIconSize.small)
    }
}

/** A trailing value for [DSListRow], with tabular digits ("84.200 km"). */
@Composable
fun DSRowValue(text: String, modifier: Modifier = Modifier) {
    DSText(text, DSTextStyle.SUBHEADLINE, modifier, numeric = true)
}

/** A symbol on a soft tint of its colour, in a well with continuous corners: a row's leading symbol. */
@Composable
fun DSIconWell(symbol: DSSymbol, tint: Color, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(decorationSize(DSControl.iconWell))
            .background(tint.copy(alpha = DSTint.FILL), DSShapes.control),
        contentAlignment = Alignment.Center,
    ) { DSIcon(symbol, tint) }
}

private val TITLE_GAP = DSSpace.xxs / 2
