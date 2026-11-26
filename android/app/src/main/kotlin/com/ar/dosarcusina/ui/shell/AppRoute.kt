package com.ar.dosarcusina.ui.shell

import com.ar.dosarcusina.core.readiness.ReadinessRoute
import com.ar.dosarcusina.core.values.CalendarDay
import java.util.UUID

/**
 * Every place the app can be opened to, the same set as the iPhone app's `AppRoute`
 * (ios/DosarCuSina/Navigation/AppRoute.swift). Reminders, widgets, links, the share inbox and
 * in-app links all speak this one type, and go through [ShellRouter.open].
 */
sealed interface AppRoute {
    /** The Dosar tab: the grid of section boxes. */
    data object Home : AppRoute

    /** The Urmează tab: what comes up next. */
    data object Upcoming : AppRoute

    /** The Caută tab. */
    data object Search : AppRoute

    /** The Adaugă tab: scan or add something. */
    data object Intake : AppRoute

    /** The Agendă box: people and firms. */
    data object Agenda : AppRoute

    /** A section's page (VW Golf 2018, Apartament, PawPaw). */
    data class Asset(val id: UUID) : AppRoute

    /** Logging a visit (service, repair, check-up) on a section. */
    data class AddVisit(val assetId: UUID) : AppRoute

    /** A deadline's page. */
    data class Obligation(val id: UUID) : AppRoute

    /**
     * „Am rezolvat” for one deadline, over its page, for the cycle the person saw: where a
     * reminder's „Am rezolvat” lands when closing asks what only the app can ask.
     */
    data class Completion(val obligationId: UUID, val cycle: CalendarDay) : AppRoute

    data class HistoryEntry(val id: UUID) : AppRoute

    data class Provider(val id: UUID) : AppRoute

    data class Document(val id: UUID) : AppRoute

    /** A box that groups a category (Acte, Garanții, Abonamente), by its template key. */
    data class Category(val key: String) : AppRoute

    /** Settings, at one of its places or its first page. */
    data class Settings(val section: SettingsSection? = null) : AppRoute

    /** A situation's checklist: a trip, selling the car, a claim. */
    data class Readiness(val route: ReadinessRoute) : AppRoute

    /** The lock the route's screen opens behind ([RouteLock]), declared for every route. */
    val lock: RouteLock
        get() = when (this) {
            Home, Upcoming, Search, Intake, Agenda, is Settings -> RouteLock.Open
            is Asset -> RouteLock.Section(id)
            is AddVisit -> RouteLock.Section(assetId)
            is Obligation, is Completion, is HistoryEntry, is Document, is Provider, is Category, is Readiness ->
                RouteLock.DrawnByItsScreen
        }
}

/**
 * A place in Settings a link can open (`dosarcusina://settings/<section>`), as the iPhone app's
 * `SettingsSection`. [raw] is link text and never changes.
 */
enum class SettingsSection(val raw: String) {
    NOTIFICATIONS("notifications"),

    /** Protecție: the phone's lock for the app and for categories. */
    PRIVACY("privacy"),

    /** Ecranul Dosar: which categories show, their boxes, the person's own categories. */
    CATEGORIES("categories"),

    /** Copii de siguranță: backups and the room documents take. */
    BACKUP("backup"),
    EXAMPLES("examples"),

    /** The repair list: data an earlier version saved wrongly, waiting for an OK. */
    REPAIRS("repairs"),

    /** Citire cu AI: the optional service that reads documents better. */
    AI("ai"),
    ABOUT("about"),
    ;

    companion object {
        fun of(raw: String?): SettingsSection? = entries.firstOrNull { it.raw == raw }
    }
}
