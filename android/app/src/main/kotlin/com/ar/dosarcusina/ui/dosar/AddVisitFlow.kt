package com.ar.dosarcusina.ui.dosar

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder
import java.util.UUID

/**
 * The visit form, a shaped screen (`VisitKind`, `VisitShape`).
 * Placeholder: the Dosar tab's agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun AddVisitFlow(assetId: UUID) {
    ScreenPlaceholder(Word.app("Vizită"))
}
