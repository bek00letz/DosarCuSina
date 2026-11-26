package com.ar.dosarcusina.ui.dosar

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.AddSectionRequest
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder
import java.util.UUID

/**
 * „Adaugă o secțiune”, from anywhere, a shaped screen (`AddSectionForm`). [onAdded] gets the new
 * section's id and whether it stands on its own (no parent), so the shell can open it.
 * Placeholder: the Dosar tab's agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun AddSectionFlow(request: AddSectionRequest, onAdded: (assetId: UUID, isTopLevel: Boolean) -> Unit) {
    ScreenPlaceholder(Word.app("Adaugă o secțiune"), DSSymbol.ADD)
}
