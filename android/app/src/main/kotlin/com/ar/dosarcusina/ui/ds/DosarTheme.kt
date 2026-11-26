package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

/**
 * The app's look: Android's own Material 3, held to the standing rule's checklist, with the app's
 * own accent and neutral surfaces (never the wallpaper's colours), a real dark theme, the phone's
 * higher contrast and its "remove animations" setting. Every screen, sheet and the gallery draw
 * inside it. [dark], [highContrast] and [reduceMotion] are the phone's unless a caller (the
 * gallery, a test) asks for one.
 */
@Composable
fun DosarTheme(
    dark: Boolean = isSystemInDarkTheme(),
    highContrast: Boolean = systemAsksForHighContrast(),
    reduceMotion: Boolean = systemRemovesAnimations(),
    content: @Composable () -> Unit,
) {
    val colors = DSColors.of(dark, highContrast)
    MaterialTheme(colorScheme = colors.materialScheme(), typography = Typography()) {
        CompositionLocalProvider(
            LocalDSColors provides colors,
            LocalReduceMotion provides reduceMotion,
            content = content,
        )
    }
}

/** Material's colour roles, filled from the app's own colours so Material's controls match the rest. */
internal fun DSColors.materialScheme(): ColorScheme {
    val base = if (isDark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = accent,
        onPrimary = onAccent,
        primaryContainer = accent.copy(alpha = DSTint.FILL),
        onPrimaryContainer = accent,
        secondaryContainer = accent.copy(alpha = DSTint.FILL),
        onSecondaryContainer = label,
        background = background,
        onBackground = label,
        surface = background,
        onSurface = label,
        surfaceVariant = fill,
        onSurfaceVariant = secondaryLabel,
        surfaceContainerLowest = surface,
        surfaceContainerLow = surface,
        surfaceContainer = surface,
        surfaceContainerHigh = surfaceRaised,
        surfaceContainerHighest = surfaceRaised,
        outline = separator,
        outlineVariant = separator,
        error = status.overdue,
        onError = onAccent,
    )
}

/** The design system's colours, inside [DosarTheme]. */
object DS {
    val colors: DSColors
        @Composable get() = LocalDSColors.current

    val reduceMotion: Boolean
        @Composable get() = LocalReduceMotion.current
}
