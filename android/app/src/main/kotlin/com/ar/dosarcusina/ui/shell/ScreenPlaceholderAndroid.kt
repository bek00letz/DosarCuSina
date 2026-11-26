package com.ar.dosarcusina.ui.shell

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.ar.dosarcusina.app.R
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSCenteredScroll
import com.ar.dosarcusina.ui.ds.DSEmptyState
import com.ar.dosarcusina.ui.ds.DSSymbol

/**
 * What a screen shows until its tab's agent builds it: its name and the placeholder's one line
 * (Android's own words, app.xml), as the placeholder contract in AGENTS.md says. Each placeholder
 * keeps the agreed name and parameters, and is replaced in place.
 */
@Composable
fun ScreenPlaceholder(title: Word, symbol: DSSymbol = DSSymbol.FOLDER) {
    DSCenteredScroll {
        DSEmptyState(title = title.written(), message = stringResource(R.string.placeholder_line), symbol = symbol)
    }
}
