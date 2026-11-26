package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.documents.DocumentTypeCatalog
import com.ar.dosarcusina.core.values.CalendarDay
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
        val builtIn: TravelData by lazy { read(text = ::resource) }

        /** A file this build carries, as text. */
        fun resource(file: File): String {
            val stream = TravelData::class.java.getResourceAsStream(RESOURCES + file.fileName)
                ?: throw TravelError("${file.fileName} isn't in the build: travelResources copies shared/travel/")
            return stream.use { it.readBytes().decodeToString() }
        }

        /** The travel data in the files [text] gives, by file, for the document types [catalog] declares. */
        fun read(catalog: DocumentTypeCatalog = DocumentTypeCatalog.builtIn, text: (File) -> String): TravelData {
            val rules = parse(text, File.RULES)
            val keys = ReadinessKeys.read(rules.obj("reads"))
            val documents = DocumentTypes.read(parse(text, File.DOCUMENTS), catalog)
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
 * The document types' travel data, as the iOS app declares it (`DocumentType.travelMargins`,
 * `TravelRules.notForTravel` and `travelEnds`), read from shared/travel/documents.json: each type's
 * travel margin, and for each variant whether it travels at all and the last day it is good for
 * travel. What the types are (their keys, names, variants and the app's other rules on them) is the
 * catalog's, [catalog] ([DocumentTypeCatalog], from shared/catalog/documents/), which says which type
 * a document's values name; this holds only what a trip asks of it. The two files list the same keys.
 */
class DocumentTypes(
    /** What the types are: the one copy, the catalog's. */
    val catalog: DocumentTypeCatalog,
    /** Each type's travel margin in days, by its key. */
    private val travelMargins: Map<String, Int>,
    /** Each variant's travel data, by its key. */
    private val variants: Map<String, VariantTravel>,
) {
    /** Whether a variant can be travelled with at all (not the simple identity card), and until when. */
    data class VariantTravel(val travels: Boolean, val travelEnds: CalendarDay?)

    /** A document's type, from its values. */
    fun type(values: ReadinessValues): String? = catalog.key(values.text(catalog.typeField))

    /** How long before its expiry a document stops being good for travel, from its values (its type's). */
    fun travelMarginDays(values: ReadinessValues): Int = travelMarginDays(values.text(catalog.typeField))

    /** How long before its expiry a document of the type [text] names stops being good for travel; 0 when never. */
    fun travelMarginDays(text: String?): Int = catalog.key(text)?.let(travelMargins::get) ?: 0

    private fun variant(values: ReadinessValues): VariantTravel? = values.text(catalog.variantField)?.let(variants::get)

    /** Whether a document can be travelled with at all (not the simple identity card). */
    fun travels(values: ReadinessValues): Boolean = variant(values)?.travels ?: true

    /** The last day a document is good for travel by its kind, when its kind has one. */
    fun travelEnd(values: ReadinessValues): CalendarDay? = variant(values)?.travelEnds

    companion object {
        /**
         * The travel data in [json] for the types [catalog] declares: every type and variant the
         * catalog has, and no other, or the two exports are out of step.
         */
        fun read(json: JsonObject, catalog: DocumentTypeCatalog): DocumentTypes {
            val margins = json.list("types").map { it.obj("types") }.associate {
                it.string("key") to it.int("travelMarginDays")
            }
            val variants = json.list("variants").map { it.obj("variants") }.associate {
                it.string("key") to VariantTravel(it.bool("travels"), it.day("travelEnds"))
            }
            sameKeys("types", margins.keys, catalog.types.map { it.key })
            sameKeys("variants", variants.keys, catalog.variants.map { it.key })
            return DocumentTypes(catalog, margins, variants)
        }

        private fun sameKeys(part: String, travel: Set<String>, declared: List<String>) {
            if (travel != declared.toSet()) {
                throw TravelError("documents.json's $part aren't the catalog's: ${travel.toSortedSet()} and $declared")
            }
        }
    }
}
