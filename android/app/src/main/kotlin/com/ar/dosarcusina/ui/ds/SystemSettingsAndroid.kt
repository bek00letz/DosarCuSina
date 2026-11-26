package com.ar.dosarcusina.ui.ds

import android.app.UiModeManager
import android.content.Context
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext

// The phone's settings the design system follows, read where Android keeps them. The only file of
// the design system that reads Android itself (its name ends in Android.kt).

/**
 * Whether the phone's "remove animations" is on (animator duration scale 0, Android's Reduce
 * Motion), followed while the app runs.
 */
@Composable
fun systemRemovesAnimations(): Boolean {
    val context = LocalContext.current
    var removes by remember { mutableStateOf(animationsRemoved(context)) }
    DisposableEffect(context) {
        val uri = Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE)
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                removes = animationsRemoved(context)
            }
        }
        context.contentResolver.registerContentObserver(uri, false, observer)
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }
    return removes
}

private fun animationsRemoved(context: Context): Boolean =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

/**
 * Whether the phone asks for higher contrast: Android 14's contrast setting at medium or high.
 * Earlier versions have no such setting the app may read.
 */
@Composable
fun systemAsksForHighContrast(): Boolean {
    val context = LocalContext.current
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
    val modes = context.getSystemService(UiModeManager::class.java) ?: return false
    return modes.contrast >= MEDIUM_CONTRAST
}

/** Android's medium contrast level (`UiModeManager.getContrast`, from −1 to 1). */
private const val MEDIUM_CONTRAST = 0.5f
