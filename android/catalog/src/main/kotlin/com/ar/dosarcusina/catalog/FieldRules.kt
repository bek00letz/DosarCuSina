package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.ChoiceKeys
import com.ar.dosarcusina.archive.v3.ChoiceOption
import com.ar.dosarcusina.archive.v3.Condition
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.documents.DocumentTypeCatalog
import com.ar.dosarcusina.core.subscriptions.SubscriptionGroup
import com.ar.dosarcusina.core.values.option
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The rules a section's values follow as they are saved, as the iOS app's
 * `FieldValues.applyingRules(of:previous:calendar:)` and `normalizingChoices(for:)`
 * (ios/DosarCuSina/Models/Fields/FieldValue.swift), with `FieldDerivation`
 * (ios/DosarCuSina/Models/Fields/FieldDefinition.swift): the one way a form's values become what
 * is kept, for a new section and an edit alike.
 */
object FieldRules {
    /** How many times values that no longer belong are taken out, so one that depended on a dropped one goes too. */
    private const val PASSES = 2

    /**
     * Choice fields stored as option keys: display text written before keys existed maps to its key,
     * text no option recognizes is kept as written (`normalizingChoices`).
     */
    fun normalizingChoices(values: FieldValues, fields: List<FieldDefinition>): FieldValues =
        ChoiceKeys.normalizing(values, fields)

    /**
     * [values] with defaults filled in for empty fields (a new section only: no [previous]), the
     * values that no longer belong taken out (a cazier's variant after the type became a passport;
     * a choice whose option isn't offered for the other values), and derived fields worked out again
     * when one of their inputs changed, or while they are still empty. A derived value the person
     * typed in themselves stays until an input changes, and one given in the same change as its
     * inputs (a contract's printed end date) is kept as given.
     */
    fun applying(
        values: FieldValues,
        fields: List<FieldDefinition>,
        previous: FieldValues?,
        documentTypes: DocumentTypeCatalog,
    ): FieldValues {
        val filled = if (previous == null) withDefaults(values, fields) else values
        return withDerived(withoutWhatNoLongerBelongs(filled, fields), fields, previous, documentTypes)
    }

    /** [values] with each empty field's default (a new section only). */
    private fun withDefaults(values: FieldValues, fields: List<FieldDefinition>): FieldValues {
        var result = values
        for (field in fields.filter { values[it.key] == null }) {
            val default = field.defaultValue?.let(FieldValue::read) ?: continue
            result = result.with(field.key, default)
        }
        return result
    }

    /**
     * [values] without what no longer belongs: a field whose condition isn't met, a choice whose option
     * isn't offered for the other values. Twice, so a value that depended on a dropped one goes too.
     */
    private fun withoutWhatNoLongerBelongs(values: FieldValues, fields: List<FieldDefinition>): FieldValues {
        var result = values
        repeat(PASSES) {
            for (field in fields) {
                if (!belongs(field, result)) result = result.with(field.key, null)
            }
        }
        return result
    }

    private fun belongs(field: FieldDefinition, values: FieldValues): Boolean {
        val key = (values[field.key] as? FieldValue.Text)?.value
        val option = key?.takeIf { field.type == FieldDefinition.CHOICE }?.let { field.options?.option(it) }
        return field.applies(values) && (option == null || isOffered(option, values))
    }

    /** [values] with each derived field worked out again when an input changed, or while it is empty. */
    private fun withDerived(
        values: FieldValues,
        fields: List<FieldDefinition>,
        previous: FieldValues?,
        documentTypes: DocumentTypeCatalog,
    ): FieldValues {
        var result = values
        for (field in fields) {
            val derivation = derivation(field) ?: continue
            val inputsChanged = previous?.let { old -> derivation.inputs(documentTypes).any { old[it] != result[it] } }
                ?: true
            val givenNow = previous?.let { it[field.key] != result[field.key] } ?: (result[field.key] != null)
            val worksOut = result[field.key] == null || (inputsChanged && !givenNow)
            derivation.value(result, documentTypes)?.takeIf { worksOut }?.let { result = result.with(field.key, it) }
        }
        return result
    }

    /** Whether [option] is offered for [values]: always, unless its condition says otherwise. */
    fun isOffered(option: ChoiceOption, values: FieldValues): Boolean =
        option.appliesWhen?.let(Condition::read)?.isMet(values) ?: true

    /** How [field] is worked out from others, when it is and this build reads how. */
    fun derivation(field: FieldDefinition): Derivation? {
        val rule = field.derivation as? JsonObject ?: return null
        fun text(name: String) = (rule[name] as? JsonPrimitive)?.takeIf { it.isString }?.content
        return when (text("type")) {
            "addMonths" -> {
                val date = text("date")
                val months = text("months")
                if (date == null || months == null) null else Derivation.AddMonths(date, months)
            }
            "validityAfterIssue" -> text("date")?.let(Derivation::ValidityAfterIssue)
            "serviceGroup" -> text("service")?.let(Derivation::ServiceGroup)
            else -> null
        }
    }

    /** How a field is worked out from others (`FieldDerivation`). */
    sealed interface Derivation {
        /** The fields it reads. */
        fun inputs(documentTypes: DocumentTypeCatalog): List<String>

        /** Its value for [values]; none when they don't give one. */
        fun value(values: FieldValues, documentTypes: DocumentTypeCatalog): FieldValue?

        /** A date field plus a number of months from another field (a purchase's date and its warranty). */
        data class AddMonths(val dateField: String, val monthsField: String) : Derivation {
            override fun inputs(documentTypes: DocumentTypeCatalog) = listOf(dateField, monthsField)

            override fun value(values: FieldValues, documentTypes: DocumentTypeCatalog): FieldValue? {
                val day = (values[dateField] as? FieldValue.Day)?.value ?: return null
                val months = (values[monthsField] as? FieldValue.Number)?.value ?: return null
                return if (months > 0) FieldValue.Day(day.addingMonths(months.toInt())) else null
            }
        }

        /** A document's last valid day from the day it was issued, when its type and variant have a validity. */
        data class ValidityAfterIssue(val issueField: String) : Derivation {
            override fun inputs(documentTypes: DocumentTypeCatalog) =
                listOf(issueField, documentTypes.typeField, documentTypes.variantField)

            override fun value(values: FieldValues, documentTypes: DocumentTypeCatalog): FieldValue? {
                val issued = (values[issueField] as? FieldValue.Day)?.value ?: return null
                val type = values[documentTypes.typeField]?.textValue
                val variant = values[documentTypes.variantField]?.textValue
                return documentTypes.validUntil(issued, type, variant)?.let(FieldValue::Day)
            }
        }

        /** The group a subscription is listed under, from its service: the person's choice stays until it changes. */
        data class ServiceGroup(val serviceField: String) : Derivation {
            override fun inputs(documentTypes: DocumentTypeCatalog) = listOf(serviceField)

            override fun value(values: FieldValues, documentTypes: DocumentTypeCatalog): FieldValue =
                FieldValue.Text(SubscriptionGroup.of(values[serviceField]?.textValue).key)
        }
    }
}
