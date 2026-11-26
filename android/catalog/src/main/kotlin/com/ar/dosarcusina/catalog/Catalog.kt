package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.binder.BuiltInDefinition
import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.core.values.JsonCodec
import com.ar.dosarcusina.core.values.MachineText
import java.util.UUID
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/**
 * The app's built-in categories, as the iOS app defines them (`BuiltInTemplates`): exported by
 * its tests to `shared/catalog/` (`CatalogExportTests`), copied into this module's resources as
 * it is built, and read here. Android never defines a built-in of its own.
 *
 * Each definition is read with the archive's own codecs, the ones a backup's `templates.json`
 * is read with, and must read whole: the catalog is the app's own, so a part this build can't
 * read is a broken build ([CatalogError]), never something to carry raw.
 */
@Suppress("LongParameterList") // One part per file of the catalog.
class Catalog private constructor(
    /** The catalog's version (`TemplateDefinition.builtInCatalogVersion`): every built-in's. */
    val version: Int,
    override val all: List<BuiltInDefinition>,
    /** Built-in keys of earlier catalogs and the key that replaced each (`warranty` → `purchase`). */
    val replacedKeys: Map<String, String>,
    /** Field keys renamed with a replaced category (`warranty.expiry` → `purchase.warrantyUntil`). */
    val replacedFieldKeys: Map<String, String>,
    /** Built-in keys of earlier catalogs that nothing replaced (`rental`). */
    val retiredKeys: Set<String>,
    /** What a category of one's own is made of besides its switches' answers (`ownCategories.json`). */
    val ownCategories: OwnCategories,
    /** The household's own deadlines, which belong to no section (`household.json`). */
    val household: HouseholdRules,
    /** What a personal document can be: its types, their variants and the names they give (`documents.json`). */
    val documentTypes: DocumentTypes,
) : BuiltIns {
    private val byKey: Map<String, BuiltInDefinition> = all.associateBy(BuiltInDefinition::key)

    override fun definition(key: String): BuiltInDefinition? = byKey[key]

    /** The files this catalog is read from, by name, as `shared/catalog/` holds them. */
    enum class File(val fileName: String) {
        TEMPLATES("templates.json"),
        CATALOG("catalog.json"),
        KEYS("keys.json"),
        OWN_CATEGORIES("ownCategories.json"),
        HOUSEHOLD("household.json"),
        DOCUMENTS("documents.json"),
    }

    companion object {
        private const val RESOURCES = "/com/ar/dosarcusina/catalog/"

        /** The catalog this build carries, read once. */
        val builtIn: Catalog by lazy { read(::resource) }

        /** A file of the catalog this build carries, as text. */
        fun resource(file: File): String {
            val stream = Catalog::class.java.getResourceAsStream(RESOURCES + file.fileName)
                ?: throw CatalogError("${file.fileName} isn't in the build: the catalog task copies shared/catalog/")
            return stream.use { it.readBytes().decodeToString() }
        }

        /** The catalog in the files [text] gives, by file. */
        fun read(text: (File) -> String): Catalog {
            val catalog = parse(text, File.CATALOG).obj(File.CATALOG.fileName)
            val defaults = catalog.list("categories").map { it.obj("categories") }.associate { category ->
                val defaults = Defaults(category.bool("isOnHomeByDefault"), category.bool("isSensitiveByDefault"))
                category.string("key") to defaults
            }
            val templates = parse(text, File.TEMPLATES) as? JsonArray
                ?: throw CatalogError("templates.json isn't a list")
            val definitions = templates.map { element ->
                val template = element.obj(File.TEMPLATES.fileName)
                val key = template.string("key")
                definition(template, defaults[key] ?: Defaults.missing(key))
            }
            val keys = definitions.map(BuiltInDefinition::key)
            catalogCheck(keys == defaults.keys.toList()) { "templates.json lists $keys, catalog.json ${defaults.keys}" }
            val version = catalog.int("builtInVersion")
            for (definition in definitions) {
                catalogCheck(definition.version == version) {
                    "${definition.key} is at version ${definition.version}, the catalog at $version"
                }
            }
            return Catalog(
                version = version,
                all = definitions,
                replacedKeys = catalog.strings("replacedKeys"),
                replacedFieldKeys = catalog.strings("replacedFieldKeys"),
                retiredKeys = catalog.list("retiredKeys").map { it.text("retiredKeys") }.toSet(),
                ownCategories = ownCategories(parse(text, File.OWN_CATEGORIES).obj(File.OWN_CATEGORIES.fileName)),
                household = HouseholdRules(
                    parse(text, File.HOUSEHOLD).obj(File.HOUSEHOLD.fileName)
                        .parts("blueprints", ObligationBlueprint.codec, "household"),
                ),
                documentTypes = documentTypes(parse(text, File.DOCUMENTS).obj(File.DOCUMENTS.fileName)),
            )
        }

        private fun documentTypes(documents: JsonObject): DocumentTypes {
            val types = documents.list("types").map { it.obj("types") }.map { type ->
                val aliases = type.list("aliases").map { it.text("aliases") }
                DocumentTypes.Type(type.string("key"), type.string("label"), aliases)
            }
            val keys = types.map { it.key }.toSet()
            val variants = documents.list("variants").map { it.obj("variants") }.map { variant ->
                val type = variant.string("type")
                catalogCheck(type in keys) { "documents.json has a variant of $type, which is no type" }
                DocumentTypes.Variant(
                    type, variant.string("key"), variant.string("label"), variant["documentName"]?.text("documentName"),
                )
            }
            fun keySet(name: String) = documents.list(name).map { it.text(name) }.toSet()
            fun days(name: String) = (documents[name]?.obj(name) ?: throw CatalogError("$name is missing"))
                .mapValues { (key, value) ->
                    (value as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
                        ?: throw CatalogError("$name.$key isn't a whole number")
                }
            return DocumentTypes(
                typeFieldKey = documents.string("typeFieldKey"),
                variantFieldKey = documents.string("variantFieldKey"),
                types = types,
                variants = variants,
                unnamed = documents.string("unnamed"),
                keepsBack = keySet("keepsBackSide"),
                validityMonthsAfterIssue = days("validityMonthsAfterIssue"),
                travelMargins = days("travelMargins"),
                readOnPhoneOnly = keySet("readOnPhoneOnly"),
                sharedWithCare = keySet("sharedWithCare"),
            )
        }

        private fun ownCategories(own: JsonObject): OwnCategories {
            val fields = LinkedHashMap<CategorySwitches.Counter, FieldDefinition>()
            val services = LinkedHashMap<CategorySwitches.Counter, ObligationBlueprint>()
            for (entry in own.list("counters").map { it.obj("counters") }) {
                val name = entry.string("counter")
                val counter = CategorySwitches.Counter.of(name)
                    ?: throw CatalogError("$name is no counter this build knows")
                entry["field"]?.let { fields[counter] = whole(it, FieldDefinition.codec, "$name.field") }
                val service = entry["service"] ?: throw CatalogError("$name has no service")
                services[counter] = whole(service, ObligationBlueprint.codec, "$name.service")
            }
            val missing = CategorySwitches.Counter.entries.filter { it !in services }
            catalogCheck(missing.isEmpty()) { "ownCategories.json has no service for ${missing.map { it.raw }}" }
            catalogCheck(own.string("counterSectionKey") == CategorySwitches.COUNTER_SECTION_KEY) {
                "ownCategories.json puts the counter in another section"
            }
            val recovered = own["recovered"]?.obj("recovered") ?: throw CatalogError("recovered is missing")
            val sectionID = recovered.string("sectionID")
            return OwnCategories(
                basePockets = own.list("basePockets").map { it.text("basePockets") },
                fields = fields,
                services = services,
                recovered = RecoveredCategory(
                    key = recovered.string("key"),
                    name = recovered.string("name"),
                    symbol = recovered.string("symbol"),
                    pockets = recovered.list("pockets").map { it.text("recovered.pockets") },
                    sectionID = runCatching { UUID.fromString(sectionID) }.getOrNull()
                        ?: throw CatalogError("recovered.sectionID isn't an id"),
                ),
            )
        }

        private fun parse(text: (File) -> String, file: File): JsonElement =
            MachineText.parseOrNull(text(file)) ?: throw CatalogError("${file.fileName} isn't JSON")

        private fun definition(template: JsonObject, defaults: Defaults): BuiltInDefinition {
            val key = template.string("key")
            catalogCheck(template.bool("isBuiltIn")) { "$key isn't marked built-in" }
            return BuiltInDefinition(
                key = key,
                name = template.string("name"),
                summary = template["summary"]?.text("$key.summary"),
                symbol = template.string("symbol"),
                tint = template.string("tint"),
                heroStyle = template.string("heroStyle"),
                version = template.int("version"),
                isOnHomeByDefault = defaults.isOnHome,
                isSensitiveByDefault = defaults.isSensitive,
                sections = template.parts("sections", FieldSection.codec, key),
                blueprints = template.parts("blueprints", ObligationBlueprint.codec, key),
                components = template.parts("components", ComponentDefinition.codec, key),
                pockets = template.list("pockets").map { it.text("$key.pockets") },
                behavior = template["behavior"]?.let { whole(it, CategoryBehavior.codec, "$key.behavior") }
                    ?: CategoryBehavior(),
            )
        }
    }
}

/** The catalog this build carries can't be read: the build is broken, not the person's data. */
class CatalogError(message: String) : IllegalStateException(message)

/** A built-in's defaults, from catalog.json: whether a new install shows it on the binder and locks it. */
private class Defaults(val isOnHome: Boolean, val isSensitive: Boolean) {
    companion object {
        fun missing(key: String): Nothing = throw CatalogError("catalog.json has no defaults for $key")
    }
}

// Reading the catalog's JSON, where anything missing or of another shape is a CatalogError.

private inline fun catalogCheck(condition: Boolean, message: () -> String) {
    if (!condition) throw CatalogError(message())
}

private fun <T> JsonObject.parts(name: String, codec: JsonCodec<T>, key: String): List<T> =
    list(name).mapIndexed { index, part -> whole(part, codec, "$key.$name[$index]") }

private fun <T> whole(json: JsonElement, codec: JsonCodec<T>, where: String): T =
    codec.decode(json) ?: throw CatalogError("$where can't be read by this build")

private fun JsonElement.obj(where: String): JsonObject =
    this as? JsonObject ?: throw CatalogError("$where isn't an object")

private fun JsonElement.text(where: String): String =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw CatalogError("$where isn't text")

private fun JsonObject.string(name: String): String = this[name]?.text(name) ?: throw CatalogError("$name is missing")

private fun JsonObject.bool(name: String): Boolean =
    (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
        ?: throw CatalogError("$name isn't true or false")

private fun JsonObject.int(name: String): Int =
    (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
        ?: throw CatalogError("$name isn't a whole number")

private fun JsonObject.list(name: String): List<JsonElement> =
    this[name] as? JsonArray ?: throw CatalogError("$name isn't a list")

private fun JsonObject.strings(name: String): Map<String, String> =
    (this[name]?.obj(name) ?: throw CatalogError("$name is missing"))
        .mapValues { (key, value) -> value.text("$name.$key") }
