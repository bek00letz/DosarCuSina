package com.ar.dosarcusina.ui.upcoming

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder

/** The Urmează tab's first screen: what comes up next. Placeholder: the Urmează tab's agent replaces it in place. */
@Composable
fun UpcomingRoot() {
    ScreenPlaceholder(Word.app("Urmează"), DSSymbol.SOON)
}
