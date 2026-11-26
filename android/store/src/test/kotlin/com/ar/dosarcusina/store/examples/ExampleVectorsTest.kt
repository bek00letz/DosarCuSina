package com.ar.dosarcusina.store.examples

import com.ar.dosarcusina.archive.ArchiveRecords
import com.ar.dosarcusina.archive.GoldenContents
import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.history.HistoryWording
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.sections.AssetActions
import com.ar.dosarcusina.store.templates.TemplateStore
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.io.File

/**
 * The iOS app's answers for the example household loaded, kept and removed
 * (shared/test-vectors/examples/, written by ios/DosarCuSinaTests/ExampleVectorsTests.swift), run
 * through this store's own loader ([ExampleDataService]) on a real Room store: each case's steps from
 * an empty binder with the built-in categories, today 2026-11-26 at noon in Bucharest, and the binder
 * they leave written as a backup writes it, in the canonical form both apps share ([CanonicalBinder]),
 * record by record.
 */
class ExampleVectorsTest {
    private companion object {
        const val TODAY = "2026-11-26"
    }

    private fun cases(): List<JsonObject> {
        val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
        val file = File(shared, "test-vectors/examples/load-and-remove.json")
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    @TestFactory
    fun everyCaseLeavesTheBinderTheIosAppLeaves(): List<DynamicTest> = cases().map { case ->
        DynamicTest.dynamicTest(case.getValue("name").jsonPrimitive.content) {
            val run = Run()
            case.getValue("steps").jsonArray.forEach { run.take(it.jsonObject) }
            val kept = run.kept?.let { names -> JsonArray(names.map(::JsonPrimitive)) } ?: JsonNull
            assertEquals(case.getValue("kept"), kept)
            val differences = CanonicalBinder.differences(case.getValue("binder").jsonObject, run.binder())
            assertTrue(differences.isEmpty(), differences.joinToString("\n"))
        }
    }

    /** One case's binder and what its steps have left so far. */
    private class Run {
        val binder = TestBinderStore(now = noon(TODAY)).also { it.launch.installBuiltIns(noon(TODAY)) }
        val examples = ExampleDataService(
            binder.unit, binder.launch, TestWording, now = { noon(TODAY) }, zone = { bucharest },
        )
        var kept: List<String>? = null
        private var receipt: UndoReceipt? = null

        fun take(step: JsonObject) {
            fun text(key: String) = step.getValue(key).jsonPrimitive.content
            when (val action = text("do")) {
                "ownSection" -> ownSection(text("name"), text("category"))
                "load" -> examples.loadExamples()
                "ownSectionInside" -> ownSectionInside(text("name"), text("category"), text("parent"))
                "adopt" -> examples.adopt(section(text("section")).id)
                "remove" -> ExampleRemoval.remove(examples).let {
                    kept = it.kept.sorted()
                    receipt = it.receipt
                }
                "undo" -> requireNotNull(receipt) { "Nothing to take back" }.undo()
                else -> error("No step $action")
            }
        }

        /** What the steps left, as a backup writes it, in canonical form. */
        fun binder(): JsonObject {
            val records = GoldenContents.of(ArchiveRecords.of(binder.target.snapshot(), bucharest)).records
            return CanonicalBinder.form(CanonicalBinder.paths.map { it to records[it].orEmpty().values.toList() })
        }

        private fun ownSection(name: String, category: String) {
            val template = requireNotNull(TemplateStore(binder.unit, binder.locks).template(category))
            AssetActions(binder.unit, now = { noon(TODAY) }, zone = { bucharest }).create(name, template, FieldValues())
        }

        /** A section of the person's inside an example, written straight in, as an earlier version let it be. */
        private fun ownSectionInside(name: String, category: String, parent: String) {
            val holder = section(parent)
            binder.unit.perform(now = noon(TODAY)) { step ->
                step.insert(Asset(name = name, templateKey = category, parent = holder.pk))
            }
        }

        private fun section(name: String): Asset = binder.snapshot().all(Tables.assets).first { it.name == name }
    }
}

/** A binder's records in the canonical form the iOS cases are written in (`ExampleVectorsTests`'s `Canonical`). */
internal object CanonicalBinder {
    /** The data files a binder is written with, in the archive's order: every one but the categories. */
    val paths: List<String> = DossierV3.Path.DATA_FILES.filter { it != DossierV3.Path.TEMPLATES }

    private val uuid = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

    /**
     * Each file's records ([files], in order): each file's records in an order of their own contents,
     * every id written as the place it takes (`id-1`, `id-2`…: the records' own ids first, file by
     * file, then the others as they come), a list of ids in the order of their places, and
     * `createdAt` as `<made>`.
     */
    fun form(files: List<Pair<String, List<JsonElement>>>): JsonObject {
        val places = HashMap<String, String>()
        fun place(id: String): String = places.getOrPut(id.lowercase()) { "id-${places.size + 1}" }
        val ordered = files.map { (path, records) ->
            path to records.sortedBy { record -> MachineText.json(written(record) { _ -> "<id>" }) }
        }
        for ((_, records) in ordered) {
            for (record in records) {
                val id = ((record as? JsonObject)?.get("id") as? JsonPrimitive)?.takeIf { it.isString } ?: continue
                uuid.findAll(id.content).forEach { place(it.value) }
            }
        }
        return JsonObject(
            ordered.associate { (path, records) -> path to JsonArray(records.map { written(it, ids = ::place) }) },
        )
    }

    /** Every record that differs between [expected] and [actual], by file, place and key. */
    fun differences(expected: JsonObject, actual: JsonObject): List<String> = paths.flatMap { path ->
        val left = expected[path]?.jsonArray.orEmpty()
        val right = actual[path]?.jsonArray.orEmpty()
        val sizes = if (left.size == right.size) emptyList() else listOf("$path: iOS ${left.size}, here ${right.size}")
        sizes + left.zip(right).withIndex().flatMap { (index, pair) -> differences("$path[$index]", pair) }
    }

    private fun differences(where: String, pair: Pair<JsonElement, JsonElement>): List<String> {
        val (ios, android) = pair.first.jsonObject to pair.second.jsonObject
        fun text(record: JsonObject, key: String) = record[key]?.let(MachineText::json)
        return (ios.keys + android.keys).sorted().filter { text(ios, it) != text(android, it) }.map { key ->
            "$where.$key: iOS ${text(ios, key)}, Android ${text(android, key)}"
        }
    }

    private fun written(value: JsonElement, key: String? = null, ids: (String) -> String): JsonElement = when (value) {
        is JsonObject -> JsonObject(
            value.keys.sorted().associate { name ->
                uuid.replace(name) { ids(it.value) } to written(value.getValue(name), name, ids)
            },
        )
        is JsonArray -> list(value, ids)
        is JsonPrimitive -> when {
            !value.isString -> value
            key == "createdAt" -> JsonPrimitive("<made>")
            else -> JsonPrimitive(uuid.replace(value.content) { ids(it.value) })
        }
    }

    /** A list of ids (a firm's sections, a visit's firms) is a set: written in the order of their places. */
    private fun list(value: JsonArray, ids: (String) -> String): JsonArray {
        val items = value.map { written(it, null, ids) }
        val allIds = value.all { it is JsonPrimitive && it.isString && uuid.matches(it.content) }
        if (value.isEmpty() || !allIds) return JsonArray(items)
        return JsonArray(items.map { it.jsonPrimitive.content }.sorted().map(::JsonPrimitive))
    }
}

/** The words a record's title is written with; the household names every record, so none is asked. */
internal object TestWording : HistoryWording {
    override fun entryTitle(kind: VisitKind?): String = "Vizită"

    override fun manyJobs(count: Int): String = "Revizie: $count lucrări"
}
