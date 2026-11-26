package com.ar.dosarcusina.ui.dosar

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder

/** The Dosar tab's first screen: the grid of boxes. Placeholder: the Dosar tab's agent replaces it in place. */
@Composable
fun DosarHomeView() {
    ScreenPlaceholder(Word.app("Dosar"), DSSymbol.BINDER)
}
