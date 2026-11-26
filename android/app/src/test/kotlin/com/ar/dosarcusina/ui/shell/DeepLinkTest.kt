package com.ar.dosarcusina.ui.shell

import com.ar.dosarcusina.core.readiness.ReadinessRoute
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** `dosarcusina://` links, the same as the iPhone app's (`DeepLinkTests`). */
class DeepLinkTest {
    @Test
    fun `every route's link opens it again`() {
        Routes.all.forEach { route -> assertEquals(route, DeepLink.route(DeepLink.url(route)), DeepLink.url(route)) }
    }

    @Test
    fun `links are written as the iPhone writes them`() {
        val id = Routes.asset.toString()
        assertEquals("dosarcusina://home", DeepLink.url(AppRoute.Home))
        assertEquals("dosarcusina://asset/$id", DeepLink.url(AppRoute.Asset(Routes.asset)))
        assertEquals("dosarcusina://visit/$id", DeepLink.url(AppRoute.AddVisit(Routes.asset)))
        assertEquals(
            "dosarcusina://complete/${Routes.obligation}/2026-12-01",
            DeepLink.url(AppRoute.Completion(Routes.obligation, Routes.cycle)),
        )
        assertEquals("dosarcusina://settings", DeepLink.url(AppRoute.Settings()))
        assertEquals("dosarcusina://settings/backup", DeepLink.url(AppRoute.Settings(SettingsSection.BACKUP)))
        assertEquals("dosarcusina://ready/trip", DeepLink.url(AppRoute.Readiness(ReadinessRoute.Trip(null))))
        val sale = AppRoute.Readiness(ReadinessRoute.Sale(Routes.asset))
        assertEquals("dosarcusina://ready/sale/$id", DeepLink.url(sale))
        assertEquals("dosarcusina://category/vehicle", DeepLink.url(AppRoute.Category("vehicle")))
    }

    @Test
    fun `older and differently written links still open`() {
        assertEquals(AppRoute.Upcoming, DeepLink.route("dosarcusina://radar"))
        assertEquals(AppRoute.Home, DeepLink.route("DOSARCUSINA://HOME"))
        val upper = Routes.asset.toString().uppercase()
        assertEquals(AppRoute.Asset(Routes.asset), DeepLink.route("dosarcusina://asset/$upper"))
        assertEquals(AppRoute.Settings(null), DeepLink.route("dosarcusina://settings/nowhere"))
    }

    @Test
    fun `a link that can't say what it opens opens nothing`() {
        listOf(
            "https://example.com/asset/${Routes.asset}",
            "dosarcusina://asset",
            "dosarcusina://asset/not-an-id",
            "dosarcusina://asset/1-1-1-1-1",
            "dosarcusina://complete/${Routes.obligation}",
            "dosarcusina://complete/${Routes.obligation}/someday",
            "dosarcusina://ready/sale",
            "dosarcusina://ready/holiday",
            "dosarcusina://elsewhere",
            "not a link",
        ).forEach { assertNull(DeepLink.route(it), it) }
    }

    @Test
    fun `the navigator hands a link out once, and none while the app is locked`() {
        var locked = true
        val navigator = AppNavigator { locked }
        navigator.open(DeepLink.url(AppRoute.Search))
        assertNull(navigator.consume())
        locked = false
        assertEquals(AppRoute.Search, navigator.consume())
        assertNull(navigator.consume())
        assertEquals(false, navigator.open("https://example.com"))
    }
}
