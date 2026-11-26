package com.ar.dosarcusina.ui.shell

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Holds a route that arrived from outside the screens (a reminder tap, a widget, a link) until the
 * shell takes it, as the iPhone app's `AppNavigator`. While the app lock is closed nothing is handed
 * out: links wait until it opens ([isAppLocked], the lock's answer, Phase 6).
 */
@Stable
class AppNavigator(private val isAppLocked: () -> Boolean = { false }) {
    /** The route waiting to be opened; the newest wins. */
    var pendingRoute: AppRoute? by mutableStateOf(null)
        private set

    /** Whether the app lock holds routes back now. */
    val isLocked: Boolean get() = isAppLocked()

    /** How many routes were asked for so far, so the app doesn't steer a person who is opening something. */
    var openCount: Int = 0
        private set

    fun open(route: AppRoute) {
        openCount += 1
        pendingRoute = route
    }

    /** Opens a `dosarcusina://` link; false for anything that isn't one. */
    fun open(url: String): Boolean {
        val route = DeepLink.route(url) ?: return false
        open(route)
        return true
    }

    /** The pending route, once, cleared as it is handed out; null while the app is locked. */
    fun consume(): AppRoute? {
        if (isAppLocked()) return null
        val route = pendingRoute
        pendingRoute = null
        return route
    }
}
