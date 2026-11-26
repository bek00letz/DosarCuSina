package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.RecurrenceEngine
import com.ar.dosarcusina.catalog.completionKind
import com.ar.dosarcusina.core.deadlines.CompletionKind
import com.ar.dosarcusina.core.deadlines.CompletionShape
import com.ar.dosarcusina.core.deadlines.DueDayValidity
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.urgency.ReminderProfile
import com.ar.dosarcusina.core.urgency.UrgencyRule
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptBlueprints
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.reminders
import java.time.ZoneId
import com.ar.dosarcusina.store.schema.dueDay as storedDueDay

// A deadline as the rules read it, over its stored columns (schema/KeptValues.kt), as the iOS
// `Obligation`'s computed properties (ObligationModel.swift, DeadlineCompletion.swift,
// CycleReminders.swift, DueDayValidity.swift): its kind and status, how it repeats, what closing it
// asks, and its reminders as this cycle uses them.

/** Where the deadline stands, as stored. */
val Obligation.status: ObligationStatus get() = ObligationStatus.stored(statusRaw)

/** What kind of duty it is; a kind a newer build wrote reads as the loudest and stays stored as it was. */
val Obligation.kind: ObligationKind get() = ObligationKind.stored(kindRaw)

/** How it repeats; a rule this build can't read behaves as one-off and stays stored as written. */
val Obligation.recurrence: RecurrenceRule get() = keptRecurrence.value

/**
 * The day it is due, where the phone is ([zone]): its stored day, else (one that can't be read) the
 * day it was made, as the iOS `dueDay`.
 */
fun Obligation.dueDay(zone: ZoneId): CalendarDay = storedDueDay ?: CalendarDay.of(createdAt, zone)

/**
 * A deadline the person wrote themselves ("Alt termen"), not one of its category's usual ones: its name
 * and importance are theirs to change. A category's deadline keeps the name and kind its blueprint gives.
 */
val Obligation.isPersonsOwn: Boolean get() = blueprintKey == null

/** The counter unit of a deadline counted by a counter, such as kilometres. */
val Obligation.metricUnit: MeasurementUnit?
    get() = (recurrence as? RecurrenceRule.Metric)?.let { MeasurementUnit.of(it.unit) }

/** Whether this deadline is still valid on [day] (an RCA on the day of a trip): [DueDayValidity]'s rule. */
fun Obligation.isValid(day: CalendarDay, zone: ZoneId): Boolean = DueDayValidity.isValid(dueDay(zone), day)

/**
 * Its reminders as this cycle uses them ([ReminderProfile.forCycle]: a lead longer than how it repeats is
 * left out): what reminders, urgency, Urmează, the widget and the page read. The stored profile
 * ([reminders]) is what the person edits.
 */
fun Obligation.cycleReminders(zone: ZoneId): ReminderProfile {
    val due = dueDay(zone)
    return reminders.rule.forCycle(RecurrenceEngine.cycleStart(due, recurrence), due)
}

/** The one urgency rule for this deadline, from the reminders of its cycle. */
fun Obligation.urgencyRule(zone: ZoneId): UrgencyRule = cycleReminders(zone).urgencyRule

/**
 * What completing one deadline asks, found once for every screen that completes it, as the iOS app's
 * `Obligation.completionKind(template:)` (ios/DosarCuSina/Services/Obligations/DeadlineCompletion.swift):
 * what its blueprint states, in its section's category's [blueprints] or the household's
 * ([household]), else, for a deadline of one's own, what its kind gives ([CompletionKind.own]). Never
 * decide it from the kind where a blueprint states it.
 */
fun Obligation.completionKind(
    blueprints: List<ObligationBlueprint>,
    household: List<ObligationBlueprint> = Catalog.builtIn.household.blueprints,
): CompletionKind {
    val key = blueprintKey ?: return CompletionKind.own(kind)
    return (blueprints + household).firstOrNull { it.key == key }?.completionKind ?: CompletionKind.own(kind)
}

/** What completing it asks, in its section's category's [blueprints]. */
fun Obligation.completion(blueprints: List<ObligationBlueprint>): CompletionShape = completionKind(blueprints).shape

/** The history kind closing it writes ([HistoryKind.forCompleting]): its completion kind's record. */
fun Obligation.completionHistoryKind(blueprints: List<ObligationBlueprint>): HistoryKind =
    HistoryKind.forCompleting(completionKind(blueprints))

/**
 * The binder's deadlines as the rules read them: a deadline's section's category, and its usual
 * deadlines, as kept in the binder.
 */
object DeadlineCategory {
    /**
     * The category of the section [obligation] is in, as kept in the binder: the first by row with its
     * key (`TemplateStore.template(forKey:)`); none for a deadline of no section, or whose category's
     * record isn't there.
     */
    fun of(view: BinderView, obligation: Obligation): CategoryTemplate? {
        val asset = obligation.asset?.let { view.row(Tables.assets, it) } ?: return null
        return view.all(Tables.templates).firstOrNull { it.key == asset.templateKey }
    }

    /** The usual deadlines of [obligation]'s section's category; none when there is no category. */
    fun blueprints(view: BinderView, obligation: Obligation): List<ObligationBlueprint> =
        of(view, obligation)?.keptBlueprints?.items.orEmpty()

    /** The blueprint [obligation] was made from, in its section's category; none for one of the person's own. */
    fun blueprint(view: BinderView, obligation: Obligation): ObligationBlueprint? {
        val key = obligation.blueprintKey ?: return null
        return blueprints(view, obligation).firstOrNull { it.key == key }
    }

    /** What completing [obligation] asks, its category read from [view]. */
    fun completionKind(view: BinderView, obligation: Obligation): CompletionKind =
        obligation.completionKind(blueprints(view, obligation))
}
