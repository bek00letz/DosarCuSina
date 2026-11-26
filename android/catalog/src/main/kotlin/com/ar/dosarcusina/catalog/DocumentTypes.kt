package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.NamedChoice
import com.ar.dosarcusina.core.values.option
import java.util.UUID

/**
 * What a personal document can be, as the iOS app's `DocumentType`
 * (ios/DosarCuSina/Models/Fields/ChoiceOptions.swift), read from the shared catalog's
 * `documents.json`: its types in the order they are offered, their variants (each offered only
 * for its type) and the names they give, and what the types declare as data (a back worth
 * keeping, a validity after issue, a travel margin). No code asks for a type by name: it asks
 * here.
 */
// The iOS type's surface, one function per question, and the file's parts, one per rule.
@Suppress("TooManyFunctions", "LongParameterList")
class DocumentTypes internal constructor(
    /** The field that holds the type, which variants depend on (`document.type`). */
    val typeFieldKey: String,
    /** The field that holds the variant (`document.variant`). */
    val variantFieldKey: String,
    /** The types, in the order they are offered. */
    val types: List<Type>,
    /** Every variant, each of one type, in order. */
    val variants: List<Variant>,
    /** What a document is called when its type isn't one this build knows. */
    val unnamed: String,
    private val keepsBack: Set<String>,
    private val validityMonthsAfterIssue: Map<String, Int>,
    private val travelMargins: Map<String, Int>,
    private val readOnPhoneOnly: Set<String>,
    private val sharedWithCare: Set<String>,
) {
    /** A type of document: its stored key, its label and what else it is found by. */
    data class Type(override val key: String, override val label: String, override val aliases: List<String>) :
        NamedChoice

    /** A variant of [type]: its option and, when it differs from the type's, the name the document takes. */
    data class Variant(
        val type: String,
        override val key: String,
        override val label: String,
        val documentName: String?,
    ) : NamedChoice {
        override val aliases: List<String> get() = emptyList()
    }

    /** The type [text] names: its key, or a label stored by an earlier version. */
    fun type(text: String?): Type? = text?.let { types.option(it) }

    /** The document's name for a type: "Carte de identitate", "Pașaport". */
    fun label(type: String): String? = type(type)?.label

    /** The variants of one type, in order. */
    fun variants(of: String): List<Variant> = variants.filter { it.type == of }

    /** The types that have variants, so the variant question appears only for them. */
    val typesWithVariants: List<String> get() = variants.map { it.type }.distinct()

    /** What the document is called: the variant's own name ("Cazier fiscal"), else the type's. */
    fun documentName(type: String, variant: String?): String {
        val spec = variant?.let { key -> variants.firstOrNull { it.type == type && it.key == key } }
        return spec?.documentName ?: label(type) ?: unnamed
    }

    /**
     * What a personal document with [values] is called by its type and variant ("Carte de
     * identitate", "Cazier judiciar"), when it has a type this build knows
     * (`AssetActions.documentName`).
     */
    fun documentName(values: FieldValues): String? {
        val type = type(values[typeFieldKey]?.textValue)?.key ?: return null
        val variant = values[variantFieldKey]?.textValue?.let { text -> variants.option(text)?.key }
        return documentName(type, variant)
    }

    /**
     * Whether a document of this type (its key, or a label stored by an earlier version) has a back
     * worth adding. A document with no type yet counts as "Alt document"; never a bank card.
     */
    fun keepsBackSide(type: String?): Boolean {
        if (type.isNullOrEmpty()) return OTHER in keepsBack
        val key = type(type)?.key ?: return false
        return key in keepsBack
    }

    /** The months a document of this type and variant is valid after it is issued, if a rule says so. */
    fun validityMonths(type: String?, variant: String?): Int? {
        val key = type(type)?.key ?: return null
        val ownVariant = variant?.takeIf { v -> variants.any { it.type == key && it.key == v } }
        return ownVariant?.let(validityMonthsAfterIssue::get) ?: validityMonthsAfterIssue[key]
    }

    /** Whether a type is dated by the day it was issued: the type, or one of its variants, has a validity from it. */
    fun isDatedByIssue(type: String?): Boolean {
        val key = type(type)?.key ?: return false
        return key in validityMonthsAfterIssue || variants(of = key).any { it.key in validityMonthsAfterIssue }
    }

    /** The last day a document issued on [issued] is valid by its rule: the same day, its months later. */
    fun validUntil(issued: CalendarDay, type: String?, variant: String?): CalendarDay? =
        validityMonths(type, variant)?.let { issued.addingMonths(it) }

    /** How long before its printed expiry a type stops being good for travel, in days; 0 when it never does. */
    fun travelMarginDays(type: String?): Int = type(type)?.key?.let(travelMargins::get) ?: 0

    /** The travel margin of a document from its values: its type's (a variant has its type's). */
    fun travelMarginDays(values: FieldValues): Int = travelMarginDays(values[typeFieldKey]?.textValue)

    /** Whether a type is read only on the phone, never sent to the person's AI provider. */
    fun isReadOnPhoneOnly(type: String?): Boolean = type(type)?.key?.let { it in readOnPhoneOnly } ?: false

    /** Whether sending a type's picture says to send it only to someone the person trusts. */
    fun isSharedWithCare(type: String?): Boolean = type(type)?.key?.let { it in sharedWithCare } ?: false

    companion object {
        /** "Alt document": what a document with no type yet counts as. */
        const val OTHER = "documentType.other"
    }
}

/**
 * „Recuperate”, the category of one's own the repair list keeps records in whose section was
 * deleted on another device, as the iOS app's `LostRecordsStep` makes it: one key and one
 * section id on every device and on both apps, so two that keep records there make one.
 */
data class RecoveredCategory(
    val key: String,
    val name: String,
    val symbol: String,
    /** `SectionPocket` keys, as stored. */
    val pockets: List<String>,
    /** The id of its one section. */
    val sectionID: UUID,
)
