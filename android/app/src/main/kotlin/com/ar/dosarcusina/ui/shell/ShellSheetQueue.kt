package com.ar.dosarcusina.ui.shell

/**
 * Everything up over the tabs, and what waits for it, as the iPhone app's `ShellSheetQueue`: the
 * shell's one sheet and the one waiting for it to finish closing, so sheets never stack and the
 * next opens as soon as the last is gone (when its dismissal completes, never after a guessed
 * pause); and the screens' own sheets and dialogs ([DSSheet], [DSDialog]), so a route never lands
 * under one. Pure, so it is tested.
 *
 * A route that comes while a screen's own sheet is up closes them, the top one first and each once
 * the one above has closed, then lands; while one of them, or the shell's sheet, holds work the
 * person hasn't saved, it waits until the person has closed them.
 */
class ShellSheetQueue {
    /** What the shell asks to show; null while nothing should be up (or the last is closing). */
    var shown: ShellSheet? = null
        private set

    /** Opens once the sheet on screen has finished closing. */
    var waiting: ShellSheet? = null
        private set

    /** A sheet is on screen, or still on its way off it. */
    var isOnScreen: Boolean = false
        private set

    /** The shell's sheet holds work the person hasn't saved (its form's discard guard). */
    var shellHoldsWork: Boolean = false
        private set

    /** A screen's own sheet on screen, and whether a route must wait for the person to close it. */
    data class ScreenSheet(
        val id: String,
        /** It must be answered before anything else. */
        val waitsByItself: Boolean,
        /** Its form holds changes the person hasn't saved. */
        val holdsWork: Boolean = false,
    ) {
        val keepsRoutesWaiting: Boolean get() = waitsByItself || holdsWork
    }

    /** The screens' own sheets on screen, the first opened first: the last is on top. */
    var screens: List<ScreenSheet> = emptyList()
        private set

    /** A route that came while something was up over the tabs; the newest wins. */
    var waitingRoute: AppRoute? = null
        private set

    /** What a waiting route does next. */
    sealed interface RouteStep {
        /** Nothing is up any more: it lands. */
        data class Land(val route: AppRoute) : RouteStep

        /** Closes this screen's sheet, the top one, and waits for its dismissal to complete. */
        data class Close(val id: String) : RouteStep

        /** Something up holds unsaved work: it waits for the person to close it. */
        data object Wait : RouteStep
    }

    /** Something is up, closing, or about to open. */
    val isBusy: Boolean
        get() = shown != null || waiting != null || isOnScreen || screens.isNotEmpty() || waitingRoute != null

    /**
     * A route arrives: it lands at once, or waits for what is up over the tabs. The shell's own
     * sheet doesn't hold it back unless it holds unsaved work: landing presents the route's sheet,
     * which closes the one on screen first.
     */
    fun arrive(route: AppRoute): RouteStep {
        waitingRoute = route
        return nextStep()
    }

    /** A screen's own sheet came on screen (again, after something over it closed: it keeps its place). */
    fun screenDidAppear(id: String, waitsByItself: Boolean) {
        if (screens.any { it.id == id }) return
        screens = screens + ScreenSheet(id, waitsByItself)
    }

    /**
     * A screen's own sheet's form now holds (or no longer holds) unsaved work. A route already
     * waiting goes on waiting for the person: it is looked at again only when something closes.
     */
    fun screen(id: String, holdsWork: Boolean) {
        screens = screens.map { if (it.id == id) it.copy(holdsWork = holdsWork) else it }
    }

    /** The shell's sheet's form now holds (or no longer holds) unsaved work. */
    fun shellSheet(holdsWork: Boolean) {
        shellHoldsWork = holdsWork
    }

    /** A screen's own sheet finished closing: what a waiting route does next, if one waits. */
    fun screenDidDismiss(id: String): RouteStep? {
        screens = screens.filterNot { it.id == id }
        return if (waitingRoute == null) null else nextStep()
    }

    private fun nextStep(): RouteStep {
        val route = waitingRoute ?: return RouteStep.Wait
        if (screens.any { it.keepsRoutesWaiting } || (isOnScreen && shellHoldsWork)) return RouteStep.Wait
        screens.lastOrNull()?.let { return RouteStep.Close(it.id) }
        waitingRoute = null
        return RouteStep.Land(route)
    }

    /** Shows [next] (null closes). Over a sheet on screen it closes that one first and waits. */
    fun present(next: ShellSheet?) {
        if (!isOnScreen) {
            // Nothing to wait for: it opens (or closes) right away.
            shown = next
            waiting = null
            return
        }
        if (next == shown) {
            // Already up (or nothing asked while one closes): forget anything waiting.
            waiting = null
            return
        }
        waiting = next
        shown = null
    }

    /** The sheet came on screen. */
    fun didAppear() {
        isOnScreen = true
    }

    /**
     * The sheet finished closing, however it closed: the waiting one opens now, and a route that
     * waited for it is looked at again.
     */
    fun didDismiss(): RouteStep? {
        isOnScreen = false
        shellHoldsWork = false
        waiting?.let {
            shown = it
            waiting = null
        }
        return if (waitingRoute == null) null else nextStep()
    }
}
