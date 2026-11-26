package com.ar.dosarcusina.ui.dosar

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder
import java.util.UUID

/** A person's or a firm's page in Agendă. Placeholder: the Dosar tab's agent replaces it in place. */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun ProviderScreen(providerId: UUID) {
    ScreenPlaceholder(Word.app("Agendă"), DSSymbol.PEOPLE)
}
