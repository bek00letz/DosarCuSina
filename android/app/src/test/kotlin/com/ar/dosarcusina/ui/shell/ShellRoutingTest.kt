package com.ar.dosarcusina.ui.shell

import com.ar.dosarcusina.core.readiness.ReadinessRoute
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.UUID

/** Where every route lands and which lock it opens behind, as the iPhone app's `ShellRoutingTests`. */
class ShellRoutingTest {
    private val asset = AppRoute.Asset(Routes.asset)
    private val obligation = AppRoute.Obligation(Routes.obligation)
    private val entry = AppRoute.HistoryEntry(Routes.entry)
    private val document = AppRoute.Document(Routes.document)
    private val provider = AppRoute.Provider(Routes.provider)
    private val category = AppRoute.Category("vehicle")
    private val completion = AppRoute.Completion(Routes.obligation, Routes.cycle)
    private val backup = AppRoute.Settings(SettingsSection.BACKUP)

    @Test
    fun `every route lands where the iPhone app lands it`() {
        val expected = mapOf(
            AppRoute.Home to plan(AppTab.DOSAR),
            AppRoute.Upcoming to plan(AppTab.UPCOMING),
            AppRoute.Search to plan(AppTab.SEARCH),
            AppRoute.Intake to plan(AppTab.ADD),
            AppRoute.Agenda to plan(AppTab.DOSAR, AppRoute.Agenda),
            asset to plan(AppTab.DOSAR, asset),
            AppRoute.AddVisit(Routes.asset) to plan(AppTab.DOSAR, asset, sheet = ShellSheet.AddVisit(Routes.asset)),
            obligation to plan(AppTab.UPCOMING, obligation),
            completion to plan(AppTab.UPCOMING, obligation, sheet = ShellSheet.Completion(Routes.obligation, Routes.cycle)),
            entry to plan(AppTab.DOSAR, entry),
            provider to plan(AppTab.DOSAR, AppRoute.Agenda, provider),
            document to plan(AppTab.DOSAR, document),
            category to plan(AppTab.DOSAR, category),
            AppRoute.Settings() to plan(AppTab.DOSAR, sheet = ShellSheet.Settings(null)),
            backup to plan(AppTab.DOSAR, sheet = ShellSheet.Settings(SettingsSection.BACKUP)),
            trip(null) to plan(AppTab.UPCOMING, trip(null)),
            trip(Routes.member) to plan(AppTab.DOSAR, AppRoute.Asset(Routes.member), trip(Routes.member)),
            sale() to plan(AppTab.DOSAR, asset, sale()),
            claim() to plan(AppTab.DOSAR, asset, claim()),
        )
        assertEquals(Routes.all.toSet(), expected.keys, "every route has its expected plan")
        expected.forEach { (route, plan) -> assertEquals(plan, ShellRouting.plan(route), "$route") }
    }

    @Test
    fun `a section's routes open behind its lock, a record's draw their own`() {
        assertEquals(RouteLock.Section(Routes.asset), asset.lock)
        assertEquals(RouteLock.Section(Routes.asset), AppRoute.AddVisit(Routes.asset).lock)
        listOf(AppRoute.Home, AppRoute.Upcoming, AppRoute.Search, AppRoute.Intake, AppRoute.Agenda, AppRoute.Settings())
            .forEach { assertEquals(RouteLock.Open, it.lock, "$it") }
        listOf(obligation, completion, entry, document, provider, category, sale())
            .forEach { assertEquals(RouteLock.DrawnByItsScreen, it.lock, "$it") }
    }

    @Test
    fun `a sheet writes behind the section it writes into`() {
        val member = RouteLock.Section(Routes.member)
        assertEquals(RouteLock.Open, ShellSheet.Settings().lock)
        assertEquals(RouteLock.Section(Routes.asset), ShellSheet.AddVisit(Routes.asset).lock)
        assertEquals(RouteLock.Open, ShellSheet.AddSection(AddSectionRequest.TopLevel).lock)
        assertEquals(member, ShellSheet.AddSection(AddSectionRequest(parentId = Routes.member)).lock)
        assertEquals(RouteLock.Open, ShellSheet.AddPersonalDocument(null).lock)
        assertEquals(member, ShellSheet.AddPersonalDocument(Routes.member).lock)
        assertEquals(member, ShellSheet.AddDocument(Routes.member).lock)
        assertEquals(RouteLock.DrawnByItsScreen, ShellSheet.Completion(Routes.obligation, Routes.cycle).lock)
    }

    @Test
    fun `a plan's locks are its screens' and its sheet's, in order`() {
        val plan = ShellRouting.plan(AppRoute.AddVisit(Routes.asset))
        assertEquals(listOf(RouteLock.Section(Routes.asset), RouteLock.Section(Routes.asset)), plan.locks)
    }

    @Test
    fun `tabs and sheets are never pushed`() {
        listOf(AppRoute.Home, AppRoute.Upcoming, AppRoute.Search, AppRoute.Intake, AppRoute.Settings(), completion)
            .forEach { assertFalse(ShellRouting.isPushed(it), "$it") }
        assertTrue(ShellRouting.isPushed(asset))
        assertTrue(ShellRouting.isPushed(AppRoute.Agenda))
    }

    private fun plan(tab: AppTab, vararg path: AppRoute, sheet: ShellSheet? = null) =
        ShellRoutePlan(tab, path.toList(), sheet)

    private fun trip(holder: UUID?) = AppRoute.Readiness(ReadinessRoute.Trip(holder))

    private fun sale() = AppRoute.Readiness(ReadinessRoute.Sale(Routes.asset))

    private fun claim() = AppRoute.Readiness(ReadinessRoute.Claim(Routes.asset))
}
