package com.ar.dosarcusina.ui.shell

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.ui.NavDisplay
import com.ar.dosarcusina.ui.add.AddRoot
import com.ar.dosarcusina.ui.dosar.AddVisitFlow
import com.ar.dosarcusina.ui.dosar.AgendaScreen
import com.ar.dosarcusina.ui.dosar.CategoryScreen
import com.ar.dosarcusina.ui.dosar.DocumentScreen
import com.ar.dosarcusina.ui.dosar.DosarHomeView
import com.ar.dosarcusina.ui.dosar.HistoryEntryScreen
import com.ar.dosarcusina.ui.dosar.ProviderScreen
import com.ar.dosarcusina.ui.dosar.SectionScreen
import com.ar.dosarcusina.ui.ds.DSMotion
import com.ar.dosarcusina.ui.ds.LocalReduceMotion
import com.ar.dosarcusina.ui.search.SearchScreen
import com.ar.dosarcusina.ui.upcoming.ObligationScreen
import com.ar.dosarcusina.ui.upcoming.ReadinessScreen
import com.ar.dosarcusina.ui.upcoming.UpcomingRoot

/**
 * One place on a tab's back stack: the tab's first screen ([route] null) or a pushed route, keyed
 * by its place so the same route twice on a stack keeps two states.
 */
data class ShellEntry(val tab: AppTab, val index: Int, val route: AppRoute?) {
    /** What the entry's saved state is kept under. */
    val key: String get() = "${tab.name}/$index/$route"
}

/** The entries of [tab]'s stack, its first screen first. */
fun ShellRouter.entries(tab: AppTab): List<ShellEntry> =
    listOf(ShellEntry(tab, 0, null)) + stack(tab).mapIndexed { index, route -> ShellEntry(tab, index + 1, route) }

/**
 * The tabs: only the showing one is drawn, each keeping its screens' state while another shows.
 * Each tab is one back stack, with Android's back gesture and its predictive animation; going back
 * on a tab's first screen leaves the app, as Android does.
 */
@Composable
internal fun ShellTabs(router: ShellRouter) {
    val states = rememberSaveableStateHolder()
    val tab = router.tab
    states.SaveableStateProvider(tab.name) { TabStack(router, tab) }
}

@Composable
private fun TabStack(router: ShellRouter, tab: AppTab) {
    val reduceMotion = LocalReduceMotion.current
    NavDisplay(
        backStack = router.entries(tab),
        onBack = { router.pop() },
        transitionSpec = { DSMotion.STANDARD.navigation(back = false, reduceMotion) },
        popTransitionSpec = { DSMotion.STANDARD.navigation(back = true, reduceMotion) },
        predictivePopTransitionSpec = { DSMotion.STANDARD.navigation(back = true, reduceMotion) },
        entryProvider = { entry -> NavEntry(entry, contentKey = entry.key) { EntryScreen(it) } },
    )
}

@Composable
private fun EntryScreen(entry: ShellEntry) {
    val route = entry.route
    if (route == null) TabRoot(entry.tab) else RouteScreen(route)
}

/** A tab's first screen. Tab roots never add a back stack of their own. */
@Composable
private fun TabRoot(tab: AppTab) {
    when (tab) {
        AppTab.DOSAR -> DosarHomeView()
        AppTab.UPCOMING -> UpcomingRoot()
        AppTab.ADD -> AddRoot()
        AppTab.SEARCH -> SearchScreen()
    }
}

/** The screen of a pushed route, behind the lock the route declares ([AppRoute.lock]). */
@Composable
fun RouteScreen(route: AppRoute) {
    RouteLockGate(route.lock) {
        when (route) {
            is AppRoute.Asset -> SectionScreen(assetId = route.id)
            is AppRoute.Obligation -> ObligationScreen(obligationId = route.id)
            is AppRoute.HistoryEntry -> HistoryEntryScreen(entryId = route.id)
            is AppRoute.Provider -> ProviderScreen(providerId = route.id)
            is AppRoute.Document -> DocumentScreen(attachmentId = route.id)
            AppRoute.Agenda -> AgendaScreen()
            is AppRoute.Category -> CategoryScreen(templateKey = route.key)
            is AppRoute.AddVisit -> AddVisitFlow(assetId = route.assetId)
            is AppRoute.Readiness -> ReadinessScreen(route = route.route)
            AppRoute.Home, AppRoute.Upcoming, AppRoute.Search, AppRoute.Intake, is AppRoute.Settings,
            is AppRoute.Completion,
            -> HandedToTheRouter(route)
        }
    }
}

/** Tabs and sheets aren't pushed: one that ends up on a stack is handed to the router instead. */
@Composable
private fun HandedToTheRouter(route: AppRoute) {
    val router = LocalShellRouter.current
    LaunchedEffect(route) {
        router.pop()
        router.open(route)
    }
}
