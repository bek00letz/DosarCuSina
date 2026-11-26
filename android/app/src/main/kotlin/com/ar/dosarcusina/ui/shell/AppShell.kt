package com.ar.dosarcusina.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DS
import com.ar.dosarcusina.ui.ds.DSControl
import com.ar.dosarcusina.ui.ds.DSIcon
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.ds.DSText
import com.ar.dosarcusina.ui.ds.DSTextStyle
import com.ar.dosarcusina.ui.ds.DSToastCenter
import com.ar.dosarcusina.ui.ds.DSToastHost
import com.ar.dosarcusina.ui.ds.LocalToastCenter
import com.ar.dosarcusina.ui.ds.countText

/** The shell's router, for a screen that opens or pushes a route; provided by [AppShell]. */
val LocalShellRouter = staticCompositionLocalOf<ShellRouter> { error("No ShellRouter: screens draw inside AppShell") }

/**
 * The app once the store is open, as the iPhone app's `AppShell`: four labelled tabs, each with its
 * own back stack, every route through one [router], the shell's sheet over them (never stacked, the
 * next waiting for the last's dismissal), and a toast above the navigation bar that outlives the
 * screen it came from. A route from outside ([navigator]) is opened once the app lock lets it.
 * Every screen is drawn behind the lock its route declares, through [lockGate]. Draw it inside
 * [com.ar.dosarcusina.ui.ds.DosarTheme].
 */
@Composable
fun AppShell(
    router: ShellRouter,
    navigator: AppNavigator,
    lockGate: LockGate,
    modifier: Modifier = Modifier,
    inboxCount: Int = 0,
    talkBackOn: Boolean = false,
) {
    val toasts = remember { DSToastCenter() }
    LaunchedEffect(navigator, router) {
        snapshotFlow { navigator.pendingRoute.takeIf { !navigator.isLocked } }
            .collect { if (it != null) navigator.consume()?.let(router::open) }
    }
    CompositionLocalProvider(
        LocalShellRouter provides router,
        LocalShellSheets provides router.sheets,
        LocalLockGate provides lockGate,
        LocalToastCenter provides toasts,
    ) {
        Scaffold(
            modifier = modifier.fillMaxSize(),
            containerColor = DS.colors.background,
            bottomBar = { ShellTabBar(router, inboxCount) },
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
                ShellTabs(router)
                DSToastHost(toasts, talkBackOn = talkBackOn)
            }
        }
        ShellSheetHost(router.sheets)
    }
}

/** The tab bar: Android's navigation bar, each tab with its symbol and its name. */
@Composable
private fun ShellTabBar(router: ShellRouter, inboxCount: Int) {
    val colors = DS.colors
    NavigationBar(containerColor = colors.surface) {
        AppTab.entries.forEach { tab ->
            val selected = router.tab == tab
            NavigationBarItem(
                selected = selected,
                onClick = { router.select(tab) },
                icon = { TabIcon(tab, if (selected) colors.accent else colors.secondaryLabel, inboxCount) },
                // The bar keeps its height: its words grow with the font size up to where they still fit.
                label = { CappedFontScale { DSText(tab.title.written(), DSTextStyle.CAPTION, maxLines = 1) } },
                colors = NavigationBarItemDefaults.colors(indicatorColor = colors.accent.copy(alpha = INDICATOR_TINT)),
            )
        }
    }
}

/** A tab's symbol, with Adaugă's count of what waits in De verificat. */
@Composable
private fun TabIcon(tab: AppTab, ink: Color, inboxCount: Int) {
    if (tab != AppTab.ADD || inboxCount <= 0) return DSIcon(tab.symbol, ink)
    BadgedBox(badge = { Badge { DSText(countText(inboxCount), DSTextStyle.CAPTION, numeric = true) } }) {
        DSIcon(tab.symbol, ink)
    }
}

/**
 * Words of the app's chrome (the tab bar) that keep the bar's height: they grow with the font size
 * up to [DSControl.LARGEST_DECORATION_SCALE], as the iPhone's tab bar does.
 */
@Composable
private fun CappedFontScale(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val capped = Density(density.density, density.fontScale.coerceAtMost(DSControl.LARGEST_DECORATION_SCALE))
    CompositionLocalProvider(LocalDensity provides capped, content = content)
}

/** The tab's name, as on the iPhone. */
val AppTab.title: Word
    get() = when (this) {
        AppTab.DOSAR -> Word.app("Dosar")
        AppTab.UPCOMING -> Word.app("Urmează")
        AppTab.ADD -> Word.app("Adaugă")
        AppTab.SEARCH -> Word.app("Caută")
    }

/** The tab's symbol, matched to the iPhone's. */
val AppTab.symbol: DSSymbol
    get() = when (this) {
        AppTab.DOSAR -> DSSymbol.BINDER
        AppTab.UPCOMING -> DSSymbol.SOON
        AppTab.ADD -> DSSymbol.ADD_CIRCLE
        AppTab.SEARCH -> DSSymbol.SEARCH
    }

private const val INDICATOR_TINT = 0.14f
