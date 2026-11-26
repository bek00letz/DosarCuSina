package com.ar.dosarcusina.ui.dosar

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder

/** Agendă: the people and firms. Placeholder: the Dosar tab's agent replaces it in place. */
@Composable
fun AgendaScreen() {
    ScreenPlaceholder(Word.app("Agendă"), DSSymbol.PEOPLE)
}
