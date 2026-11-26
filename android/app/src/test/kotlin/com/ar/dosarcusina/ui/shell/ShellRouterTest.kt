package com.ar.dosarcusina.ui.shell

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The router: tabs with one back stack each, every route through [ShellRouter.open]. */
class ShellRouterTest {
    private val asset = AppRoute.Asset(Routes.asset)

    @Test
    fun `a route switches tab, replaces that tab's stack and presents its sheet`() {
        val router = ShellRouter()
        router.push(AppRoute.Agenda)
        router.open(AppRoute.AddVisit(Routes.asset))
        assertEquals(AppTab.DOSAR, router.tab)
        assertEquals(listOf(asset), router.stack(AppTab.DOSAR))
        assertEquals(ShellSheet.AddVisit(Routes.asset), router.sheets.shown)

        router.open(AppRoute.Obligation(Routes.obligation))
        assertEquals(AppTab.UPCOMING, router.tab)
        assertEquals(listOf(AppRoute.Obligation(Routes.obligation)), router.stack(AppTab.UPCOMING))
        assertEquals(listOf(asset), router.stack(AppTab.DOSAR), "the other tab keeps its stack")
    }

    @Test
    fun `each tab keeps a back stack of its own`() {
        val router = ShellRouter()
        router.push(asset)
        router.select(AppTab.SEARCH)
        router.push(AppRoute.Document(Routes.document))
        router.select(AppTab.DOSAR)
        assertEquals(listOf(asset), router.stack(AppTab.DOSAR))
        assertEquals(listOf(AppRoute.Document(Routes.document)), router.stack(AppTab.SEARCH))
    }

    @Test
    fun `back goes one screen back, and on a tab's first screen leaves it to Android`() {
        val router = ShellRouter()
        router.push(asset)
        router.push(AppRoute.HistoryEntry(Routes.entry))
        assertTrue(router.pop())
        assertEquals(listOf(asset), router.stack(AppTab.DOSAR))
        assertTrue(router.pop())
        assertFalse(router.pop())
    }

    @Test
    fun `selecting the tab that shows goes back to its first screen`() {
        val router = ShellRouter()
        router.push(asset)
        router.select(AppTab.DOSAR)
        assertEquals(emptyList<AppRoute>(), router.stack(AppTab.DOSAR))
    }

    @Test
    fun `a tab or a sheet pushed is opened instead`() {
        val router = ShellRouter()
        router.push(AppRoute.Settings(SettingsSection.ABOUT))
        assertEquals(emptyList<AppRoute>(), router.stack(AppTab.DOSAR))
        assertEquals(ShellSheet.Settings(SettingsSection.ABOUT), router.sheets.shown)
    }

    @Test
    fun `a route never lands under a screen's own sheet: it closes it, then lands once it has closed`() {
        val router = ShellRouter()
        var closed = 0
        router.sheets.screenDidAppear("photo", waitsByItself = false) { closed += 1 }
        router.open(asset)
        assertEquals(1, closed)
        assertEquals(emptyList<AppRoute>(), router.stack(AppTab.DOSAR), "nothing lands while the sheet is up")
        assertTrue(router.sheets.isBusy)
        router.sheets.screenDidDismiss("photo")
        assertEquals(listOf(asset), router.stack(AppTab.DOSAR))
        assertFalse(router.sheets.isBusy)
    }

    @Test
    fun `a route under an unsaved sheet waits until the person closes it`() {
        val router = ShellRouter()
        var closed = 0
        router.sheets.screenDidAppear("form", waitsByItself = false) { closed += 1 }
        router.sheets.holdsWork("form", true)
        router.open(asset)
        assertEquals(0, closed, "work the person hasn't saved is never closed for them")
        assertTrue(router.sheets.holdsWork("form"))
        router.sheets.screenDidDismiss("form")
        assertEquals(listOf(asset), router.stack(AppTab.DOSAR))
    }

    @Test
    fun `the shell's sheet asked over another opens once the first has closed`() {
        val router = ShellRouter()
        router.open(AppRoute.Settings())
        router.sheets.didAppear()
        router.open(AppRoute.AddVisit(Routes.asset))
        assertNull(router.sheets.shown, "the settings sheet closes first")
        router.sheets.didDismiss()
        assertEquals(ShellSheet.AddVisit(Routes.asset), router.sheets.shown)
    }

    @Test
    fun `a route under the shell's unsaved sheet waits, then lands when the person closes it`() {
        val router = ShellRouter()
        router.open(AppRoute.Settings())
        router.sheets.didAppear()
        router.sheets.holdsWork(ShellSheets.SHELL_SHEET_ID, true)
        router.open(AppRoute.Search)
        assertEquals(AppTab.DOSAR, router.tab)
        router.sheets.present(null)
        router.sheets.didDismiss()
        assertEquals(AppTab.SEARCH, router.tab)
    }

    @Test
    fun `a tab's entries are its first screen and then what is pushed, each keyed by its place`() {
        val router = ShellRouter()
        router.push(asset)
        router.push(asset)
        val entries = router.entries(AppTab.DOSAR)
        assertEquals(listOf(null, asset, asset), entries.map { it.route })
        assertEquals(entries.size, entries.map { it.key }.toSet().size, "the same route twice keeps two states")
    }
}
