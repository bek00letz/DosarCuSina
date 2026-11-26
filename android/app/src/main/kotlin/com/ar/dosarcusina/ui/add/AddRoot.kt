package com.ar.dosarcusina.ui.add

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder

/**
 * The Adaugă tab's first screen: scan or add something, and De verificat.
 * Placeholder: the Adaugă tab's agent replaces it in place.
 */
@Composable
fun AddRoot() {
    ScreenPlaceholder(Word.app("Adaugă"), DSSymbol.ADD_CIRCLE)
}
