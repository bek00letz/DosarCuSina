package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.NamedChoice
import com.ar.dosarcusina.core.values.option
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/** A file of shared/travel/ that this build can't read: a build's fault, never the person's binder's. */
class TravelError(message: String) : IllegalStateException(message)

/**
 * What a traveller carries, the countries and the document types' travel data, as the iOS app
 * exports them to shared/travel/ (ios/DosarCuSinaTests/TravelExportTests.swift): read whole, or
 * not at all. The readiness checks read these and never name a country, a document rule or a key
 * of their own.
 */
class TravelData(
    val rules: TravelRules,
    val citizenship: Citizenship,
    val documents: DocumentTypes,
    val keys: ReadinessKeys,
) {
    /** The files it is read from, by name, as shared/travel/ holds them. */
    enum class File(val fileName: String) {
        RULES("rules.json"),
        COUNTRIES("countries.json"),
        DOCUMENTS("documents.json"),
    }

    companion object {
        private const val RESOURCES = "/com/ar/dosarcusina/core/readiness/"

        /** The travel data this build carries, read once. */
        val builtIn: TravelData by lazy { read(::resource) }

        /** A file this build carries, as text. */
        fun resource(file: File): String {
            val stream = TravelData::class.java.getResourceAsStream(RESOURCES + file.fileName)
                ?: throw TravelError("${file.fileName} isn't in the build: travelResources copies shared/travel/")
            return stream.use { it.readBytes().decodeToString() }
        }

        /** The travel data in the files [text] gives, by file. */
        fun read(text: (File) -> String): TravelData {
            val rules = parse(text, File.RULES)
            val keys = ReadinessKeys.read(rules.obj("reads"))
            val documents = DocumentTypes.read(parse(text, File.DOCUMENTS))
            val citizenship = Citizenship.read(parse(text, File.COUNTRIES), keys)
            return TravelData(TravelRules.read(rules, citizenship), citizenship, documents, keys)
        }

        private fun parse(text: (File) -> String, file: File): JsonObject =
            MachineText.parseOrNull(text(file)) as? JsonObject
                ?: throw TravelError("${file.fileName} isn't a JSON object")
    }
}

// Reading the files

internal fun JsonObject.obj(key: String): JsonObject =
    this[key] as? JsonObject ?: throw TravelError("$key isn't an object")

internal fun JsonObject.list(key: String): JsonArray = this[key] as? JsonArray ?: throw TravelError("$key isn't a list")

internal fun JsonObject.string(key: String): String =
    (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw TravelError("$key isn't text")

internal fun JsonObject.stringOrNull(key: String): String? {
    val value = this[key]?.takeUnless { it is JsonNull } ?: return null
    return (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw TravelError("$key isn't text")
}

internal fun JsonObject.int(key: String): Int =
    (this[key] as? JsonPrimitive)?.intOrNull ?: throw TravelError("$key isn't a whole number")

internal fun JsonObject.bool(key: String): Boolean =
    (this[key] as? JsonPrimitive)?.booleanOrNull ?: throw TravelError("$key isn't true or false")

internal fun JsonObject.strings(key: String): List<String> = list(key).map { it.text(key) }

internal fun JsonElement.obj(context: String): JsonObject =
    this as? JsonObject ?: throw TravelError("an entry of $context isn't an object")

internal fun JsonElement.text(context: String): String =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw TravelError("an entry of $context isn't text")

internal fun JsonObject.day(key: String): CalendarDay? =
    stringOrNull(key)?.let { CalendarDay.parse(it) ?: throw TravelError("$key isn't a day") }

/**
 * The keys the readiness checks read, as the iOS app's constants name them (shared/travel/rules.json's
 * `reads`, keys.json's shape): never a key written in Kotlin. `:catalog`'s tests check them against
 * shared/catalog/keys.json.
 */
class ReadinessKeys(private val reads: Map<String, Map<String, String>>) {
    /** The key the Swift constant [type].[name] names. */
    fun of(type: String, name: String): String =
        reads[type]?.get(name) ?: throw TravelError("rules.json's reads has no $type.$name")

    /** Every key read, by type and name, as written. */
    val all: Map<String, Map<String, String>> get() = reads

    val expiry = of("DocumentFields", "expiry")
    val nationality = of("DocumentFields", "nationality")
    val documentPlate = of("DocumentFields", "vehiclePlate")
    val personalNumber = of("DocumentFields", "personalNumber")
    val plate = of("VehicleFields", "plate")
    val civ = of("VehicleFields", "civ")
    val vin = of("VehicleFields", "vin")
    val petPassport = of("PetFields", "passport")
    val citizenship = of("MemberFields", "citizenship")
    val bonusMalus = of("MemberFields", "bonusMalus")
    val vehicleRCA = of("BuiltInBlueprints", "vehicleRCA")
    val vehicleITP = of("BuiltInBlueprints", "vehicleITP")
    val vehicleVignette = of("BuiltInBlueprints", "vehicleVignette")
    val vehicleCASCO = of("BuiltInBlueprints", "vehicleCASCO")
    val homePAD = of("BuiltInBlueprints", "homePAD")
    val homeInsurance = of("BuiltInBlueprints", "homeInsurance")
    val petRabies = of("BuiltInBlueprints", "petRabies")
    val healthEUCard = of("BuiltInBlueprints", "healthEUCard")
    val vehicle = of("BuiltInTemplates.Key", "vehicle")
    val pet = of("BuiltInTemplates.Key", "pet")
    val idCard = of("DocumentType", "idCard")
    val passport = of("DocumentType", "passport")
    val residencePermit = of("DocumentType", "residencePermit")
    val drivingLicence = of("DocumentType", "drivingLicence")
    val euHealthCard = of("DocumentType", "euHealthCard")
    val greenCard = of("DocumentType", "greenCard")
    val insurance = of("ObligationKind", "insurance")
    val tax = of("ObligationKind", "tax")
    val payment = of("ObligationKind", "payment")
    val invoice = of("DocumentKind", "invoice")
    val policy = of("DocumentKind", "policy")
    val insurer = of("BlueprintFactRole", "insurer")
    val policyNumber = of("BlueprintFactRole", "policyNumber")
    val claimsPhone = of("BlueprintFactRole", "claimsPhone")
    val policyholder = of("BlueprintFactRole", "policyholder")

    companion object {
        fun read(reads: JsonObject): ReadinessKeys = ReadinessKeys(
            reads.mapValues { (type, names) -> names.obj(type).mapValues { (name, key) -> key.text("$type.$name") } },
        )
    }
}

/**
 * What a personal document can be, as the iOS app's `DocumentType`
 * (ios/DosarCuSina/Models/Fields/ChoiceOptions.swift), read once for the whole app from
 * shared/travel/documents.json: each type's key, name and other spellings (a type stored as a label
 * by an earlier version is still its type) and its travel margin; its variants, with the name a
 * document of the variant takes and what makes it no travel document; and what the app declares on
 * the types as data: what a document of no known type is called, which keep a back, how long one
 * is valid after it is issued, which are read only on the phone and which are shared with care.
 * The readiness checks and the section actions (a document's name, its validity after issue) both
 * read it here; no code asks for a type by name.
 */
// The iOS type's surface, one function per question, and the file's parts, one per rule.
@Suppress("TooManyFunctions", "LongParameterList")
class DocumentTypes(
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
        val travelMarginDays: Int,
    ) : NamedChoice

    data class Variant(
        val type: String,
        override val key: String,
        val travels: Boolean,
        val travelEnds: CalendarDay?,
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

    /** A document's type, from its values. */
    fun type(values: ReadinessValues): String? = key(values.text(typeField))

    /** How long before its expiry a document stops being good for travel, from its values (its type's). */
    fun travelMarginDays(values: ReadinessValues): Int = travelMarginDays(values.text(typeField))

    /** How long before its expiry a document of the type [text] names stops being good for travel; 0 when never. */
    fun travelMarginDays(text: String?): Int = types.firstOrNull { it.key == key(text) }?.travelMarginDays ?: 0

    private fun variant(values: ReadinessValues): Variant? =
        values.text(variantField)?.let { key -> variants.firstOrNull { it.key == key } }

    /** Whether a document can be travelled with at all (not the simple identity card). */
    fun travels(values: ReadinessValues): Boolean = variant(values)?.travels ?: true

    /** The last day a document is good for travel by its kind, when its kind has one. */
    fun travelEnd(values: ReadinessValues): CalendarDay? = variant(values)?.travelEnds

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
    fun documentName(typeText: String?, variantText: String?): String? {
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

        fun read(json: JsonObject): DocumentTypes = DocumentTypes(
            typeField = json.string("typeField"),
            variantField = json.string("variantField"),
            types = json.list("types").map { it.obj("types") }.map {
                Type(it.string("key"), it.string("label"), it.strings("aliases"), it.int("travelMarginDays"))
            },
            variants = json.list("variants").map { it.obj("variants") }.map {
                val name = it.stringOrNull("documentName")
                val label = it.string("label")
                Variant(it.string("type"), it.string("key"), it.bool("travels"), it.day("travelEnds"), name, label)
            },
            unnamed = json.string("unnamed"),
            keepsBack = json.strings("keepsBackSide").toSet(),
            validityMonthsAfterIssue = json.obj("validityMonthsAfterIssue").keys.associateWith {
                json.obj("validityMonthsAfterIssue").int(it)
            },
            readOnPhoneOnly = json.strings("readOnPhoneOnly").toSet(),
            sharedWithCare = json.strings("sharedWithCare").toSet(),
        )
    }
}
