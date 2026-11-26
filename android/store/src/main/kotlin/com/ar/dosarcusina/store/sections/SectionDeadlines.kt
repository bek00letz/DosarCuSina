package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.CategorySwitches
import com.ar.dosarcusina.catalog.RecurrenceEngine
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.repairs.StoredKinds
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptReminders
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import com.ar.dosarcusina.store.schema.withKeptReminders
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

/** A deadline was asked for without the first day its blueprint needs (the current ITP's expiry). */
class MissingFirstDueDate(val blueprintKey: String) :
    IllegalArgumentException("The deadline needs its first day: $blueprintKey")

/**
 * What a section's actions need of its deadlines, as the iOS app's `HouseholdMutations.makeObligation`,
 * `currentMetric` and `DeadlineReminders.follow` (ios/DosarCuSina/Services/Obligations/AssetActions.swift
 * and DeadlineReminders.swift), with the blueprint's own rules they read (`reminders(for:)`,
 * `isWorthScheduling`, `deadlineNote`, `kind.defaultProfile`). It saves nothing: it records in the step it
 * is given.
 *
 * A seam, kept private to the section actions: the deadline engine and actions (`ObligationActions`,
 * `DeadlineMutations`, `DeadlineReminders` and the blueprint's rules, Phase 3) bring the one public home of
 * each of these, which this then calls instead, never beside it.
 */
// One function per rule the section actions read of a deadline.
@Suppress("TooManyFunctions")
internal object SectionDeadlines {
    private const val RENEWAL = "renewal"
    private const val LEGAL = "legal"

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
            notes = deadlineNote(blueprint),
            isExample = asset.isExample,
            createdAt = now,
            updatedAt = now,
            asset = asset.pk,
        ).withKeptRecurrence(KeptObject.made(recurrence, RecurrenceRule.codec))
            .withKeptReminders(KeptObject.made(reminders(blueprint, values), ReminderProfile.codec))
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

    // The blueprint's own rules

    /**
     * The reminders a deadline from [blueprint] gives for a section with [values] (`reminders(for:)`):
     * the variant for the value its `reminderVariants` reads (a passport, a dog), else its own, else its
     * kind's ([defaultProfile]).
     */
    fun reminders(blueprint: ObligationBlueprint, values: FieldValues): ReminderProfile {
        val variants = blueprint.reminderVariants as? JsonObject
        val field = (variants?.get("field") as? JsonPrimitive)?.takeIf { it.isString }?.content
        val value = field?.let { values[it]?.textValue }
        val variant = value?.let { (variants["variants"] as? JsonObject)?.get(it) }?.let(ReminderProfile.codec::decode)
        return variant ?: blueprint.reminders?.let(ReminderProfile.codec::decode) ?: defaultProfile(blueprint.kind)
    }

    /**
     * The reminders of a kind of deadline when its blueprint says none (`ObligationKind.defaultProfile`);
     * a kind a newer build wrote reads as the loudest, legal.
     */
    @Suppress("MagicNumber") // The iOS kinds' profiles, as data.
    fun defaultProfile(kind: String): ReminderProfile = when (kind) {
        "tax" -> ReminderProfile(listOf(14, 1), "financial")
        "insurance" -> ReminderProfile(listOf(30, 7, 0), LEGAL)
        "health" -> ReminderProfile(listOf(7, 1), "health", graceDays = 7)
        RENEWAL -> ReminderProfile(listOf(60, 30), LEGAL)
        "payment" -> ReminderProfile(listOf(2, 0), "financial")
        "maintenance" -> ReminderProfile(listOf(14, 1), "comfort", graceDays = 14)
        "routine" -> ReminderProfile(listOf(0), "comfort", graceDays = 3)
        else -> ReminderProfile(listOf(30, 7, 0), LEGAL)
    }

    /**
     * Whether a deadline from [blueprint] first due on [day] is worth making on [today]
     * (`isWorthScheduling(on:today:values:)`): a day still to come, or a renewal the law asks for,
     * worth knowing about even once it has passed (an expired identity card).
     */
    fun isWorthScheduling(blueprint: ObligationBlueprint, day: CalendarDay, today: CalendarDay, values: FieldValues) =
        day >= today || (blueprint.kind == RENEWAL && reminders(blueprint, values).consequence == LEGAL)

    /** The note a deadline starts with (`deadlineNote`): its own, except a service's of a category of one's own. */
    fun deadlineNote(blueprint: ObligationBlueprint): String? =
        if (CategorySwitches.isServiceBlueprint(blueprint.key)) null else blueprint.note

    /** A first day taken from a section's date field, shifted by [offsetDays] (`FirstDueRule.field`). */
    data class FieldDay(val field: String, val offsetDays: Int)

    /** The section's field a deadline from [blueprint] is first due by, when its first day comes from one. */
    fun firstDueField(blueprint: ObligationBlueprint): FieldDay? {
        val rule = blueprint.firstDue as? JsonObject ?: return null
        if ((rule["type"] as? JsonPrimitive)?.content != "field") return null
        val key = (rule["field"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        val offset = (rule["offsetDays"] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toIntOrNull() ?: 0
        return FieldDay(key, offset)
    }

    /** Whether a deadline from [blueprint] repeats (`RecurrenceRule.repeats`): a rule this build can't read doesn't. */
    fun repeats(blueprint: ObligationBlueprint): Boolean =
        when (blueprint.recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None) {
            RecurrenceRule.None, is RecurrenceRule.Unreadable -> false
            else -> true
        }

    // Reminders that follow the section

    /**
     * After the section in row [asset] had its values changed from [previous] to [values], in [step]
     * (`DeadlineReminders.follow`): each of its deadlines whose blueprint gives another profile for the
     * new values takes it whole; one whose reminders the person set keeps its own, with only the
     * document's travel margin, a fact about the document. Done and archived ones, and values the
     * profile doesn't read, change nothing.
     */
    fun followReminders(
        step: Step,
        asset: Long,
        blueprints: List<ObligationBlueprint>,
        previous: FieldValues,
        values: FieldValues,
    ) {
        val byKey = LinkedHashMap<String, ObligationBlueprint>()
        for (blueprint in blueprints) byKey.putIfAbsent(blueprint.key, blueprint)
        val running = setOf(ObligationStatus.ACTIVE, ObligationStatus.PAUSED)
        val deadlines = step.pointingAt(Tables.obligations, "asset", asset)
            .mapNotNull { step.row(Tables.obligations, it) }
            .filter { ObligationStatus.stored(it.statusRaw) in running }
        for (obligation in deadlines) {
            val blueprint = obligation.blueprintKey?.let(byKey::get)
                ?.takeIf { reminders(it, previous) != reminders(it, values) } ?: continue
            val usual = reminders(blueprint, values)
            val own = obligation.reminders
            val margin = usual.travelMarginDays
            val profile = if (!obligation.remindersCustomized) {
                usual
            } else {
                ReminderProfile(own.leadDays, own.consequence, own.graceDays, own.followUpAfterLapse, margin)
            }
            val given = obligation.withKeptReminders(obligation.keptReminders.replacingValue(profile))
            if (own != profile) step.update(given)
        }
    }
}
