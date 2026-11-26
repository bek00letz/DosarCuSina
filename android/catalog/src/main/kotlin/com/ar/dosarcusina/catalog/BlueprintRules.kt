package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.Condition
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.core.documents.DocumentTypeCatalog
import com.ar.dosarcusina.core.values.CalendarDay

/**
 * Which of a category's usual deadlines a new section starts with, as the iOS app's
 * `AssetActions.plannedObligations` (ios/DosarCuSina/Services/Obligations/AssetActions.swift): those
 * that apply to its values, each with its first day worked out when its rule can, ticked by the one
 * rule ([PlannedObligation.startsSelected]). What a deadline made from a blueprint reminds with and
 * when it is worth making are the deadline engine's (`RecurrenceEngine`, the blueprint's own rules).
 */
object BlueprintRules {
    /** Whether [blueprint] applies to a section with [values] (`appliesWhen`): always, unless its rule says not. */
    fun applies(blueprint: ObligationBlueprint, values: FieldValues): Boolean =
        blueprint.appliesWhen?.let(Condition::read)?.isMet(values) ?: true

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
        documentTypes: DocumentTypeCatalog,
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
