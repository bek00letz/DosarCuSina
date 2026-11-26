package com.ar.dosarcusina.ui.shell

import com.ar.dosarcusina.core.readiness.ReadinessRoute
import com.ar.dosarcusina.core.values.CalendarDay
import java.util.UUID

/** One of every route the app can open, with fixed ids, for the shell's tests. */
internal object Routes {
    val asset: UUID = id("asset")
    val obligation: UUID = id("obligation")
    val entry: UUID = id("entry")
    val provider: UUID = id("provider")
    val document: UUID = id("document")
    val member: UUID = id("member")
    val cycle: CalendarDay = CalendarDay(2026, 12, 1)

    /** Every route, each kind at least once (the readiness ones in each of their forms). */
    val all: List<AppRoute> = listOf(
        AppRoute.Home,
        AppRoute.Upcoming,
        AppRoute.Search,
        AppRoute.Intake,
        AppRoute.Agenda,
        AppRoute.Asset(asset),
        AppRoute.AddVisit(asset),
        AppRoute.Obligation(obligation),
        AppRoute.Completion(obligation, cycle),
        AppRoute.HistoryEntry(entry),
        AppRoute.Provider(provider),
        AppRoute.Document(document),
        AppRoute.Category("vehicle"),
        AppRoute.Settings(),
        AppRoute.Settings(SettingsSection.BACKUP),
        AppRoute.Readiness(ReadinessRoute.Trip(null)),
        AppRoute.Readiness(ReadinessRoute.Trip(member)),
        AppRoute.Readiness(ReadinessRoute.Sale(asset)),
        AppRoute.Readiness(ReadinessRoute.Claim(asset)),
    )

    /** The same id for the same name, every run. */
    private fun id(name: String): UUID = UUID.nameUUIDFromBytes(name.toByteArray())
}
