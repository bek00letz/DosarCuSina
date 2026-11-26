package com.ar.dosarcusina.ui.shell

import com.ar.dosarcusina.core.readiness.ReadinessRoute
import com.ar.dosarcusina.core.readiness.ReadinessSituation
import com.ar.dosarcusina.core.values.CalendarDay
import java.net.URI
import java.net.URISyntaxException
import java.util.Locale
import java.util.UUID

/**
 * `dosarcusina://` links, built and read in one place, the same links as the iPhone app's
 * `DeepLink`, so a link one app makes opens the same place in the other:
 *
 * - `dosarcusina://home`, `upcoming` (also `radar`, from earlier builds), `search`, `intake`, `agenda`
 * - `asset/<uuid>`, `visit/<asset uuid>`, `obligation/<uuid>`, `history/<uuid>`, `provider/<uuid>`,
 *   `document/<uuid>`, and `complete/<uuid>/<yyyy-MM-dd>` („Am rezolvat” for that cycle)
 * - `category/<key>`
 * - `settings` or `settings/<section>`
 * - `ready/trip`, `ready/trip/<member uuid>`, `ready/sale/<asset uuid>`, `ready/claim/<asset uuid>`
 */
object DeepLink {
    const val SCHEME: String = "dosarcusina"

    /** The link that opens [route]. */
    fun url(route: AppRoute): String {
        val (host, path) = parts(route)
        return "$SCHEME://$host" + path.joinToString("") { "/$it" }
    }

    /** The route a link opens; null for anything that isn't one of the app's links. */
    fun route(url: String): AppRoute? {
        val uri = try {
            URI(url)
        } catch (_: URISyntaxException) {
            return null
        }
        if (uri.scheme?.lowercase(Locale.ROOT) != SCHEME) return null
        val host = uri.host?.lowercase(Locale.ROOT) ?: return null
        val pieces = uri.path.orEmpty().split('/').filter { it.isNotEmpty() }
        return route(host, pieces)
    }

    private fun route(host: String, pieces: List<String>): AppRoute? {
        val argument = pieces.firstOrNull()
        val id = argument?.let(::uuid)
        return when (host) {
            "home" -> AppRoute.Home
            "upcoming", "radar" -> AppRoute.Upcoming
            "search" -> AppRoute.Search
            "agenda" -> AppRoute.Agenda
            "intake" -> AppRoute.Intake
            "visit" -> id?.let(AppRoute::AddVisit)
            "asset" -> id?.let(AppRoute::Asset)
            "obligation" -> id?.let(AppRoute::Obligation)
            "complete" -> completion(id, pieces.getOrNull(1))
            "history" -> id?.let(AppRoute::HistoryEntry)
            "provider" -> id?.let(AppRoute::Provider)
            "document" -> id?.let(AppRoute::Document)
            "category" -> argument?.let(AppRoute::Category)
            "settings" -> AppRoute.Settings(SettingsSection.of(argument))
            "ready" -> readiness(argument, pieces.getOrNull(1)?.let(::uuid))
            else -> null
        }
    }

    /** A link without the cycle it was for can't say which one to close. */
    private fun completion(id: UUID?, cycle: String?): AppRoute? {
        val day = cycle?.let(CalendarDay::parse) ?: return null
        return id?.let { AppRoute.Completion(it, day) }
    }

    /** `ready/<situation>[/<uuid>]`: a trip may name a member; a sale or a claim must name its section. */
    private fun readiness(situation: String?, id: UUID?): AppRoute? =
        when (ReadinessSituation.entries.firstOrNull { it.raw == situation }) {
            ReadinessSituation.TRIP -> AppRoute.Readiness(ReadinessRoute.Trip(id))
            ReadinessSituation.SALE -> id?.let { AppRoute.Readiness(ReadinessRoute.Sale(it)) }
            ReadinessSituation.CLAIM -> id?.let { AppRoute.Readiness(ReadinessRoute.Claim(it)) }
            null -> null
        }

    private fun parts(route: AppRoute): Pair<String, List<String>> = when (route) {
        AppRoute.Home -> "home" to emptyList()
        AppRoute.Upcoming -> "upcoming" to emptyList()
        AppRoute.Search -> "search" to emptyList()
        AppRoute.Agenda -> "agenda" to emptyList()
        AppRoute.Intake -> "intake" to emptyList()
        is AppRoute.AddVisit -> "visit" to listOf(text(route.assetId))
        is AppRoute.Asset -> "asset" to listOf(text(route.id))
        is AppRoute.Obligation -> "obligation" to listOf(text(route.id))
        is AppRoute.Completion -> "complete" to listOf(text(route.obligationId), route.cycle.isoString)
        is AppRoute.HistoryEntry -> "history" to listOf(text(route.id))
        is AppRoute.Provider -> "provider" to listOf(text(route.id))
        is AppRoute.Document -> "document" to listOf(text(route.id))
        is AppRoute.Category -> "category" to listOf(route.key)
        is AppRoute.Settings -> "settings" to listOfNotNull(route.section?.raw)
        is AppRoute.Readiness -> "ready" to readinessParts(route.route)
    }

    private fun readinessParts(route: ReadinessRoute): List<String> = when (route) {
        is ReadinessRoute.Trip -> listOfNotNull(ReadinessSituation.TRIP.raw, route.holderID?.let(::text))
        is ReadinessRoute.Sale -> listOf(ReadinessSituation.SALE.raw, text(route.assetID))
        is ReadinessRoute.Claim -> listOf(ReadinessSituation.CLAIM.raw, text(route.assetID))
    }

    private fun text(id: UUID): String = id.toString().lowercase(Locale.ROOT)

    /** A UUID written as one, 8-4-4-4-12 hex digits, as the iPhone reads it: never a shortened form. */
    private fun uuid(text: String): UUID? = if (UUID_TEXT.matches(text)) UUID.fromString(text) else null

    private val UUID_TEXT = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
}
