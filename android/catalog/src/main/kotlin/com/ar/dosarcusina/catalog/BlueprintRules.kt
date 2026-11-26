package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.Condition
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.core.values.CalendarDay
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * What one of a category's usual deadlines says about the deadline made from it, as the iOS app's
 * `ObligationBlueprint` (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift and
 * DueDayValidity.swift): whether it applies to a section's values, the reminders it gives for
 * them, whether a first day is worth scheduling, and the note it starts with. The deadline actions
 * read these when they make a deadline; nothing decides them twice.
 */
object BlueprintRules {
    private const val RENEWAL = "renewal"
    private const val LEGAL = "legal"

    /** Whether [blueprint] applies to a section with [values] (`appliesWhen`): always, unless its rule says not. */
    fun applies(blueprint: ObligationBlueprint, values: FieldValues): Boolean =
        blueprint.appliesWhen?.let(Condition::read)?.isMet(values) ?: true

    /**
     * The reminders a deadline from [blueprint] gives for a section with [values]
     * (`reminders(for:)`): the variant for the value its `reminderVariants` reads (a passport, a
     * dog), else its own, else its kind's ([defaultProfile]).
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
     * (`isWorthScheduling(on:today:values:)`): a day still to come, or a renewal the law asks
     * for, which is worth knowing about even once it has passed (an expired identity card).
     */
    fun isWorthScheduling(
        blueprint: ObligationBlueprint,
        day: CalendarDay,
        today: CalendarDay,
        values: FieldValues,
    ): Boolean = day >= today || (blueprint.kind == RENEWAL && reminders(blueprint, values).consequence == LEGAL)

    /**
     * The section's field a deadline from [blueprint] is first due by, with its offset in days, when
     * its first day comes from one (`FirstDueRule.field`): a document's renewal by its expiry.
     */
    fun firstDueField(blueprint: ObligationBlueprint): FieldDay? {
        val rule = blueprint.firstDue as? JsonObject ?: return null
        if ((rule["type"] as? JsonPrimitive)?.content != "field") return null
        val key = (rule["field"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        val offset = (rule["offsetDays"] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toIntOrNull() ?: 0
        return FieldDay(key, offset)
    }

    /** A first day taken from a section's date field, shifted by [offsetDays]. */
    data class FieldDay(val field: String, val offsetDays: Int)

    /** Whether a deadline from [blueprint] repeats (`RecurrenceRule.repeats`): a rule this build can't read doesn't. */
    fun repeats(blueprint: ObligationBlueprint): Boolean =
        when (blueprint.recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None) {
            RecurrenceRule.None, is RecurrenceRule.Unreadable -> false
            else -> true
        }

    /**
     * The note a deadline from [blueprint] starts with (`deadlineNote`): its own, except a service's
     * of a category of one's own, whose note only says how often, which the deadline's page says anyway.
     */
    fun deadlineNote(blueprint: ObligationBlueprint): String? =
        if (CategorySwitches.isServiceBlueprint(blueprint.key)) null else blueprint.note

    /**
     * The deadlines a new section of a category with [fields] and [blueprints] would start with,
     * for a section with [values] on [today]: each that applies, with its first day worked out when
     * its rule can, ticked by the one rule ([PlannedObligation.startsSelected]). The values are
     * read as saving would keep them ([FieldRules.applying]).
     */
    fun planned(
        fields: List<FieldDefinition>,
        blueprints: List<ObligationBlueprint>,
        values: FieldValues,
        today: CalendarDay,
        documentTypes: DocumentTypes,
    ): List<PlannedObligation> {
        val kept = FieldRules.applying(values, fields, previous = null, documentTypes = documentTypes)
        return blueprints.filter { applies(it, kept) }.map { blueprint ->
            val firstDue = RecurrenceEngine.firstDue(blueprint, kept, today)
            PlannedObligation(blueprint, firstDue, PlannedObligation.startsSelected(blueprint, firstDue))
        }
    }
}

/**
 * A deadline the add flow is about to make, as the iOS app's `PlannedObligation`
 * (ios/DosarCuSina/Services/Obligations/AssetActions.swift): a blueprint and its first day, ticked
 * or not.
 */
data class PlannedObligation(
    val blueprint: ObligationBlueprint,
    /** None while the person still has to pick it. */
    val firstDue: CalendarDay?,
    val isSelected: Boolean,
    /**
     * Whether its first day had to be asked when it was planned: nothing the section says works it
     * out (the current ITP's expiry). Such a deadline starts unticked.
     */
    val asksFirstDate: Boolean = firstDue == null,
) {
    /** The blueprint's key: one planned deadline per blueprint. */
    val id: String get() = blueprint.key

    companion object {
        /**
         * Ticked at first: a deadline the category suggests, once its first day is worked out (from
         * a field, an interval after today, its next fixed date). One whose day must be asked starts
         * unticked, so making a section never stops on dates; the person may still tick it and give
         * its day. The one rule for every category, by the blueprint's first day, never by a category.
         */
        fun startsSelected(blueprint: ObligationBlueprint, firstDue: CalendarDay?): Boolean =
            blueprint.isSuggested && firstDue != null
    }
}
