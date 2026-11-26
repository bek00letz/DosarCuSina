package com.ar.dosarcusina.store.search

import com.ar.dosarcusina.archive.v3.ChoiceOption
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.search.SearchDetail
import com.ar.dosarcusina.core.search.SearchDocument
import com.ar.dosarcusina.core.search.SearchRoute
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.RecordRef
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.locks.BinderLocks
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/**
 * What each record gives the index, as on the iPhone: the household of
 * shared/test-vectors/search/search-records.json (written by ios/DosarCuSinaTests/SearchVectorsTests.swift)
 * saved into a Room binder through the unit of work, then read by [SearchIndexer], must give every
 * document the iOS app's `SearchIndexBuilder` gave, field by field.
 */
class SearchRecordsVectorsTest {
    private val case: JsonObject = vectors().getValue("cases").jsonArray.single().jsonObject
    private val household = case.getValue("household").jsonObject
    private val words = VectorWording(case.getValue("words").jsonObject, household)

    @Test
    fun `every record gives the index what it gives on the iPhone`() {
        val binder = TestBinderStore()
        fill(binder)
        val indexer = SearchIndexer(binder.store, binder.locks, words, zone = { ZoneId.of(words.zone) })
        val actual = runBlocking { indexer.rebuild() }.documents.associateBy { it.id }
        val expected = case.getValue("documents").jsonArray.map { it.jsonObject }
        assertEquals(expected.map { it.text("id") }.toSet(), actual.keys, "The same documents")
        for (document in expected) check(document, actual.getValue(document.text("id")))
    }

    @Test
    fun `what a change to a section reads again is what it reads on the iPhone`() {
        val binder = TestBinderStore()
        fill(binder)
        val view = binder.snapshot()
        val locks = BinderLocks.of(
            view.all(Tables.templates),
            view.all(Tables.assets).map { it.templateKey },
            binder.locks,
        )
        val search = BinderSearch(view, locks, words, ZoneId.of(words.zone))
        for (entry in case.list("rereads")) {
            val section =
                entry.textOrNull("section")?.let { id ->
                    view.all(Tables.assets).single { it.id == UUID.fromString(id) }
                }
            val ref = section?.let { RecordRef.of(Tables.assets, it) }
                ?: RecordRef.of(
                    Tables.templates,
                    view.all(Tables.templates).single { it.key == entry.text("category") },
                )
            val changed = search.recordsShowing(ref)?.let { named(it, view) }
            val deleted = search.recordsShowingDeleted(ref)?.let { named(it, view) }
            assertEquals(entry.names("changed"), changed, "$ref changed")
            assertEquals(entry.names("deleted"), deleted, "$ref deleted")
        }
    }

    /** Records as the iPhone names them: their kind as a route names it and their id ("document:…"), sorted. */
    private fun named(records: Set<RecordRef>, view: BinderView): List<String> = records.mapNotNull { ref ->
        val (kind, id) = when (ref.type) {
            Tables.assets.type -> "asset" to view.row(Tables.assets, ref.row)?.id
            Tables.obligations.type -> "obligation" to view.row(Tables.obligations, ref.row)?.id
            Tables.history.type -> "historyEntry" to view.row(Tables.history, ref.row)?.id
            Tables.providers.type -> "provider" to view.row(Tables.providers, ref.row)?.id
            Tables.attachments.type -> "document" to view.row(Tables.attachments, ref.row)?.id
            else -> return@mapNotNull null
        }
        id?.let { "$kind:${it.toString().uppercase(Locale.ROOT)}" }
    }.sorted()

    private fun JsonObject.names(key: String): List<String>? =
        getValue(key).takeUnless { it is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content }

    private fun check(expected: JsonObject, actual: SearchDocument) {
        val id = actual.id
        assertEquals(expected.text("kind"), actual.kind.raw, "$id kind")
        assertEquals(expected.text("title"), actual.title, "$id title")
        assertEquals(expected.textOrNull("subtitle").orEmpty(), words.line(actual.subtitle), "$id subtitle")
        val route = expected.getValue("route").jsonObject
        assertEquals(route.text("kind") to UUID.fromString(route.text("id")), routeOf(actual.route), "$id route")
        val fields = expected.list("fields").map { it.text("text") to it.int("weight") }
        assertEquals(fields, actual.fields.map { it.text to it.weight }, "$id fields")
        assertEquals(expected.textOrNull("date")?.let(Instant::parse), actual.date, "$id date")
        assertEquals(expected.bool("isSensitive"), actual.isSensitive, "$id isSensitive")
    }

    private fun routeOf(route: SearchRoute): Pair<String, UUID> = when (route) {
        is SearchRoute.Section -> "asset"
        is SearchRoute.Deadline -> "obligation"
        is SearchRoute.HistoryEntry -> "historyEntry"
        is SearchRoute.Provider -> "provider"
        is SearchRoute.Document -> "document"
    } to route.id

    // The household, saved as a backup's writer saves it: through the unit of work, its times kept.

    private fun fill(binder: TestBinderStore) {
        for (template in household.list("templates")) {
            if (template.bool("isLocked")) {
                binder.store.locks.set(true, template.text("key"), binder.now)
            }
        }
        binder.unit.performPrivate { step ->
            for (template in household.list("templates")) step.insert(template(template))
            val assets = household.list("assets").associate { it.uuid("id") to step.insert(asset(it)).pk }
            val providers = household.list("providers").associate { it.uuid("id") to step.insert(provider(it)).pk }
            for (provider in household.list("providers")) {
                val looksAfter = provider.uuids("assetIds").map(assets::getValue)
                step.setLinked(Tables.providerAssets, providers.getValue(provider.uuid("id")), looksAfter)
            }
            val obligations = household.list("obligations").associate { row ->
                row.uuid("id") to step.insert(obligation(row, row.uuidOrNull("assetId")?.let(assets::getValue))).pk
            }
            val entries = mutableMapOf<UUID, Long>()
            val items = mutableMapOf<UUID, Long>()
            for (row in household.list("historyEntries")) {
                val entry = step.insert(entry(row, row.uuidOrNull("assetId")?.let(assets::getValue)))
                entries[row.uuid("id")] = entry.pk
                step.setLinked(Tables.entryProviders, entry.pk, row.uuids("providerIds").map(providers::getValue))
                for (item in row.list("items")) items[item.uuid("id")] = step.insert(item(item, entry.pk, providers)).pk
            }
            for (row in household.list("attachments")) insertPaper(step, row, assets, obligations, entries, items)
        }
    }

    private fun template(row: JsonObject): CategoryTemplate {
        val fields = row.list("fields").map { field ->
            FieldDefinition(
                key = field.text("key"), label = field.text("label"), type = field.text("type"),
                role = field.textOrNull("role"), isSensitive = field.bool("isSensitive"),
                options = field.list("options").map { ChoiceOption(it.text("key"), it.text("label")) }.ifEmpty { null },
            )
        }
        val components = row.list("components").map {
            ComponentDefinition(it.text("key"), it.text("name"), it.text("group"), it.texts("synonyms"))
        }
        return CategoryTemplate(
            key = row.text("key"), name = row.text("name"), isBuiltIn = false,
            sectionsData = json(listOf(FieldSection.codec.encode(FieldSection("main", "Date", fields)))),
            componentsData = json(components.map(ComponentDefinition.codec::encode)),
        )
    }

    private fun asset(row: JsonObject): Asset {
        val values = row.getValue("values").jsonObject.mapValues { (_, value) -> value.jsonObject.getValue("value") }
        val facts = row.list("facts").map {
            CustomFact(
                it.uuid("id"), it.text("label"), it.text("value"),
                it.bool("isSensitive"),
                it.bool("isSecret"),
            ).toJson()
        }
        val updatedAt = Instant.parse(row.text("updatedAt"))
        return Asset(
            id = row.uuid("id"), name = row.text("name"), templateKey = row.text("templateKey"),
            notes = row.textOrNull("notes"),
            valuesData = MachineText.json(JsonObject(values)), customFactsData = json(facts),
            createdAt = updatedAt, updatedAt = updatedAt,
        )
    }

    private fun provider(row: JsonObject): Provider {
        val updatedAt = Instant.parse(row.text("updatedAt"))
        return Provider(
            id = row.uuid("id"), name = row.text("name"), trades = row.texts("trades"), phone = row.textOrNull("phone"),
            address = row.textOrNull("address"), notes = row.textOrNull("notes"),
            createdAt = updatedAt, updatedAt = updatedAt,
        )
    }

    private fun obligation(row: JsonObject, asset: Long?) = Obligation(
        id = row.uuid("id"), title = row.text("title"), dueDayISO = row.text("dueDay"),
        reference = row.textOrNull("reference"),
        provider = row.textOrNull("provider"), notes = row.textOrNull("notes"), asset = asset,
    )

    private fun entry(row: JsonObject, asset: Long?) = HistoryEntry(
        id = row.uuid("id"), kindRaw = row.text("kind"), title = row.text("title"),
        occurredAt = Instant.parse(row.text("occurredAt")),
        note = row.textOrNull("note"), reference = row.textOrNull("reference"), asset = asset,
    )

    private fun item(row: JsonObject, entry: Long, providers: Map<UUID, Long>) = ServiceItem(
        id = row.uuid("id"), name = row.text("name"), componentKey = row.textOrNull("componentKey"),
        partBrandOrCode = row.textOrNull("partBrandOrCode"),
        supplier = row.uuidOrNull("supplierId")?.let(providers::getValue),
        entry = entry,
    )

    @Suppress("LongParameterList")
    private fun insertPaper(
        step: Step,
        row: JsonObject,
        assets: Map<UUID, Long>,
        obligations: Map<UUID, Long>,
        entries: Map<UUID, Long>,
        items: Map<UUID, Long>,
    ) {
        step.insert(
            Attachment(
                id = row.uuid("id"), title = row.textOrNull("title"), fileName = row.text("fileName"),
                kindRaw = row.text("kind"), extractedText = row.textOrNull("extractedText"),
                isArchived = row.bool("isArchived"),
                documentDayISO = row.textOrNull("documentDay"), createdAt = Instant.parse(row.text("createdAt")),
                asset = row.uuidOrNull("assetId")?.let(assets::getValue),
                obligation = row.uuidOrNull("obligationId")?.let(obligations::getValue),
                historyEntry = row.uuidOrNull("historyEntryId")?.let(entries::getValue),
                serviceItem = row.uuidOrNull("serviceItemId")?.let(items::getValue),
            ),
        )
    }

    /** The iPhone's words for this household: each value as its row showed it, each day, each trade. */
    private class VectorWording(words: JsonObject, household: JsonObject) : BinderSearchWording {
        val zone: String = words.text("zone")
        private val days = words.getValue("days").jsonObject.mapValues { it.value.jsonPrimitive.content }
        private val trades = words.getValue("trades").jsonObject.mapValues { it.value.jsonPrimitive.content }
        private val archived = words.text("archived")
        private val shown: Map<Pair<String, FieldValue>, String> = household.list("assets").flatMap { asset ->
            asset.getValue("values").jsonObject.mapNotNull { (key, value) ->
                val read = FieldValue.read(value.jsonObject.getValue("value")) ?: return@mapNotNull null
                val text = value.jsonObject.textOrNull("shown") ?: return@mapNotNull null
                (key to read) to text
            }
        }.toMap()

        /**
         * As the iPhone showed it; a text the save masked (a card number in a colour) is shown as
         * stored, as the iPhone shows any plain text.
         */
        override fun shown(value: FieldValue, field: FieldDefinition): String =
            shown[field.key to value]
                ?: value.textValue?.takeIf { field.type == "text" }
                ?: error("No shown value for ${field.key}")

        override fun trade(key: String): String = trades[key] ?: key

        override fun line(details: List<SearchDetail>): String = details.joinToString(" · ") { detail ->
            when (detail) {
                is SearchDetail.Text -> detail.text
                is SearchDetail.Day -> days.getValue(detail.day.isoString)
                is SearchDetail.Trades -> romanianList(detail.keys.map(::trade))
                SearchDetail.Archived -> archived
            }
        }

        /** "A", "A și B", "A, B și C", as the iOS app's list format in Romanian. */
        private fun romanianList(items: List<String>): String =
            if (items.size <= 1) {
                items.joinToString("")
            } else {
                "${items.dropLast(1).joinToString(", ")} și ${items.last()}"
            }
    }

    private companion object {
        fun vectors(): JsonObject {
            val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
            val text = File(shared, "test-vectors/search/search-records.json").readText()
            return expand(MachineText.parse(text)).jsonObject
        }

        /** Every number the iOS test built when it ran, built again: `{luhn:DIGITS}`, the only kind used here. */
        fun expand(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(element.mapValues { expand(it.value) })
            is JsonArray -> JsonArray(element.map(::expand))
            is JsonPrimitive -> if (element.isString) JsonPrimitive(expandText(element.content)) else element
            JsonNull -> element
        }

        private val token = Regex("""\{luhn:([^{}]*)\}""")

        fun expandText(text: String): String = token.replace(text) { match ->
            val digits = match.groupValues[1]
            digits + checkDigit(digits.filter(Char::isDigit))
        }

        fun checkDigit(digits: String): Int {
            val sum = digits.reversed().withIndex().sumOf { (index, character) ->
                val digit = character - '0'
                val doubled = if (index % 2 == 0) digit * 2 else digit
                if (doubled > 9) doubled - 9 else doubled
            }
            return (10 - sum % 10) % 10
        }

        fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content

        fun JsonObject.textOrNull(key: String): String? =
            this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

        fun JsonObject.bool(key: String): Boolean = text(key).toBooleanStrict()

        fun json(elements: List<JsonElement>): String = MachineText.json(JsonArray(elements))

        fun JsonObject.int(key: String): Int = text(key).toInt()

        fun JsonObject.texts(key: String): List<String> = getValue(key).jsonArray.map { it.jsonPrimitive.content }

        fun JsonObject.list(key: String): List<JsonObject> = getValue(key).jsonArray.map { it.jsonObject }

        fun JsonObject.uuid(key: String): UUID = UUID.fromString(text(key))

        fun JsonObject.uuidOrNull(key: String): UUID? = textOrNull(key)?.let(UUID::fromString)

        fun JsonObject.uuids(key: String): List<UUID> = texts(key).map(UUID::fromString)
    }
}
