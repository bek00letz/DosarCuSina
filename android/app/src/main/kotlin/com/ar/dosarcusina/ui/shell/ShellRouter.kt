package com.ar.dosarcusina.ui.shell

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Owns the selected tab, each tab's back stack and what is up over the tabs ([sheets]), as the
 * iPhone app's `ShellRouter`. Every route, from inside or outside the app, goes through [open]: it
 * switches tab, replaces that tab's back stack and presents a sheet if the plan has one
 * ([ShellRouting.plan]), never under a screen's own sheet ([ShellSheetQueue]). State Compose
 * reads, used on the main thread.
 */
@Stable
class ShellRouter {
    private var stacks by mutableStateOf(AppTab.entries.associateWith { emptyList<AppRoute>() })

    /** The shell's sheet and the screens' own, and the routes that wait for them. */
    val sheets: ShellSheets = ShellSheets(::follow)

    /** The tab showing. */
    var tab: AppTab by mutableStateOf(AppTab.DOSAR)
        private set

    /** The screens pushed on [tab]'s first screen, first pushed first. */
    fun stack(tab: AppTab): List<AppRoute> = stacks.getValue(tab)

    /** Opens a route; while a screen's own sheet is up it closes them first, or waits for the person. */
    fun open(route: AppRoute) = follow(sheets.arrive(route))

    /** Pushes a screen on the current tab. A tab's first screen or a sheet is opened with [open] instead. */
    fun push(route: AppRoute) {
        if (ShellRouting.isPushed(route)) setStack(tab, stack(tab) + route) else open(route)
    }

    /** Goes back one screen on the current tab; false on its first screen, where back leaves the app. */
    fun pop(): Boolean {
        val current = stack(tab)
        if (current.isEmpty()) return false
        setStack(tab, current.dropLast(1))
        return true
    }

    /** Selecting the tab that is already showing goes back to its first screen. */
    fun select(newTab: AppTab) {
        if (newTab == tab) setStack(newTab, emptyList())
        tab = newTab
    }

    private fun follow(step: ShellSheetQueue.RouteStep?) {
        when (step) {
            is ShellSheetQueue.RouteStep.Land -> land(step.route)
            is ShellSheetQueue.RouteStep.Close -> sheets.close(step.id)
            ShellSheetQueue.RouteStep.Wait, null -> Unit
        }
    }

    private fun land(route: AppRoute) {
        val plan = ShellRouting.plan(route)
        tab = plan.tab
        setStack(plan.tab, plan.path)
        sheets.present(plan.sheet)
    }

    private fun setStack(tab: AppTab, path: List<AppRoute>) {
        stacks = stacks + (tab to path)
    }
}

/**
 * What is up over the tabs, through the one queue ([ShellSheetQueue]): the shell's sheet ([shown])
 * and the screens' own sheets and dialogs, which tell it when they come on screen, when they hold
 * unsaved work and when their dismissal has completed.
 */
@Stable
class ShellSheets internal constructor(private val follow: (ShellSheetQueue.RouteStep?) -> Unit) {
    private val queue = ShellSheetQueue()

    /** How to close each screen's own sheet on screen, for a route that closes them. */
    private val closers = mutableMapOf<String, () -> Unit>()

    /** The shell's sheet, as the queue says. */
    var shown: ShellSheet? by mutableStateOf(null)
        private set

    /** Something is up over the tabs, closing or about to open, or a route waits: nothing else should pop up. */
    var isBusy: Boolean by mutableStateOf(false)
        private set

    /** Presents the shell's sheet (null closes it), closing the one on screen first so sheets never stack. */
    fun present(next: ShellSheet?) = sync { queue.present(next) }

    /** The shell's sheet came on screen. */
    fun didAppear() = sync { queue.didAppear() }

    /** The shell's sheet finished closing, however it closed: a route waiting for it goes on. */
    fun didDismiss() = follow(sync { queue.didDismiss() })

    /** A screen's own sheet came on screen ([DSSheet], [DSDialog]), with how a route closes it. */
    fun screenDidAppear(id: String, waitsByItself: Boolean, close: () -> Unit) {
        closers[id] = close
        sync { queue.screenDidAppear(id, waitsByItself) }
    }

    /** A screen's own sheet finished closing: a route waiting for it goes on. */
    fun screenDidDismiss(id: String) {
        closers.remove(id)
        follow(sync { queue.screenDidDismiss(id) })
    }

    /** A sheet's form holds (or no longer holds) unsaved work ([dsDiscardGuard]); [SHELL_SHEET_ID] for the shell's. */
    fun holdsWork(id: String, holds: Boolean) = sync {
        if (id == SHELL_SHEET_ID) queue.shellSheet(holds) else queue.screen(id, holds)
    }

    /** Whether the sheet [id] holds unsaved work now. */
    fun holdsWork(id: String): Boolean =
        if (id == SHELL_SHEET_ID) queue.shellHoldsWork else queue.screens.any { it.id == id && it.holdsWork }

    internal fun arrive(route: AppRoute): ShellSheetQueue.RouteStep = sync { queue.arrive(route) }

    internal fun close(id: String) {
        closers[id]?.invoke()
    }

    /** Runs a step of the queue, then shows what it now says. */
    private fun <R> sync(step: () -> R): R {
        val result = step()
        shown = queue.shown
        isBusy = queue.isBusy
        return result
    }

    companion object {
        /** The id the shell's own sheet tells its form ([LocalScreenSheet]). */
        const val SHELL_SHEET_ID: String = "shell"
    }
}
