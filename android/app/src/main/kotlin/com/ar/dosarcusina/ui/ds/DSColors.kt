package com.ar.dosarcusina.ui.ds

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * The app's semantic colours, as the iPhone app's `DS.Palette` and status colours
 * (ios/DosarCuSina/Resources/Assets.xcassets, ios/Shared/StatusColors.xcassets), each with a light,
 * a dark and a higher-contrast variant, so nothing is inverted or adjusted by hand for dark mode.
 * One accent, the app's own, never the wallpaper's (docs/DECISIONS.md, 2026-11-25); status colours
 * only for status; everything else neutral.
 */
@Immutable
data class DSColors(
    /** The single accent: buttons, links, selection, focus rings. */
    val accent: Color,
    val onAccent: Color,
    /** The screen behind cards (iOS's grouped background). */
    val background: Color,
    /** Cards and boxes on the background. */
    val surface: Color,
    /** Something raised on a card: a chip, a control's fill on a card. */
    val surfaceRaised: Color,
    /** A field's or a well's fill. */
    val fill: Color,
    /** Hairline separators and outlines. */
    val separator: Color,
    val label: Color,
    val secondaryLabel: Color,
    val tertiaryLabel: Color,
    /** Vivid status fills, for dots, symbols and tinted backgrounds. */
    val status: StatusColors,
    /** Status text, keeping 4.5:1 on cards and on its own tinted fill. */
    val statusText: StatusColors,
    val isDark: Boolean,
) {
    /** The four status tones, as the iPhone app's `DSStatus`. */
    @Immutable
    data class StatusColors(val overdue: Color, val soon: Color, val later: Color, val done: Color) {
        fun of(status: DSStatus): Color = when (status) {
            DSStatus.OVERDUE -> overdue
            DSStatus.SOON -> soon
            DSStatus.LATER -> later
            DSStatus.DONE -> done
        }
    }

    companion object {
        /** The colours for a light or dark screen, with the phone's higher contrast when it asks for it. */
        fun of(dark: Boolean, highContrast: Boolean): DSColors = when {
            dark && highContrast -> DarkHighContrast
            dark -> Dark
            highContrast -> LightHighContrast
            else -> Light
        }

        val Light = DSColors(
            accent = Color(0xFF007AFF),
            onAccent = Color.White,
            background = Color(0xFFF2F2F7),
            surface = Color.White,
            surfaceRaised = Color(0xFFF2F2F7),
            fill = Color(0x1F767680),
            separator = Color(0x4A3C3C43),
            label = Color.Black,
            secondaryLabel = Color(0x993C3C43),
            tertiaryLabel = Color(0x4D3C3C43),
            status = StatusColors(Color(0xFFFF3B30), Color(0xFFFF9500), Color(0xFF8E8E93), Color(0xFF34C759)),
            statusText = StatusColors(Color(0xFFD70015), Color(0xFFB25000), Color(0xFF636366), Color(0xFF1F7A35)),
            isDark = false,
        )

        val LightHighContrast = Light.copy(
            accent = Color(0xFF0040DD),
            separator = Color(0xFF8E8E93),
            secondaryLabel = Color(0xCC3C3C43),
            tertiaryLabel = Color(0x993C3C43),
            status = StatusColors(Color(0xFFD70015), Color(0xFFC93400), Color(0xFF6C6C70), Color(0xFF248A3D)),
            statusText = StatusColors(Color(0xFFA6000F), Color(0xFF8F3F00), Color(0xFF48484A), Color(0xFF175E28)),
        )

        val Dark = DSColors(
            accent = Color(0xFF0A84FF),
            onAccent = Color.White,
            background = Color.Black,
            surface = Color(0xFF1C1C1E),
            surfaceRaised = Color(0xFF2C2C2E),
            fill = Color(0x3D767680),
            separator = Color(0x99545458),
            label = Color.White,
            secondaryLabel = Color(0x99EBEBF5),
            tertiaryLabel = Color(0x4DEBEBF5),
            status = StatusColors(Color(0xFFFF453A), Color(0xFFFF9F0A), Color(0xFF8E8E93), Color(0xFF30D158)),
            statusText = StatusColors(Color(0xFFFF6961), Color(0xFFFFB340), Color(0xFFAEAEB2), Color(0xFF30D158)),
            isDark = true,
        )

        val DarkHighContrast = Dark.copy(
            accent = Color(0xFF409CFF),
            separator = Color(0xFF8E8E93),
            secondaryLabel = Color(0xCCEBEBF5),
            tertiaryLabel = Color(0x99EBEBF5),
            status = StatusColors(Color(0xFFFF6961), Color(0xFFFFB340), Color(0xFFAEAEB2), Color(0xFF30DB5B)),
            statusText = StatusColors(Color(0xFFFF8A80), Color(0xFFFFC46B), Color(0xFFC7C7CC), Color(0xFF5FE07F)),
        )
    }
}

/** The colours of the screen being drawn, set by [DosarTheme]. */
val LocalDSColors = staticCompositionLocalOf { DSColors.Light }

/** How strongly a status or accent colour tints the fill behind it (badges, wells, notices). */
object DSTint {
    const val FILL: Float = 0.14f

    /** A notice's background: a little lighter than a badge's. */
    const val NOTICE: Float = 0.10f

    /** A pressed surface's dim. */
    const val PRESSED: Float = 0.75f

    /** A disabled control. */
    const val DISABLED: Float = 0.45f

    /** The add box's dashed outline. */
    const val ADD_OUTLINE: Float = 0.55f
}
