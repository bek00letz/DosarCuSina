package com.ar.dosarcusina.ui.upcoming

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.readiness.ReadinessRoute
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder

/**
 * A situation's checklist: a trip, selling the car, a claim. It draws its own locked state.
 * Placeholder: the Urmează tab's agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun ReadinessScreen(route: ReadinessRoute) {
    ScreenPlaceholder(Word.app("Pleci din țară"), DSSymbol.DONE)
}
