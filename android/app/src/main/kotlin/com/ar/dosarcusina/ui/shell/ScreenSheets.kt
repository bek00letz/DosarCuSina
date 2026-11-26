package com.ar.dosarcusina.ui.shell

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DS
import com.ar.dosarcusina.ui.ds.DSButtonRole
import com.ar.dosarcusina.ui.ds.DSText
import com.ar.dosarcusina.ui.ds.DSTextStyle
import java.util.UUID

// A screen's own sheets and dialogs, presented so the router knows they are up (ShellSheets,
// ShellSheetQueue): a route from a reminder, a widget or a link then never lands under one. It
// closes them, the top one first, each once the one above has finished closing, and lands when the
// last has gone; while one holds work the person hasn't saved (its form's dsDiscardGuard) or must
// be answered (waitsByItself), it waits for the person to close it. Every sheet and dialog goes
// through DSSheet or DSDialog (the DosarSheetOutsideRouter detekt rule); the shell's own sheet is
// ShellSheets.shown, drawn by AppShell. Each is drawn behind the lock of the screen that presents
// it (LocalScreenLock).

/** The router's sheets, provided by [AppShell]; null outside it (the gallery), where sheets aren't tracked. */
val LocalShellSheets = staticCompositionLocalOf<ShellSheets?> { null }

/**
 * What a sheet gives what it shows: its id with the router, so its form says when it holds unsaved
 * work ([com.ar.dosarcusina.ui.ds.dsDiscardGuard]), and how the form asks to close it.
 */
@Stable
class ScreenSheetHandle internal constructor(val id: String, private val sheets: ShellSheets?) {
    /** The guard's question, asked when the person tries to close the sheet with work in it. */
    internal var askToDiscard: (() -> Unit)? = null

    /** Closes the sheet without asking (the guard's „Renunță la modificări”, or nothing to lose). */
    internal var close: () -> Unit = {}

    /** The form holds work: closing by a swipe, back or a tap outside asks first. */
    internal var isGuarded: Boolean by mutableStateOf(false)
        private set

    /** The form holds (or no longer holds) unsaved work. */
    fun holdsWork(holds: Boolean) {
        isGuarded = holds
        sheets?.holdsWork(id, holds)
    }

    /** The person asks to close: it closes, or the guard asks first. */
    fun attemptClose() {
        val ask = askToDiscard
        if (isGuarded && ask != null) ask() else close()
    }
}

/** The sheet this content is shown in, when there is one; null outside a sheet. */
val LocalScreenSheet = staticCompositionLocalOf<ScreenSheetHandle?> { null }

/**
 * A sheet the router knows about, shown while [visible], as the iPhone app's `dsSheet`. The person
 * closes it by a swipe, back or a tap outside (which a discard guard holds back), or the screen by
 * setting [visible] false; [onDismissRequest] asks the screen to do that. [onDismissed] runs once
 * its dismissal has completed, however it closed. [keepsRoutesWaiting] for one that must be
 * answered before a route lands.
 */
@Composable
fun DSSheet(
    visible: Boolean,
    onDismissRequest: () -> Unit,
    onDismissed: () -> Unit = {},
    keepsRoutesWaiting: Boolean = false,
    content: @Composable () -> Unit,
) {
    val sheets = LocalShellSheets.current
    val lock = LocalScreenLock.current
    val id = remember { UUID.randomUUID().toString() }
    val handle = remember(sheets) { ScreenSheetHandle(id, sheets) }
    val close by rememberUpdatedState(onDismissRequest)
    RoutedBottomSheet(
        visible = visible,
        handle = handle,
        onPersonCloses = { close() },
        onAppeared = { sheets?.screenDidAppear(id, keepsRoutesWaiting) { close() } },
        onDismissed = {
            sheets?.screenDidDismiss(id)
            onDismissed()
        },
    ) {
        RouteLockGate(lock, inSheet = true, onClose = { close() }, content = content)
    }
}

/**
 * A question the router knows about, as the iPhone app's alerts and confirmation dialogs: a
 * title, an optional message, the button that does it ([confirmTitle], red for a [role] that takes
 * something away) and the one that leaves it („Renunță” unless [dismissTitle] says otherwise).
 */
@Composable
fun DSDialog(
    visible: Boolean,
    title: String,
    confirmTitle: String,
    onConfirm: () -> Unit,
    onDismissRequest: () -> Unit,
    message: String? = null,
    dismissTitle: String = Word.app("Renunță").written(),
    role: DSButtonRole = DSButtonRole.NORMAL,
) {
    if (!visible) return
    val sheets = LocalShellSheets.current
    val id = remember { UUID.randomUUID().toString() }
    val dismiss by rememberUpdatedState(onDismissRequest)
    DisposableEffect(sheets) {
        sheets?.screenDidAppear(id, waitsByItself = false) { dismiss() }
        onDispose { sheets?.screenDidDismiss(id) }
    }
    val colors = DS.colors
    AlertDialog(
        onDismissRequest = onDismissRequest,
        title = { DSText(title, DSTextStyle.HEADLINE) },
        text = message?.let { { DSText(it, DSTextStyle.BODY, color = colors.secondaryLabel) } },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                val ink = if (role == DSButtonRole.DESTRUCTIVE) colors.statusText.overdue else colors.accent
                DSText(confirmTitle, DSTextStyle.BODY, color = ink)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismissRequest) { DSText(dismissTitle, DSTextStyle.BODY, color = colors.accent) }
        },
        containerColor = colors.surface,
    )
}

/**
 * The one bottom sheet of the app, for the shell's sheet and a screen's own: it comes on screen
 * while [visible], tells [onAppeared] once it is up, and [onDismissed] once its dismissal has
 * completed, so the next waits for the event, never a guessed pause. While its form holds work
 * ([ScreenSheetHandle.isGuarded]) a swipe, back or a tap outside doesn't close it: the guard asks.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RoutedBottomSheet(
    visible: Boolean,
    handle: ScreenSheetHandle,
    onPersonCloses: () -> Unit,
    onAppeared: () -> Unit,
    onDismissed: () -> Unit,
    content: @Composable () -> Unit,
) {
    var onScreen by remember { mutableStateOf(false) }
    LaunchedEffect(visible) { if (visible) onScreen = true }
    if (!onScreen) return
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true) { target ->
        val heldBack = target == SheetValue.Hidden && handle.isGuarded
        if (heldBack) handle.attemptClose()
        !heldBack
    }
    LaunchedEffect(visible) {
        if (!visible) {
            state.hide()
            onScreen = false
            onDismissed()
        }
    }
    SideEffect { handle.close = onPersonCloses }
    ModalBottomSheet(onDismissRequest = onPersonCloses, sheetState = state, containerColor = DS.colors.background) {
        LaunchedEffect(Unit) { onAppeared() }
        CompositionLocalProvider(LocalScreenSheet provides handle, content = content)
    }
}
