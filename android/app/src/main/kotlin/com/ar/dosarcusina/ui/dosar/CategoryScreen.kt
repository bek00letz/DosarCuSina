package com.ar.dosarcusina.ui.dosar

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder

/**
 * A box that groups a category's sections (Acte, Garanții), by its key.
 * Placeholder: the Dosar tab's agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun CategoryScreen(templateKey: String) {
    ScreenPlaceholder(Word.app("Dosar"), DSSymbol.BINDER)
}
