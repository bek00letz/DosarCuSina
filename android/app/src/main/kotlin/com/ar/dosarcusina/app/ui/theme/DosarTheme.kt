package com.ar.dosarcusina.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp

// The app's one accent, the iPhone app's (AccentColor), never the wallpaper's colours.
// Neutral surfaces around it, and a real dark theme. Later phases complete the scheme.
private val LightColors = lightColorScheme(
    primary = Color(0xFF007AFF),
    onPrimary = Color.White,
    background = Color.White,
    onBackground = Color.Black,
    surface = Color.White,
    onSurface = Color.Black,
    onSurfaceVariant = Color(0xFF6C6C70),
    outline = Color(0xFFC6C6C8),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF0A84FF),
    onPrimary = Color.White,
    background = Color.Black,
    onBackground = Color.White,
    surface = Color(0xFF1C1C1E),
    onSurface = Color.White,
    onSurfaceVariant = Color(0xFF98989F),
    outline = Color(0xFF38383A),
)

// Large titles a little tighter, as on the iPhone; the rest is Material's scale.
private val DosarTypography = Typography().run {
    copy(
        displayLarge = displayLarge.copy(letterSpacing = (-0.5).sp),
        displayMedium = displayMedium.copy(letterSpacing = (-0.5).sp),
        displaySmall = displaySmall.copy(letterSpacing = (-0.25).sp),
        headlineLarge = headlineLarge.copy(letterSpacing = (-0.25).sp),
    )
}

@Composable
fun DosarTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = DosarTypography,
        content = content,
    )
}
