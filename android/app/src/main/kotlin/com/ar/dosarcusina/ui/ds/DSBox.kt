package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.wording.Word

/**
 * A big box on the Dosar grid, as the iPhone app's `DSBox`: a photo or the category's symbol, the
 * name in large type and one status line ([DSStatusLine]). The whole box is the target; TalkBack
 * reads its name, then its line, its lock and whether it is an example.
 */
@Composable
fun DSBox(
    title: String,
    symbol: DSSymbol,
    tint: Color,
    statusText: String,
    tone: DSBoxTone,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    photo: ImageBitmap? = null,
    isExample: Boolean = false,
    isLocked: Boolean = false,
) {
    val colors = DS.colors
    val interaction = remember { MutableInteractionSource() }
    val spoken = listOfNotNull(
        title,
        statusText,
        Word.app("Protejat cu Face ID").written().takeIf { isLocked },
        Word.app("Date de exemplu").written().takeIf { isExample },
    ).joinToString(", ")
    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = DSControl.boxMinHeight)
            .clip(DSShapes.card)
            .background(colors.surface)
            .dsHairlineBorder(DSShapes.card)
            .clickable(interactionSource = interaction, indication = ripple(), onClick = onClick)
            .dsPressable(interaction)
            .clearAndSetSemantics {
                contentDescription = spoken
                role = Role.Button
            }
            .padding(DSSpace.m),
        verticalArrangement = Arrangement.spacedBy(DSSpace.s),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            BoxArtwork(symbol, tint, photo)
            Spacer(Modifier.weight(1f))
            when {
                isLocked -> DSIcon(DSSymbol.LOCK, colors.secondaryLabel, size = DSIconSize.small)
                isExample -> DSExampleBadge()
            }
        }
        DSText(title, DSTextStyle.SECTION_TITLE, fontWeight = FontWeight.Bold, maxLines = BOX_TITLE_LINES)
        DSStatusLine(statusText, tone)
    }
}

/** A box's artwork: the section's photo, or its category's symbol on a soft tint, with concentric corners. */
@Composable
private fun BoxArtwork(symbol: DSSymbol, tint: Color, photo: ImageBitmap?) {
    val side = decorationSize(ARTWORK)
    val shape = DSShapes.concentric(DSRadius.card, DSSpace.m)
    if (photo != null) {
        Image(photo, null, Modifier.size(side).clip(shape), contentScale = ContentScale.Crop)
    } else {
        val well = Modifier.size(side).background(tint.copy(alpha = DSTint.FILL), shape)
        Box(well, contentAlignment = Alignment.Center) { DSIcon(symbol, tint, size = DSIconSize.large) }
    }
}

/**
 * The last box on the grid, as the iPhone app's `DSAddBox`: a dashed outline that adds a new
 * section, naming under its title what it can add that has no box yet ([detail], written by the
 * caller; null for none).
 */
@Composable
fun DSAddBox(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, detail: String? = null) {
    val colors = DS.colors
    val outline = colors.accent.copy(alpha = DSTint.ADD_OUTLINE)
    val density = LocalDensity.current
    val dash = with(density) { DASH.toPx() }
    val stroke = Stroke(
        width = with(density) { ADD_STROKE.toPx() },
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(dash, dash * DASH_GAP)),
    )
    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = DSControl.boxMinHeight)
            .clip(DSShapes.card)
            .drawBehind {
                drawOutline(DSShapes.card.createOutline(size, layoutDirection, this), outline, style = stroke)
            }
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) { role = Role.Button }
            .padding(DSSpace.m),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DSSpace.s, Alignment.CenterVertically),
    ) {
        DSIcon(DSSymbol.ADD, colors.accent, size = DSIconSize.large)
        DSText(title, DSTextStyle.HEADLINE, color = colors.accent, textAlign = TextAlign.Center)
        detail?.let { DSText(it, DSTextStyle.FOOTNOTE, textAlign = TextAlign.Center, maxLines = BOX_TITLE_LINES) }
    }
}

/** „Exemplu” on every example record, as the iPhone app's `DSExampleBadge`. */
@Composable
fun DSExampleBadge(modifier: Modifier = Modifier) {
    val colors = DS.colors
    DSText(
        Word.app("Exemplu").written(),
        DSTextStyle.CAPTION_EMPHASIZED,
        modifier
            .border(hairlineWidth(), colors.separator, DSShapes.badge)
            .background(colors.fill, DSShapes.badge)
            .padding(horizontal = DSSpace.xs, vertical = DSSpace.xxs / 2),
    )
}

private const val BOX_TITLE_LINES = 3
private const val DASH_GAP = 5f / 7f
private val ARTWORK = 52.dp
private val DASH = 7.dp
private val ADD_STROKE = 1.5.dp
