package com.ar.dosarcusina.ui.upcoming

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder
import java.util.UUID

/**
 * „Am rezolvat” for one deadline at the cycle the person saw, asked from outside the app (a
 * reminder's button, a link): the shell's sheet over the deadline's page.
 * Placeholder: the Urmează tab's agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun OutsideCompletionSheet(obligationId: UUID, cycle: CalendarDay) {
    ScreenPlaceholder(Word.app("Am rezolvat"), DSSymbol.DONE)
}
