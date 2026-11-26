package com.ar.dosarcusina.ui.ds.gallery

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DS
import com.ar.dosarcusina.ui.ds.DSAddBox
import com.ar.dosarcusina.ui.ds.DSBox
import com.ar.dosarcusina.ui.ds.DSBoxTone
import com.ar.dosarcusina.ui.ds.DSButtonRole
import com.ar.dosarcusina.ui.ds.DSCheckRow
import com.ar.dosarcusina.ui.ds.DSChoiceField
import com.ar.dosarcusina.ui.ds.DSDelayedProgress
import com.ar.dosarcusina.ui.ds.DSEmptyState
import com.ar.dosarcusina.ui.ds.DSErrorState
import com.ar.dosarcusina.ui.ds.DSLockedState
import com.ar.dosarcusina.ui.ds.DSMoreAction
import com.ar.dosarcusina.ui.ds.DSMoreActionsToolbar
import com.ar.dosarcusina.ui.ds.DSNotice
import com.ar.dosarcusina.ui.ds.DSNoticeKind
import com.ar.dosarcusina.ui.ds.DSPinnedActionScaffold
import com.ar.dosarcusina.ui.ds.DSPrimaryButton
import com.ar.dosarcusina.ui.ds.DSRevealsValidation
import com.ar.dosarcusina.ui.ds.DSSecondaryButton
import com.ar.dosarcusina.ui.ds.DSSecretField
import com.ar.dosarcusina.ui.ds.DSSpace
import com.ar.dosarcusina.ui.ds.DSStatusLine
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.ds.DSText
import com.ar.dosarcusina.ui.ds.DSTextField
import com.ar.dosarcusina.ui.ds.DSTextStyle
import com.ar.dosarcusina.ui.ds.DSToast
import com.ar.dosarcusina.ui.ds.DSToastCenter
import com.ar.dosarcusina.ui.ds.DSToastHost
import com.ar.dosarcusina.ui.ds.DSUndo
import com.ar.dosarcusina.ui.ds.DSValidation
import com.ar.dosarcusina.ui.ds.DSValidationReveal

/** The gallery's entries for the components built from the foundations. */
internal object GalleryComponents {
    val all: List<GalleryEntry> = listOf(
        GalleryEntry("DSEmptyState, DSErrorState") { States() },
        GalleryEntry("DSLockedState") { Locked() },
        GalleryEntry("DSNotice") { Notices() },
        GalleryEntry("DSDelayedProgress") { DSDelayedProgress() },
        GalleryEntry("DSToast, DSToastHost") { Toasts() },
        GalleryEntry("DSCheckRow") { Checks() },
        GalleryEntry("DSTextField, DSSecretField, DSRevealsValidation") { Fields() },
        GalleryEntry("DSChoiceField") { Choices() },
        GalleryEntry("DSBox, DSAddBox, DSStatusLine") { Boxes() },
        GalleryEntry("DSMoreActionsToolbar") { MoreActions() },
        GalleryEntry("DSPinnedActionScaffold") { Pinned() },
    )
}

@Composable
private fun States() {
    Column {
        DSEmptyState(
            title = Word.app("Agendă").written(),
            message = GallerySamples.NOTE,
            symbol = DSSymbol.PEOPLE,
            actionTitle = Word.app("Adaugă").written(),
            onAction = {},
        )
        DSErrorState(title = Word.app("Nu a mers").written(), message = GallerySamples.NOTE, onRetry = {})
    }
}

@Composable
private fun Locked() {
    DSLockedState(
        title = Word.app("„%@” e protejat", Word.text(GallerySamples.CAR)).written(),
        message = Word.app("Protejat cu Face ID").written(),
        unlockTitle = Word.app("Deblochează").written(),
        onUnlock = {},
    )
}

@Composable
private fun Notices() {
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.s)) {
        DSNoticeKind.entries.forEach { kind ->
            DSNotice(
                kind,
                GallerySamples.STATUS_LINE,
                message = GallerySamples.NOTE,
                actionTitle = Word.app("Vezi tot").written(),
                onAction = {},
            )
        }
    }
}

@Composable
private fun Toasts() {
    val center = remember { DSToastCenter() }
    val undo = remember { GalleryUndo() }
    Box(Modifier.heightIn(min = TOAST_ROOM)) {
        DSSecondaryButton(Word.app("Arată").written(), onClick = {
            center.show(DSToast.undo(Word.app("Vizita e în istoric.").written(), undo))
        })
        DSToastHost(center)
    }
}

/** An undo for the gallery's toast: it can always be taken back, and takes nothing. */
private class GalleryUndo : DSUndo {
    override val canUndo: Boolean = true

    override fun undo() = Unit
}

@Composable
private fun Checks() {
    var isOn by remember { mutableStateOf(true) }
    var isOff by remember { mutableStateOf(false) }
    Column {
        DSCheckRow(GallerySamples.CAR, isOn, { isOn = it }, subtitle = GallerySamples.PLATE) {
            DSText(GallerySamples.NOTE, DSTextStyle.FOOTNOTE)
        }
        DSCheckRow(GallerySamples.LONG_TITLE, isOff, { isOff = it }, isRadio = true)
    }
}

@Composable
private fun Fields() {
    var name by remember { mutableStateOf(GallerySamples.CAR) }
    var key by remember { mutableStateOf(GallerySamples.KEY) }
    var reveal by remember { mutableStateOf(DSValidationReveal()) }
    DSRevealsValidation(reveal) {
        Column(verticalArrangement = Arrangement.spacedBy(DSSpace.s)) {
            DSTextField(Word.app("Nume").written(), name, { name = it }, footnote = GallerySamples.NOTE)
            DSTextField(Word.app("Notă").written(), "", {}, validation = DSValidation.requiredMissing)
            DSSecretField(Word.app("Cheia ta").written(), key, { key = it })
            DSPrimaryButton(Word.app("Salvează").written(), onClick = { reveal = reveal.revealed() })
        }
    }
}

@Composable
private fun Choices() {
    var colour by remember { mutableStateOf<String?>(GallerySamples.colours.first()) }
    var country by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.s)) {
        DSChoiceField(Word.app("Notă").written(), GallerySamples.colours, { it }, colour, { colour = it })
        DSChoiceField(
            Word.app("Țara").written(),
            GallerySamples.countries,
            { it },
            country,
            { country = it },
            allowsNone = true,
        )
    }
}

@Composable
private fun Boxes() {
    val colors = DS.colors
    Column(verticalArrangement = Arrangement.spacedBy(DSSpace.s)) {
        Row(horizontalArrangement = Arrangement.spacedBy(DSSpace.s)) {
            val each = Modifier.weight(1f)
            val line = GallerySamples.STATUS_LINE
            DSBox(GallerySamples.CAR, DSSymbol.FOLDER, colors.accent, line, DSBoxTone.PENDING, {}, each)
            DSBox(
                GallerySamples.HOME, DSSymbol.FOLDER, colors.status.done, GallerySamples.ALL_GOOD,
                DSBoxTone.ALL_GOOD, {}, each,
                isLocked = true,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(DSSpace.s)) {
            val each = Modifier.weight(1f)
            DSBox(
                GallerySamples.LONG_TITLE, DSSymbol.DOCUMENT, colors.status.soon, GallerySamples.STATUS_LINE,
                DSBoxTone.ALARMING, {}, each,
                isExample = true,
            )
            DSAddBox(Word.app("Adaugă o secțiune").written(), {}, each, detail = GallerySamples.ADD_DETAIL)
        }
        DSStatusLine(GallerySamples.FIRM, DSBoxTone.NEUTRAL)
    }
}

@Composable
private fun MoreActions() {
    Row(horizontalArrangement = Arrangement.spacedBy(DSSpace.m)) {
        DSMoreActionsToolbar(listOf(DSMoreAction("move", Word.app("Mută la…").written(), DSSymbol.FOLDER) {}))
        DSMoreActionsToolbar(
            listOf(
                DSMoreAction("move", Word.app("Mută la…").written(), DSSymbol.FOLDER) {},
                DSMoreAction("delete", Word.app("Șterge").written(), DSSymbol.TRASH, DSButtonRole.DESTRUCTIVE) {},
            ),
        )
    }
}

@Composable
private fun Pinned() {
    Box(Modifier.heightIn(min = PINNED_ROOM, max = PINNED_ROOM)) {
        DSPinnedActionScaffold(
            action = { DSPrimaryButton(Word.app("Salvează").written(), onClick = {}) },
            note = { DSText(GallerySamples.NOTE, DSTextStyle.FOOTNOTE) },
            secondary = { DSSecondaryButton(Word.app("Renunță").written(), onClick = {}) },
        ) { padding ->
            DSText(GallerySamples.LONG_TITLE, DSTextStyle.BODY, Modifier.padding(padding))
        }
    }
}

private val TOAST_ROOM = 160.dp
private val PINNED_ROOM = 360.dp
