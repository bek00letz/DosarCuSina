package com.ar.dosarcusina.ui.upcoming

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder
import java.util.UUID

/**
 * A deadline's page, with „Editează” and „Am rezolvat”. It draws its own locked state
 * (`RouteLock.DrawnByItsScreen`) and declares its sheets' lock with `ScreenLock`.
 * Placeholder: the Urmează tab's agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun ObligationScreen(obligationId: UUID) {
    ScreenPlaceholder(Word.app("Termen"), DSSymbol.CALENDAR)
}
