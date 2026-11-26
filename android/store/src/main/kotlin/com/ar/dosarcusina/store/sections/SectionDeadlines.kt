package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.BlueprintRules
import com.ar.dosarcusina.catalog.RecurrenceEngine
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.repairs.StoredKinds
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import com.ar.dosarcusina.store.schema.withKeptReminders
import java.time.Instant

/** A deadline was asked for without the first day its blueprint needs (the current ITP's expiry). */
class MissingFirstDueDate(val blueprintKey: String) :
    IllegalArgumentException("The deadline needs its first day: $blueprintKey")

/**
 * A section's deadline made from one of its category's blueprints, as the iOS app's
 * `HouseholdMutations.makeObligation` (ios/DosarCuSina/Services/Obligations/AssetActions.swift):
 * what making a section and editing one need. It saves nothing: it records the deadline in the
 * step it is given.
 *
 * This is the one place a section's deadline is made from a blueprint until the deadline actions
 * (`ObligationActions.create`, Phase 3) bring theirs, which this then calls, never beside it.
 */
internal object SectionDeadlines {
    /**
     * Makes the deadline [blueprint] gives the section [asset] (as [step] has it), first due on
     * [firstDue], else on the day its rule works out on [today]; throws [MissingFirstDueDate] when
     * neither gives one. A deadline repeating by a counter is due at the section's counter now plus
     * its step. Made at [now], an example when its section is.
     */
    @Suppress("LongParameterList") // The iOS function's parts.
    fun make(
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
            ?: throw MissingFirstDueDate(blueprint.key)
        val recurrence = blueprint.recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None
        val reminders = BlueprintRules.reminders(blueprint, values)
        val dueMetric = (recurrence as? RecurrenceRule.Metric)?.let { rule ->
            currentMetric(step, asset, builtIns)?.let { it + rule.every }
        }
        val obligation = Obligation(
            title = blueprint.title,
            kindRaw = StoredKinds.kind(blueprint.kind),
            dueDayISO = StoredDay.text(due),
            dueMetric = dueMetric,
            estimatedCostAmount = blueprint.estimatedCost?.amount,
            estimatedCostCurrency = blueprint.estimatedCost?.currency,
            blueprintKey = blueprint.key,
            notes = BlueprintRules.deadlineNote(blueprint),
            isExample = asset.isExample,
            createdAt = now,
            updatedAt = now,
            asset = asset.pk,
        ).withKeptRecurrence(KeptObject.made(recurrence, RecurrenceRule.codec))
            .withKeptReminders(KeptObject.made(reminders, ReminderProfile.codec))
        return step.insert(obligation)
    }

    /**
     * The section's counter (`HouseholdMutations.currentMetric`): the last reading of the cleaned
     * series of its newest counter reading's unit, else its hero field's value, by its category's
     * definition as kept, else the catalog's.
     */
    fun currentMetric(view: BinderView, asset: Asset, builtIns: BuiltIns): Double? {
        val counters = HouseholdReadings.readings(view, asset.pk)
            .filter { MeasurementKind.stored(it.kindRaw).isCumulative }
        val unit = counters.maxByOrNull { it.recordedAt }?.let { MeasurementUnit.of(it.unit) }
        val fromReadings = unit?.let { HouseholdReadings.readingSeries(view, asset.pk, it).current }
        if (fromReadings != null) return fromReadings
        val kept = view.all(Tables.templates).firstOrNull { it.key == asset.templateKey }
        val fields = kept?.keptSections?.items?.flatMap { it.fields }
            ?: builtIns.definition(asset.templateKey)?.sections?.flatMap { it.fields }.orEmpty()
        return HeroMetric.value(asset.keptValues.value, fields)
    }
}
