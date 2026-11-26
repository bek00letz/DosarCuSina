package com.ar.dosarcusina.ui.settings

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder
import com.ar.dosarcusina.ui.shell.SettingsSection

/**
 * Setări, reached from Dosar, as the shell's sheet, open at [initialSection]'s page or its first.
 * Placeholder: the Settings agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun SettingsScreen(initialSection: SettingsSection?) {
    ScreenPlaceholder(Word.app("Setări"), DSSymbol.SETTINGS)
}
