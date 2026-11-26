package com.ar.dosarcusina.ui.ds.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.ar.dosarcusina.core.urgency.AttentionUrgency
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DS
import com.ar.dosarcusina.ui.ds.DSAdaptiveStack
import com.ar.dosarcusina.ui.ds.DSButtonRole
import com.ar.dosarcusina.ui.ds.DSCard
import com.ar.dosarcusina.ui.ds.DSCompactButton
import com.ar.dosarcusina.ui.ds.DSDueBadge
import com.ar.dosarcusina.ui.ds.DSExpiryBadge
import com.ar.dosarcusina.ui.ds.DSLinkButton
import com.ar.dosarcusina.ui.ds.DSListRow
import com.ar.dosarcusina.ui.ds.DSPrimaryButton
import com.ar.dosarcusina.ui.ds.DSRadius
import com.ar.dosarcusina.ui.ds.DSReplacedBadge
import com.ar.dosarcusina.ui.ds.DSRowSeparator
import com.ar.dosarcusina.ui.ds.DSRowValue
import com.ar.dosarcusina.ui.ds.DSSecondaryButton
import com.ar.dosarcusina.ui.ds.DSSectionHeader
import com.ar.dosarcusina.ui.ds.DSSeeAllRow
import com.ar.dosarcusina.ui.ds.DSShapes
import com.ar.dosarcusina.ui.ds.DSSpace
import com.ar.dosarcusina.ui.ds.DSStatus
import com.ar.dosarcusina.ui.ds.DSStatusBadge
import com.ar.dosarcusina.ui.ds.DSStatusDot
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.ds.DSText
import com.ar.dosarcusina.ui.ds.DSTextStyle

/** The gallery's entries, one per component, in the order a screen is built from them. */
object GalleryEntries {
    /** Every entry: tokens and type first, then the components. */
    val all: List<GalleryEntry>
        get() = foundations + GalleryComponents.all

    /** A day the samples count from, so the gallery reads the same every day. */
    val today: CalendarDay = CalendarDay(2026, 11, 26)

    private val foundations: List<GalleryEntry> = listOf(
        GalleryEntry("DSSpace, DSRadius, DSShapes") { Tokens() },
        GalleryEntry("DSTextStyle") { TypeScale() },
        GalleryEntry("DSPrimaryButton, DSSecondaryButton") { FullWidthButtons() },
        GalleryEntry("DSCompactButton, DSLinkButton") { SmallButtons() },
        GalleryEntry("DSListRow, DSIconWell, DSRowValue") { Rows() },
        GalleryEntry("DSCard, DSSectionHeader, DSRowSeparator, DSSeeAllRow") { Cards() },
        GalleryEntry("DSStatusBadge, DSDueBadge, DSExpiryBadge, DSStatusDot") { Badges() },
        GalleryEntry("DSAdaptiveStack") { Adaptive() },
    )
}

@Composable
private fun Tokens() {
    val colors = DS.colors
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.xs)) {
        Row(horizontalArrangement = Arrangement.spacedBy(DSSpace.xs)) {
            listOf(DSSpace.xxs, DSSpace.xs, DSSpace.s, DSSpace.m, DSSpace.l, DSSpace.xl, DSSpace.xxl).forEach {
                Box(Modifier.size(it).background(colors.accent, DSShapes.badge))
            }
        }
        // A card with a well inside it: the well's corners concentric with the card's.
        Box(Modifier.background(colors.surface, DSShapes.card).padding(DSSpace.m)) {
            Box(Modifier.size(DSSpace.xxl * 2).background(colors.fill, DSShapes.concentric(DSRadius.card, DSSpace.m)))
        }
    }
}

@Composable
private fun TypeScale() {
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.xxs)) {
        DSTextStyle.entries.forEach { style -> DSText(style.name, style) }
        DSText(GallerySamples.ODOMETER, DSTextStyle.BODY, numeric = true)
    }
}

@Composable
private fun FullWidthButtons() {
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.s)) {
        DSPrimaryButton(Word.app("Salvează").written(), onClick = {})
        DSSecondaryButton(Word.app("Renunță").written(), onClick = {})
        DSSecondaryButton(
            Word.app("Șterge").written(),
            onClick = {},
            symbol = DSSymbol.TRASH,
            role = DSButtonRole.DESTRUCTIVE,
        )
        DSPrimaryButton(Word.app("Salvează").written(), onClick = {}, enabled = false)
    }
}

@Composable
private fun SmallButtons() {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(DSSpace.s)) {
        DSCompactButton(Word.app("Adaugă").written(), onClick = {}, symbol = DSSymbol.ADD)
        DSLinkButton(Word.app("Vezi tot").written(), onClick = {})
    }
}

@Composable
private fun Rows() {
    DSCard {
        DSListRow(GallerySamples.CAR, subtitle = GallerySamples.PLATE, symbol = DSSymbol.FOLDER, showsChevron = true)
        DSRowSeparator()
        DSListRow(GallerySamples.LONG_TITLE, trailing = { DSRowValue(GallerySamples.ODOMETER) })
        DSRowSeparator()
        DSListRow(GallerySamples.PERSON, symbol = DSSymbol.PEOPLE, trailing = { DSStatusBadge(DSStatus.DONE) })
    }
}

@Composable
private fun Cards() {
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.xs)) {
        DSSectionHeader(GallerySamples.SECTION, count = 3)
        DSCard {
            DSListRow(GallerySamples.HOME)
            DSRowSeparator()
            DSSeeAllRow(count = 1250)
        }
    }
}

@Composable
private fun Badges() {
    val today = GalleryEntries.today
    val gap = Arrangement.spacedBy(DSSpace.xs)
    FlowRow(horizontalArrangement = gap, verticalArrangement = gap) {
        DSStatus.entries.forEach { DSStatusBadge(it) }
        DSDueBadge(AttentionUrgency.OVERDUE, daysRemaining = -3, today = today)
        DSDueBadge(AttentionUrgency.TODAY, daysRemaining = 0, today = today)
        DSDueBadge(AttentionUrgency.SOON, daysRemaining = 5, today = today)
        DSExpiryBadge(AttentionUrgency.LATER, daysRemaining = 400, today = today)
        DSExpiryBadge(AttentionUrgency.SOON, daysRemaining = 20, today = today)
        DSReplacedBadge()
        DSStatus.entries.forEach { DSStatusDot(it) }
    }
}

@Composable
private fun Adaptive() {
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.s)) {
        DSAdaptiveStack {
            DSText(GallerySamples.CAR, DSTextStyle.BODY)
            DSCompactButton(Word.app("Adaugă").written(), onClick = {})
        }
        DSAdaptiveStack {
            DSText(GallerySamples.NOTE, DSTextStyle.BODY)
            DSCompactButton(Word.app("Adaugă").written(), onClick = {})
        }
    }
}
