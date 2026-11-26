package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ChoiceText
import com.ar.dosarcusina.core.values.MachineText
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
 * The document types as the checks read them, as the iOS app's `DocumentType`: each type's key,
 * name and other spellings (a type stored as a label by an earlier version is still its type),
 * its travel margin, and the kinds (variants) that are no travel document or stop being one.
 */
class DocumentTypes(
    /** The field that holds a document's type, and the one that holds its variant. */
    val typeField: String,
    val variantField: String,
    val types: List<Type>,
    val variants: List<Variant>,
) {
    data class Type(val key: String, val label: String, val aliases: List<String>, val travelMarginDays: Int)

    data class Variant(val type: String, val key: String, val travels: Boolean, val travelEnds: CalendarDay?)

    /** The type a stored text names: its key, or a label an earlier version stored. */
    fun key(text: String?): String? {
        text ?: return null
        val type = types.firstOrNull { it.key == text }
            ?: types.firstOrNull { ChoiceText.names(text, it.key, it.label, it.aliases) }
        return type?.key
    }

    /** A document's type, from its values. */
    fun type(values: ReadinessValues): String? = key(values.text(typeField))

    /** How long before its expiry a document stops being good for travel, from its values (its type's). */
    fun travelMarginDays(values: ReadinessValues): Int =
        types.firstOrNull { it.key == type(values) }?.travelMarginDays ?: 0

    private fun variant(values: ReadinessValues): Variant? =
        values.text(variantField)?.let { key -> variants.firstOrNull { it.key == key } }

    /** Whether a document can be travelled with at all (not the simple identity card). */
    fun travels(values: ReadinessValues): Boolean = variant(values)?.travels ?: true

    /** The last day a document is good for travel by its kind, when its kind has one. */
    fun travelEnd(values: ReadinessValues): CalendarDay? = variant(values)?.travelEnds

    companion object {
        fun read(json: JsonObject): DocumentTypes = DocumentTypes(
            typeField = json.string("typeField"),
            variantField = json.string("variantField"),
            types = json.list("types").map { it.obj("types") }.map {
                Type(it.string("key"), it.string("label"), it.strings("aliases"), it.int("travelMarginDays"))
            },
            variants = json.list("variants").map { it.obj("variants") }.map {
                Variant(it.string("type"), it.string("key"), it.bool("travels"), it.day("travelEnds"))
            },
        )
    }
}
