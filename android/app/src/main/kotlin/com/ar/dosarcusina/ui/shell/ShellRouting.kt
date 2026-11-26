package com.ar.dosarcusina.ui.shell

import com.ar.dosarcusina.core.readiness.ReadinessRoute
import com.ar.dosarcusina.core.values.CalendarDay
import java.util.UUID

/** The four tabs, as the iPhone app's `AppTab`: Dosar, Urmează, Adaugă, Caută. Setări opens from Dosar. */
enum class AppTab {
    DOSAR,
    UPCOMING,
    ADD,
    SEARCH,
}

/**
 * What a route or a sheet shows or writes, as far as the section locks go, as the iPhone app's
 * `RouteLock`. Every route ([AppRoute.lock]) and every sheet ([ShellSheet.lock]) declares one in a
 * `when` of its own, so a new one can't leave it out, and the shell draws each through
 * [RouteLockGate], wherever it came from: a tap, a reminder, a widget, a link.
 */
sealed interface RouteLock {
    /** Nothing of one section: a tab, Settings, the people and firms. */
    data object Open : RouteLock

    /** Shows or writes into this section: drawn only while its category is open. */
    data class Section(val assetId: UUID) : RouteLock

    /**
     * One record of a section, or what several sections hold: its screen finds the section by the
     * same answer and draws a locked state of its own that names nothing of it.
     */
    data object DrawnByItsScreen : RouteLock

    /**
     * A record that names no section that can be found: its own lock can't be known, so it is
     * drawn only while nothing of the binder is locked or the session is open. Locks fail closed.
     */
    data object UnknownSection : RouteLock
}

/** What adding a section starts from: the whole catalog, or one category under a parent. */
data class AddSectionRequest(
    /** The section the new one is filed under. */
    val parentId: UUID? = null,
    /** Skips the catalog and starts with this category. */
    val templateKey: String? = null,
) {
    companion object {
        val TopLevel = AddSectionRequest()
    }
}

/** The sheets the shell presents over whatever tab is showing, as the iPhone app's `ShellSheet`. */
sealed interface ShellSheet {
    data class Settings(val section: SettingsSection? = null) : ShellSheet

    data class AddVisit(val assetId: UUID) : ShellSheet

    data class AddSection(val request: AddSectionRequest) : ShellSheet

    /** A new document for a household member; without a holder (the Acte box) the photo names them. */
    data class AddPersonalDocument(val holderId: UUID?) : ShellSheet

    /** Any document of a member's, from their page's one „Adaugă un document”: capture decides where it goes. */
    data class AddDocument(val holderId: UUID) : ShellSheet

    /** „Am rezolvat” for one deadline at the cycle the person saw, asked from outside the app. */
    data class Completion(val obligationId: UUID, val cycle: CalendarDay) : ShellSheet

    /** The section the sheet writes into, behind its lock; a new top-level section reveals nothing. */
    val lock: RouteLock
        get() = when (this) {
            is Settings -> RouteLock.Open
            is AddVisit -> RouteLock.Section(assetId)
            is AddSection -> request.parentId?.let(RouteLock::Section) ?: RouteLock.Open
            is AddPersonalDocument -> holderId?.let(RouteLock::Section) ?: RouteLock.Open
            is AddDocument -> RouteLock.Section(holderId)
            // Its section is found from the deadline, by the same answer.
            is Completion -> RouteLock.DrawnByItsScreen
        }
}

/** Where a route lands: a tab, the screens pushed on it, and maybe a sheet on top. */
data class ShellRoutePlan(val tab: AppTab, val path: List<AppRoute>, val sheet: ShellSheet? = null) {
    /** Every lock the plan opens behind, the pushed screens' and the sheet's, in order. */
    val locks: List<RouteLock> get() = path.map { it.lock } + listOfNotNull(sheet?.lock)
}

/**
 * The one mapping from an [AppRoute] (a reminder, a widget, a link, a search result) to the place
 * it opens, as the iPhone app's `ShellRouting.plan`. Pure, so it is tested.
 */
object ShellRouting {
    fun plan(route: AppRoute): ShellRoutePlan = when (route) {
        AppRoute.Home -> ShellRoutePlan(AppTab.DOSAR, emptyList())
        AppRoute.Upcoming -> ShellRoutePlan(AppTab.UPCOMING, emptyList())
        AppRoute.Search -> ShellRoutePlan(AppTab.SEARCH, emptyList())
        AppRoute.Intake -> ShellRoutePlan(AppTab.ADD, emptyList())
        is AppRoute.Asset -> ShellRoutePlan(AppTab.DOSAR, listOf(route))
        is AppRoute.AddVisit ->
            ShellRoutePlan(AppTab.DOSAR, listOf(AppRoute.Asset(route.assetId)), ShellSheet.AddVisit(route.assetId))
        is AppRoute.Obligation -> ShellRoutePlan(AppTab.UPCOMING, listOf(route))
        // Over the deadline's page, which is there once the sheet closes.
        is AppRoute.Completion -> ShellRoutePlan(
            AppTab.UPCOMING,
            listOf(AppRoute.Obligation(route.obligationId)),
            ShellSheet.Completion(route.obligationId, route.cycle),
        )
        is AppRoute.HistoryEntry, is AppRoute.Document, is AppRoute.Category ->
            ShellRoutePlan(AppTab.DOSAR, listOf(route))
        AppRoute.Agenda -> ShellRoutePlan(AppTab.DOSAR, listOf(AppRoute.Agenda))
        is AppRoute.Provider -> ShellRoutePlan(AppTab.DOSAR, listOf(AppRoute.Agenda, route))
        is AppRoute.Settings -> ShellRoutePlan(AppTab.DOSAR, emptyList(), ShellSheet.Settings(route.section))
        is AppRoute.Readiness -> readiness(route)
    }

    /** Over the section it belongs to; a trip for the household opens over Urmează. */
    private fun readiness(route: AppRoute.Readiness): ShellRoutePlan {
        val assetId = when (val readiness = route.route) {
            is ReadinessRoute.Trip -> readiness.holderID
            is ReadinessRoute.Sale -> readiness.assetID
            is ReadinessRoute.Claim -> readiness.assetID
        }
        return if (assetId != null) {
            ShellRoutePlan(AppTab.DOSAR, listOf(AppRoute.Asset(assetId), route))
        } else {
            ShellRoutePlan(AppTab.UPCOMING, listOf(route))
        }
    }

    /** The routes that are a tab's own first screen or a sheet, never pushed on a tab. */
    fun isPushed(route: AppRoute): Boolean = when (route) {
        AppRoute.Home, AppRoute.Upcoming, AppRoute.Search, AppRoute.Intake -> false
        is AppRoute.Settings, is AppRoute.Completion -> false
        else -> true
    }
}
