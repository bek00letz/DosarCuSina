package com.ar.dosarcusina.ui.search

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder

/** The Caută tab's first screen: search the binder. Placeholder: the Caută tab's agent replaces it in place. */
@Composable
fun SearchScreen() {
    ScreenPlaceholder(Word.app("Caută"), DSSymbol.SEARCH)
}
