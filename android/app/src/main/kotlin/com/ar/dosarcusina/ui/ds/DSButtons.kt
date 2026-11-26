package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign

// Full-width actions, as the iPhone app's DSPrimaryButton and DSSecondaryButton
// (ios/Shared/DSButtons.swift): the main action of a screen is filled, every other full-width
// action tonal, both with the same label, so stacked they line up. A destructive one says so in
// red. Their words wrap instead of being cut off at the largest font sizes.

/** What a button does, as far as its look goes. */
enum class DSButtonRole {
    NORMAL,

    /** Deletes or takes away: drawn in the overdue red. */
    DESTRUCTIVE,
}

/** The main action of a screen: full width, at least 52 dp tall. Pin it with [DSPinnedActionScaffold]. */
@Composable
fun DSPrimaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    symbol: DSSymbol? = null,
    role: DSButtonRole = DSButtonRole.NORMAL,
    enabled: Boolean = true,
) {
    val colors = DS.colors
    val fill = if (role == DSButtonRole.DESTRUCTIVE) colors.status.overdue else colors.accent
    Button(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().heightIn(min = DSControl.fullWidthButton),
        enabled = enabled,
        shape = DSShapes.fullWidthButton,
        colors = ButtonDefaults.buttonColors(containerColor = fill, contentColor = colors.onAccent),
        contentPadding = FullWidthPadding,
    ) { DSButtonLabel(title, symbol, colors.onAccent) }
}

/** Any other full-width action: quieter than [DSPrimaryButton], the same size and label. */
@Composable
fun DSSecondaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    symbol: DSSymbol? = null,
    role: DSButtonRole = DSButtonRole.NORMAL,
    enabled: Boolean = true,
) {
    val colors = DS.colors
    val ink = if (role == DSButtonRole.DESTRUCTIVE) colors.statusText.overdue else colors.accent
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().heightIn(min = DSControl.fullWidthButton),
        enabled = enabled,
        shape = DSShapes.fullWidthButton,
        colors = ButtonDefaults.filledTonalButtonColors(containerColor = colors.fill, contentColor = ink),
        contentPadding = FullWidthPadding,
    ) { DSButtonLabel(title, symbol, ink) }
}

/**
 * A small action beside a row ("Adaugă" next to a suggestion): tonal, one line wherever it fits,
 * wrapping only rather than running past the screen's edge, and still a 48 dp target.
 */
@Composable
fun DSCompactButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, symbol: DSSymbol? = null) {
    val colors = DS.colors
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = DSControl.minimumHitTarget),
        shape = DSShapes.control,
        colors = ButtonDefaults.filledTonalButtonColors(containerColor = colors.fill, contentColor = colors.accent),
        contentPadding = PaddingValues(horizontal = DSSpace.s, vertical = DSSpace.xxs),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(DSSpace.xxs), verticalAlignment = Alignment.CenterVertically) {
            symbol?.let { DSIcon(it, colors.accent, size = DSIconSize.small) }
            DSText(title, DSTextStyle.SUBHEADLINE, color = colors.accent, fontWeight = FontWeight.SemiBold)
        }
    }
}

/**
 * An action written as words inside content (under a notice, under a paper's photo): borderless,
 * in the accent colour, its whole 48 dp the target, never only the words.
 */
@Composable
fun DSLinkButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    role: DSButtonRole = DSButtonRole.NORMAL,
) {
    val colors = DS.colors
    val ink = if (role == DSButtonRole.DESTRUCTIVE) colors.statusText.overdue else colors.accent
    TextButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = DSControl.minimumHitTarget),
        contentPadding = PaddingValues(vertical = DSSpace.xxs),
    ) {
        DSText(title, DSTextStyle.SUBHEADLINE, color = ink, fontWeight = FontWeight.SemiBold)
    }
}

/** The label both full-width buttons share: an optional symbol and a title that wraps. */
@Composable
private fun RowScope.DSButtonLabel(title: String, symbol: DSSymbol?, ink: Color) {
    Row(
        modifier = Modifier.weight(1f, fill = false),
        horizontalArrangement = Arrangement.spacedBy(DSSpace.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        symbol?.let { DSIcon(it, ink) }
        DSText(title, DSTextStyle.HEADLINE, color = ink, textAlign = TextAlign.Center)
    }
}

private val FullWidthPadding = PaddingValues(horizontal = DSSpace.m, vertical = DSSpace.s)
