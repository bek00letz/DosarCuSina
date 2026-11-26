package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.core.deadlines.missedCyclesStayOwed
import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.catalog.CategorySwitches
import com.ar.dosarcusina.catalog.RecurrenceContext
import com.ar.dosarcusina.catalog.RecurrenceEngine
import com.ar.dosarcusina.catalog.SeriesStep
import com.ar.dosarcusina.catalog.remindersFor
import com.ar.dosarcusina.core.deadlines.CompletionShape
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.history.cycleDueDay
import com.ar.dosarcusina.store.history.nextDueDay
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.readings.PlannedSectionReading
import com.ar.dosarcusina.store.readings.kind
import com.ar.dosarcusina.store.readings.measurementUnit
import com.ar.dosarcusina.store.repairs.RepairReading
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import com.ar.dosarcusina.store.schema.withKeptReminders
import com.ar.dosarcusina.archive.v3.ReminderProfile as StoredReminders
import java.time.Instant
import java.time.ZoneId

/**
 * The counter a completion reads („Am rezolvat” on an oil change), as the iOS app's
 * `ObligationActions.Counter`: the one the deadline counts on (every 15.000 km), else its section's own
 * (a car's kilometres); none when there is none. The sheet asks it by [title] (the section's own name for
 * it, else the unit's), and the reading is recorded in [unit]: the same counter either way.
 */
data class DeadlineCounter(val title: String, val unit: MeasurementUnit)

/**
 * The building blocks of the deadline actions that don't save, as the deadline part of the iOS app's
 * `HouseholdMutations` (ios/DosarCuSina/Services/Obligations/AssetActions.swift): making a deadline from
 * a blueprint, what the engine knows of its section, its counter. The actions that save
 * ([ObligationActions], and the section actions when they make a section's deadlines) call these inside
 * their own step, never a second copy.
 */
object DeadlineMutations {
    /**
     * Makes a deadline from [blueprint] for [asset] in [step]: due on [firstDue], else by the blueprint's
     * own rule on [today] (throws [ObligationActionError.MissingFirstDueDate] when it asks for a day),
     * reminding as the blueprint says for the section's values, its rule and its note the blueprint's (a
     * service's rule is no note), an example when the section is one, and due at the counter it counts to.
     */
    @Suppress("LongParameterList") // What a new deadline is made from, as the iOS building block takes it.
    fun makeObligation(
        step: Step,
        blueprint: ObligationBlueprint,
        asset: Asset,
        firstDue: CalendarDay?,
        today: CalendarDay,
        now: Instant,
        builtIns: BuiltIns,
    ): Obligation {
        val values = asset.keptValues.value
        val due = firstDue ?: RecurrenceEngine.firstDue(blueprint, values, today)
            ?: throw ObligationActionError.MissingFirstDueDate(blueprint.key)
        val rule = blueprint.recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None
        val counter = (rule as? RecurrenceRule.Metric)?.let { metric ->
            currentMetric(step, asset, builtIns)?.let { it + metric.every }
        }
        val made = Obligation(
            title = blueprint.title,
            kindRaw = blueprint.kind,
            dueDayISO = StoredDay.text(due),
            dueMetric = counter,
            blueprintKey = blueprint.key,
            notes = blueprint.note.takeUnless { CategorySwitches.isServiceBlueprint(blueprint.key) },
            estimatedCostAmount = blueprint.estimatedCost?.amount,
            estimatedCostCurrency = blueprint.estimatedCost?.currency,
            isExample = asset.isExample,
            asset = asset.pk,
            createdAt = now,
            updatedAt = now,
        ).withKeptRecurrence(KeptObject.made(rule, RecurrenceRule.codec))
            .withKeptReminders(KeptObject.made(blueprint.remindersFor(values), StoredReminders.codec))
        return step.insert(made)
    }

    /**
     * What the engine knows when [obligation] moves to its next cycle: its section's values and counter
     * readings, the counter now ([currentMetric], else the last reading, else the section's hero value),
     * the day of the month its series keeps, and whether each cycle is money still owed. Only completions
     * that moved the date take part (not the one being recorded now).
     */
    fun recurrenceContext(
        view: BinderView,
        obligation: Obligation,
        currentMetric: Double?,
        zone: ZoneId,
        builtIns: BuiltIns,
    ): RecurrenceContext {
        val steps = HistoryActions.history(view, obligation).filter { it.nextDueDay != null }
            .map { SeriesStep(it.cycleDueDay, it.nextDueDay) }
        // Only a series counted from its due dates keeps a day of the month, and only its own steps count.
        val rule = obligation.recurrence
        val seriesDay = (rule as? RecurrenceRule.Interval)?.takeIf { it.anchor == DUE_DATE }?.let {
            RecurrenceEngine.seriesStart(obligation.dueDay(zone), steps, RecurrenceEngine.interval(it)).day
        }
        val owed = obligation.kind.missedCyclesStayOwed
        val asset = obligation.asset?.let { view.row(Tables.assets, it) }
            ?: return RecurrenceContext(
                currentMetric = currentMetric, seriesDayOfMonth = seriesDay, missedCyclesStayOwed = owed,
            )
        val readings = HouseholdReadings.readingSeries(view, asset.pk, obligation.metricUnit).readings
        return RecurrenceContext(
            assetValues = asset.keptValues.value,
            readings = readings,
            currentMetric = currentMetric ?: readings.lastOrNull()?.metric ?: currentMetric(view, asset, builtIns),
            seriesDayOfMonth = seriesDay,
            missedCyclesStayOwed = owed,
        )
    }

    /** The section's counter: the last reading of the cleaned series of its newest counter, else its hero value. */
    fun currentMetric(view: BinderView, asset: Asset, builtIns: BuiltIns): Double? {
        val counters = HouseholdReadings.readings(view, asset.pk).filter { it.kind.isCumulative }
        val newest = counters.maxByOrNull { it.recordedAt }
        if (newest != null) {
            HouseholdReadings.readingSeries(view, asset.pk, newest.measurementUnit).current?.let { return it }
        }
        return HeroMetric.value(asset.keptValues.value, fields(view, asset, builtIns))
    }

    /** The fields of [asset]'s category: its record's, else the app's own definition of a built-in. */
    private fun fields(view: BinderView, asset: Asset, builtIns: BuiltIns): List<FieldDefinition> =
        RepairReading.categories(view)[asset.templateKey]?.let(RepairReading::fields)
            ?: builtIns.definition(asset.templateKey)?.sections.orEmpty().flatMap { it.fields }

    /**
     * The counter a completion of [obligation] reads, among its category's [fields]: the one the deadline
     * counts on, else (work on a vehicle, [asks] the section's) the section's hero counter; none for work
     * done at home that repeats by time.
     */
    fun counter(
        obligation: Obligation,
        fields: List<FieldDefinition>,
        asks: CompletionShape.Counter = CompletionShape.Counter.SECTION,
    ): DeadlineCounter? {
        val own = HeroMetric.field(fields)
        val ownUnit = own?.unit?.let(MeasurementUnit::of)
        val counted = obligation.metricUnit
        // Work done at home asks only the counter it counts on: one that repeats by time asks none.
        val section = own?.takeIf { asks == CompletionShape.Counter.SECTION && obligation.asset != null }
        return when {
            counted != null -> DeadlineCounter(own?.takeIf { ownUnit == counted }?.label ?: counted.label, counted)
            section != null && ownUnit != null -> DeadlineCounter(section.label, ownUnit)
            else -> null
        }
    }

    /**
     * The reading „Gata” records with the counter the person read ([metricReading]): on the deadline's
     * section, in its counter's unit ([counter]), at the moment it was done. Planned before the step's unit
     * opens, so the question a lower counter asks comes first.
     */
    fun plannedReading(
        view: BinderView,
        metricReading: Double?,
        obligation: Obligation,
        at: Instant,
    ): PlannedSectionReading? {
        if (metricReading == null) return null
        val asset = obligation.asset?.let { view.row(Tables.assets, it) } ?: return null
        val unit = counter(obligation, HeroMetric.categoryFields(view, asset))?.unit ?: obligation.metricUnit
        return HouseholdReadings.plan(view, asset.pk, metricReading, at, ReadingSource.PERSON, unit)
    }

    /** The anchor of a series counted from its due dates. */
    private const val DUE_DATE = "dueDate"
}
