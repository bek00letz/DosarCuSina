package com.ar.dosarcusina.ui.ds

import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.shell.DSDialog
import com.ar.dosarcusina.ui.shell.LocalScreenSheet

/**
 * Protects an editing sheet from losing work, as the iPhone app's `dsDiscardGuard`: while
 * [hasChanges], a swipe down, back or a tap outside doesn't close the sheet; the person is asked
 * whether to drop their changes, and a route from outside waits for them. Put it once inside the
 * sheet's content, with a [DSCancelButton] in its top bar, which asks the same. [message] says what
 * closing loses and what stays, when that is more than the changes.
 */
@Composable
fun DSDiscardGuard(hasChanges: Boolean, message: String? = null) {
    val sheet = LocalScreenSheet.current ?: return
    val haptics = LocalHapticFeedback.current
    var isAsking by remember { mutableStateOf(false) }
    LaunchedEffect(hasChanges) { sheet.holdsWork(hasChanges) }
    LaunchedEffect(isAsking) { if (isAsking) haptics.performHapticFeedback(HapticFeedbackType.Reject) }
    DisposableEffect(sheet) {
        sheet.askToDiscard = { isAsking = true }
        onDispose { sheet.askToDiscard = null }
    }
    DSDialog(
        visible = isAsking,
        title = Word.app("Renunți la modificări?").written(),
        message = message ?: Word.app("Ce ai completat până acum nu se va salva.").written(),
        confirmTitle = Word.app("Renunță la modificări").written(),
        role = DSButtonRole.DESTRUCTIVE,
        dismissTitle = Word.app("Continuă editarea").written(),
        onConfirm = {
            isAsking = false
            sheet.holdsWork(false)
            sheet.close()
        },
        onDismissRequest = { isAsking = false },
    )
}

/**
 * The cancel button of an editing sheet, „Renunță” („Anulează” is only the undo toast's), as the
 * iPhone app's `DSCancelButton`: it closes at once when nothing changed, otherwise the sheet's
 * [DSDiscardGuard] asks first. [title] when closing keeps something for later („Mai târziu”).
 */
@Composable
fun DSCancelButton(modifier: Modifier = Modifier, title: String = Word.app("Renunță").written()) {
    val sheet = LocalScreenSheet.current
    TextButton(onClick = { sheet?.attemptClose() }, modifier = modifier) {
        DSText(title, DSTextStyle.BODY, color = DS.colors.accent)
    }
}
