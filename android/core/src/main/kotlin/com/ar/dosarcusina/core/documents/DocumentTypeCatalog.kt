package com.ar.dosarcusina.core.documents

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.NamedChoice
import com.ar.dosarcusina.core.values.option
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/** A shared/catalog/documents/documents.json this build can't read: a build's fault, never the binder's. */
class DocumentTypeCatalogError(message: String) : IllegalStateException(message)

/**
 * What a personal document can be, as the iOS app's `DocumentType`
 * (ios/DosarCuSina/Models/Fields/ChoiceOptions.swift) declares it once: exported by its tests to
 * shared/catalog/documents/documents.json (`DocumentCatalogExportTests`), copied into this module's
 * resources as it is built, and read here, the one copy for the whole app. Each type's key, name and
 * other spellings (a type stored as a label by an earlier version is still its type); its variants,
 * with the name a document of the variant takes; and what the app declares on the types as data:
 * what a document of no known type is called, which keep a back, how long one is valid after it is
 * issued, which are read only on the phone and which are shared with care.
 *
 * The section actions (a document's name, its validity after issue), the field rules and the trip
 * check (which type a document is) read it here; a type's travel data is the trip check's own
 * (`core.readiness.DocumentTypes`, from shared/travel/). No code asks for a type by name.
 */
// The iOS type's surface, one function per question, and the file's parts, one per rule.
@Suppress("TooManyFunctions", "LongParameterList")
class DocumentTypeCatalog(
    /** The field that holds a document's type, and the one that holds its variant. */
    val typeField: String,
    val variantField: String,
    val types: List<Type>,
    val variants: List<Variant>,
    /** What a document is called when its type isn't one this build knows. */
    val unnamed: String = "",
    private val keepsBack: Set<String> = emptySet(),
    private val validityMonthsAfterIssue: Map<String, Int> = emptyMap(),
    private val readOnPhoneOnly: Set<String> = emptySet(),
    private val sharedWithCare: Set<String> = emptySet(),
) {
    data class Type(
        override val key: String,
        override val label: String,
        override val aliases: List<String>,
    ) : NamedChoice

    data class Variant(
        val type: String,
        override val key: String,
        /** The name a document of this variant takes when it isn't its type's ("Cazier fiscal"). */
        val documentName: String? = null,
        /** How the variant is offered, which a variant stored as text by an earlier version may be. */
        override val label: String = "",
    ) : NamedChoice {
        override val aliases: List<String> get() = emptyList()
    }

    /** The type a stored text names: its key, or a label an earlier version stored. */
    fun key(text: String?): String? {
        text ?: return null
        return types.option(text)?.key
    }

    /** The document's name for a type: "Carte de identitate", "Pașaport". */
    fun label(text: String): String? = key(text)?.let { key -> types.first { it.key == key }.label }

    /** The variants of a type, in order. */
    fun variants(of: String): List<Variant> = variants.filter { it.type == of }

    /** What the document is called: the variant's own name ("Cazier fiscal"), else the type's, else [unnamed]. */
    fun documentName(type: String, variant: String?): String {
        val spec = variant?.let { key -> variants.firstOrNull { it.type == type && it.key == key } }
        return spec?.documentName ?: label(type) ?: unnamed
    }

    /**
     * What a document whose type field holds [typeText] and whose variant field holds [variantText]
     * is called ("Carte de identitate", "Cazier judiciar"), when its type is one this build knows
     * (`AssetActions.documentName`).
     */
    fun nameFromFields(typeText: String?, variantText: String?): String? {
        val type = key(typeText) ?: return null
        val variant = variantText?.let { variants.option(it)?.key }
        return documentName(type, variant)
    }

    /**
     * Whether a document of the type [text] names has a back worth adding. One with no type yet counts
     * as "Alt document"; never a bank card, whose back shows the security code.
     */
    fun keepsBackSide(text: String?): Boolean {
        if (text.isNullOrEmpty()) return OTHER in keepsBack
        return key(text)?.let { it in keepsBack } ?: false
    }

    /** The months a document of this type and variant is valid after it is issued, if a rule says so. */
    fun validityMonths(type: String?, variant: String?): Int? {
        val key = key(type) ?: return null
        val own = variant?.takeIf { text -> variants.any { it.type == key && it.key == text } }
        return own?.let(validityMonthsAfterIssue::get) ?: validityMonthsAfterIssue[key]
    }

    /** Whether a type is dated by the day it was issued: the type, or one of its variants, has a validity from it. */
    fun isDatedByIssue(type: String?): Boolean {
        val key = key(type) ?: return false
        return key in validityMonthsAfterIssue || variants(of = key).any { it.key in validityMonthsAfterIssue }
    }

    /** The last day a document issued on [issued] is valid by its rule: the same day, its months later. */
    fun validUntil(issued: CalendarDay, type: String?, variant: String?): CalendarDay? =
        validityMonths(type, variant)?.let { issued.addingMonths(it) }

    /** Whether a type is read only on the phone, never sent to the person's AI provider. */
    fun isReadOnPhoneOnly(type: String?): Boolean = key(type)?.let { it in readOnPhoneOnly } ?: false

    /** Whether sending a type's picture says to send it only to someone the person trusts. */
    fun isSharedWithCare(type: String?): Boolean = key(type)?.let { it in sharedWithCare } ?: false

    companion object {
        /** "Alt document": what a document with no type yet counts as. */
        private const val OTHER = "documentType.other"

        private const val FILE = "documents.json"
        private const val RESOURCE = "/com/ar/dosarcusina/core/documents/$FILE"

        /** The document types this build carries, read once. */
        val builtIn: DocumentTypeCatalog by lazy {
            val stream = DocumentTypeCatalog::class.java.getResourceAsStream(RESOURCE)
                ?: fail("$FILE isn't in the build: the core module copies shared/catalog/documents/")
            read(stream.use { it.readBytes().decodeToString() })
        }

        /** The document types in [text], as `documents.json` writes them; read whole, or not at all. */
        fun read(text: String): DocumentTypeCatalog {
            val json = MachineText.parseOrNull(text) as? JsonObject ?: fail("$FILE isn't a JSON object")
            val validity = json.obj("validityMonthsAfterIssue")
            return DocumentTypeCatalog(
                typeField = json.string("typeField"),
                variantField = json.string("variantField"),
                types = json.objects("types").map { Type(it.string("key"), it.string("label"), it.strings("aliases")) },
                variants = json.objects("variants").map {
                    Variant(it.string("type"), it.string("key"), it.stringOrNull("documentName"), it.string("label"))
                },
                unnamed = json.string("unnamed"),
                keepsBack = json.strings("keepsBackSide").toSet(),
                validityMonthsAfterIssue = validity.keys.associateWith(validity::int),
                readOnPhoneOnly = json.strings("readOnPhoneOnly").toSet(),
                sharedWithCare = json.strings("sharedWithCare").toSet(),
            )
        }
    }
}

// Reading the file

private fun fail(message: String): Nothing = throw DocumentTypeCatalogError(message)

private fun JsonObject.obj(key: String): JsonObject = this[key] as? JsonObject ?: fail("$key isn't an object")

private fun JsonObject.objects(key: String): List<JsonObject> =
    (this[key] as? JsonArray ?: fail("$key isn't a list")).map {
        it as? JsonObject ?: fail("an entry of $key isn't an object")
    }

private fun JsonObject.string(key: String): String = this[key].text() ?: fail("$key isn't text")

private fun JsonObject.stringOrNull(key: String): String? {
    val value = this[key]?.takeUnless { it is JsonNull } ?: return null
    return value.text() ?: fail("$key isn't text")
}

private fun JsonObject.strings(key: String): List<String> =
    (this[key] as? JsonArray ?: fail("$key isn't a list")).map { it.text() ?: fail("an entry of $key isn't text") }

private fun JsonObject.int(key: String): Int =
    (this[key] as? JsonPrimitive)?.intOrNull ?: fail("$key isn't a whole number")

private fun JsonElement?.text(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
