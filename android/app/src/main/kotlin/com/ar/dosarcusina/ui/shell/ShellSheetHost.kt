package com.ar.dosarcusina.ui.shell

import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import com.ar.dosarcusina.ui.dosar.AddPersonalDocumentFlow
import com.ar.dosarcusina.ui.dosar.AddSectionFlow
import com.ar.dosarcusina.ui.dosar.AddVisitFlow
import com.ar.dosarcusina.ui.dosar.HolderDocumentFiling
import com.ar.dosarcusina.ui.settings.SettingsScreen
import com.ar.dosarcusina.ui.upcoming.OutsideCompletionSheet

/**
 * The shell's one sheet ([ShellSheets.shown]), over whatever tab shows: never stacked; the next
 * opens once the last's dismissal has completed. It is drawn behind the section it writes into
 * ([ShellSheet.lock]), however it was asked for (a link, a button).
 */
@Composable
internal fun ShellSheetHost(sheets: ShellSheets) {
    val last = remember { LastSheet() }
    sheets.shown?.let { last.sheet = it }
    val drawn = last.sheet ?: return
    key(drawn) {
        val handle = remember(sheets) { ScreenSheetHandle(ShellSheets.SHELL_SHEET_ID, sheets) }
        RoutedBottomSheet(
            visible = sheets.shown == drawn,
            handle = handle,
            onPersonCloses = { sheets.present(null) },
            onAppeared = { sheets.didAppear() },
            onDismissed = {
                if (last.sheet == drawn) last.sheet = null
                sheets.didDismiss()
            },
        ) {
            RouteLockGate(drawn.lock, inSheet = true, onClose = { sheets.present(null) }) { ShellSheetContent(drawn) }
        }
    }
}

/** The sheet drawn last, kept on screen while it closes. */
private class LastSheet {
    var sheet: ShellSheet? = null
}

@Composable
private fun ShellSheetContent(sheet: ShellSheet) {
    val router = LocalShellRouter.current
    when (sheet) {
        is ShellSheet.Settings -> SettingsScreen(initialSection = sheet.section)
        is ShellSheet.AddVisit -> AddVisitFlow(assetId = sheet.assetId)
        // Lands on the document's own page, over the person it was added for.
        is ShellSheet.AddPersonalDocument -> AddPersonalDocumentFlow(holderId = sheet.holderId) { documentId ->
            router.push(AppRoute.Asset(documentId))
        }
        // One of their own documents opens its page; a paper kept on theirs stays there.
        is ShellSheet.AddDocument -> AddPersonalDocumentFlow(
            holderId = sheet.holderId,
            filing = HolderDocumentFiling.CAPTURE_DECIDES,
        ) { documentId -> router.push(AppRoute.Asset(documentId)) }
        is ShellSheet.Completion -> OutsideCompletionSheet(obligationId = sheet.obligationId, cycle = sheet.cycle)
        // A new top-level section opens right away; a child shows up in its parent's pocket.
        is ShellSheet.AddSection -> AddSectionFlow(request = sheet.request) { assetId, isTopLevel ->
            if (sheet.request.parentId == null && isTopLevel) router.open(AppRoute.Asset(assetId))
        }
    }
}
