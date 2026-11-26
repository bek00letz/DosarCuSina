package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import com.ar.dosarcusina.core.values.RomanianNumber
import com.ar.dosarcusina.core.wording.Word
import java.math.BigDecimal

/**
 * A card on the screen's background, as the iPhone app's `DSCard`: the surface colour, continuous
 * corners and a hairline outline. Anything nested inside takes a concentric radius
 * ([DSShapes.concentric] with [DSRadius.card] and [padding]).
 */
@Composable
fun DSCard(modifier: Modifier = Modifier, padding: Dp = DSSpace.m, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(DS.colors.surface, DSShapes.card)
            .dsHairlineBorder(DSShapes.card)
            .padding(padding),
        content = content,
    )
}

/** A section's header above a card: its title, a heading for TalkBack, and an optional count. */
@Composable
fun DSSectionHeader(title: String, modifier: Modifier = Modifier, count: Int? = null) {
    Row(
        modifier = modifier.fillMaxWidth().padding(horizontal = DSSpace.xxs),
        horizontalArrangement = Arrangement.spacedBy(DSSpace.xs),
        verticalAlignment = Alignment.Bottom,
    ) {
        DSText(title, DSTextStyle.SECTION_TITLE, Modifier.weight(1f).semantics { heading() })
        count?.let { DSText(countText(it), DSTextStyle.SUBHEADLINE, numeric = true) }
    }
}

/** A hairline between rows inside a card. */
@Composable
fun DSRowSeparator(modifier: Modifier = Modifier) {
    DSHairline(modifier.padding(vertical = DSSpace.xxs))
}

/** The "Vezi tot" row at the bottom of a pocket: a whole row with a chevron and an optional count. */
@Composable
fun DSSeeAllRow(modifier: Modifier = Modifier, count: Int? = null, title: String = Word.app("Vezi tot").written()) {
    val colors = DS.colors
    Row(
        modifier = modifier.fillMaxWidth().heightIn(min = DSControl.minimumHitTarget),
        horizontalArrangement = Arrangement.spacedBy(DSSpace.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DSText(title, DSTextStyle.BODY, Modifier.weight(1f), color = colors.accent, fontWeight = FontWeight.SemiBold)
        count?.let { DSText(countText(it), DSTextStyle.SUBHEADLINE, numeric = true) }
        DSIcon(DSSymbol.CHEVRON, colors.tertiaryLabel, size = DSIconSize.small)
    }
}

/** A count written the app's way („1.250”), whatever the phone's region. */
internal fun countText(count: Int): String =
    RomanianNumber.format(BigDecimal.valueOf(count.toLong()), 0, 0, groupsDigits = true)
