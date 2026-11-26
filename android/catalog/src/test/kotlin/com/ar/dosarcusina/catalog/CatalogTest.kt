package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.ArchiveRecords
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.core.values.JsonCodec
import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.time.Instant
import java.time.ZoneOffset

/** `shared/`, where the iOS tests export the catalog and the golden archives. */
val sharedFolder: File get() = File(System.getProperty("dosar.shared") ?: "../../shared")

/** A file of `shared/catalog/` as committed. */
fun committed(file: Catalog.File): String = File(sharedFolder, "catalog/${file.fileName}").readText()

/**
 * The catalog the build carries is the one the iOS app exported (shared/catalog/), read whole:
 * every built-in, every part of each, written back exactly as it came, and each one what an iOS
 * backup says of it.
 */
class CatalogTest {
    private val catalog = Catalog.builtIn

    @Test
    fun theBuildCarriesTheCommittedCatalog() {
        for (file in Catalog.File.entries) {
            assertEquals(committed(file), Catalog.resource(file), "${file.fileName} is shared/catalog's, as it is")
        }
    }

    @Test
    fun everyBuiltInIsThereInTheCatalogsOrder() {
        assertEquals(
            listOf(
                "vehicle", "home", "documents", "pet", "health", "purchase", "subscription", "other", "bike", "plants",
                "tenancy", "member", "espresso",
            ),
            catalog.all.map { it.key },
        )
        for (definition in catalog.all) {
            assertEquals(catalog.version, definition.version, definition.key)
            assertTrue(catalog.isBuiltIn(definition.key))
        }
        assertFalse(catalog.isBuiltIn("custom.eeeeeeee-eeee-4eee-8eee-eeeeeeeeee01"))
        assertFalse(catalog.isBuiltIn("warranty"), "A key an earlier catalog had is no built-in")
        assertEquals(mapOf("warranty" to "purchase"), catalog.replacedKeys)
        assertEquals(setOf("rental"), catalog.retiredKeys)
        assertEquals("purchase.warrantyUntil", catalog.replacedFieldKeys["warranty.expiry"])
        val locked = catalog.all.filter { it.isSensitiveByDefault }.map { it.key }
        assertEquals(listOf("documents", "health"), locked)
    }

    /** Every part of every built-in, read and written again, is what the catalog says, nothing lost or added. */
    @Test
    fun everyPartRoundTrips() {
        val templates = MachineText.parse(committed(Catalog.File.TEMPLATES)) as JsonArray
        for (template in templates.map { it as JsonObject }) {
            val key = (template.getValue("key") as JsonPrimitive).content
            roundTrips(template, "sections", FieldSection.codec, key)
            roundTrips(template, "blueprints", ObligationBlueprint.codec, key)
            roundTrips(template, "components", ComponentDefinition.codec, key)
            template["behavior"]?.let { behavior ->
                val read = CategoryBehavior.codec.decode(behavior)
                assertNotNull(read, "$key.behavior reads")
                assertSame(behavior, CategoryBehavior.codec.encode(read!!), "$key.behavior")
            }
        }
    }

    /** Each built-in's keys read and written back: its sections', fields', deadlines' and parts', each once. */
    @Test
    fun everyBuiltInsKeysRoundTrip() {
        val templates = (MachineText.parse(committed(Catalog.File.TEMPLATES)) as JsonArray).associateBy {
            ((it as JsonObject).getValue("key") as JsonPrimitive).content
        }
        for (definition in catalog.all) {
            val stored = templates.getValue(definition.key) as JsonObject
            fun keys(name: String) = (stored.getValue(name) as JsonArray).map {
                ((it as JsonObject).getValue("key") as JsonPrimitive).content
            }
            assertEquals(keys("sections"), definition.sections.map { it.key }, definition.key)
            assertEquals(keys("blueprints"), definition.blueprints.map { it.key }, definition.key)
            assertEquals(keys("components"), definition.components.map { it.key }, definition.key)
            val fields = definition.sections.flatMap { it.fields }.map { it.key }
            val storedFields = (stored.getValue("sections") as JsonArray).flatMap { section ->
                ((section as JsonObject).getValue("fields") as JsonArray).map {
                    ((it as JsonObject).getValue("key") as JsonPrimitive).content
                }
            }
            assertEquals(storedFields, fields, definition.key)
            for (list in listOf(fields, definition.blueprints.map { it.key }, definition.components.map { it.key })) {
                assertEquals(list.size, list.toSet().size, "${definition.key}: each key once, $list")
            }
            val written = definition.template(null, Instant.EPOCH)
            assertEquals(definition.sections, written.sections.items)
            assertEquals(definition.blueprints, written.blueprints.items)
            assertEquals(definition.components, written.components.items)
        }
    }

    /**
     * Each built-in, written as an Android backup writes it, is what the iOS golden backup holds
     * for it (shared/fixtures/golden/ios/expected/data/templates.json), but for the household's
     * own choices and times.
     */
    @Test
    fun eachBuiltInIsWhatAnIosBackupSaysOfIt() {
        val household = setOf("homeOrder", "isOnHome", "isSensitive", "boxGrouping", "createdAt", "updatedAt")
        val golden = File(sharedFolder, "fixtures/golden/ios/expected/data/templates.json").readText()
        val ios = (MachineText.parse(golden) as JsonArray).associateBy {
            ((it as JsonObject).getValue("key") as JsonPrimitive).content
        }
        val binder = Binder(templates = catalog.all.map { it.template(null, Instant.EPOCH) })
        val written = ArchiveRecords.of(binder, ZoneOffset.UTC).templates
        assertEquals(catalog.all.size, written.size)
        for (record in written) {
            val ours = JsonObject(record.toJson().filterKeys { it !in household })
            val theirs = JsonObject((ios.getValue(record.key) as JsonObject).filterKeys { it !in household })
            assertSame(theirs, ours, record.key)
        }
    }

    /** Every key code names is one of its category's: a constant never names a field or deadline the catalog lacks. */
    @Test
    fun theNamedKeysAreTheCatalogs() {
        val fields = catalog.all.flatMap { it.sections }.flatMap { it.fields }.map { it.key }.toSet()
        val blueprints = catalog.all.flatMap { definition -> definition.blueprints.map { it.key } }.toSet()
        val categories = catalog.all.map { it.key }
        for ((type, keys) in BuiltInKeysTest.exported()) {
            for ((name, key) in keys) {
                val known = when {
                    type == "BuiltInTemplates.Key" -> key in categories
                    type == "BuiltInBlueprints" || name.endsWith("Blueprint") -> key in blueprints
                    else -> key in fields
                }
                assertTrue(known, "$type.$name names $key, which the catalog doesn't have")
            }
        }
    }

    @Test
    fun aCatalogThatCantBeReadWhole() {
        fun reading(change: (Catalog.File, String) -> String) = assertThrows(CatalogError::class.java) {
            Catalog.read { file -> change(file, committed(file)) }
        }
        // A field whose type isn't text, a version no built-in has, a category without its definition, no list.
        reading { file, text ->
            if (file == Catalog.File.TEMPLATES) text.replaceFirst("\"type\" : \"plate\"", "\"type\" : 7") else text
        }
        reading { file, text ->
            val version = "\"builtInVersion\" : "
            val newer = text.replace(version + catalog.version, version + (catalog.version + 1))
            if (file == Catalog.File.CATALOG) newer else text
        }
        reading { file, text ->
            if (file == Catalog.File.CATALOG) text.replaceFirst("\"key\" : \"vehicle\"", "\"key\" : \"car\"") else text
        }
        reading { file, text -> if (file == Catalog.File.TEMPLATES) "{}" else text }
    }

    private fun <T> roundTrips(template: JsonObject, name: String, codec: JsonCodec<T>, key: String) {
        for ((index, part) in (template.getValue(name) as JsonArray).withIndex()) {
            val read = codec.decode(part)
            assertNotNull(read, "$key.$name[$index] reads")
            assertSame(part, codec.encode(read!!), "$key.$name[$index]")
        }
    }

    private fun assertSame(expected: JsonElement, actual: JsonElement, what: String) {
        assertTrue(JsonTrees.same(expected, actual)) {
            "$what:\nexpected ${MachineText.json(expected)}\nwritten  ${MachineText.json(actual)}"
        }
    }
}
