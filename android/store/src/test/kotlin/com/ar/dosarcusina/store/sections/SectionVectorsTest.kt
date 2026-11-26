package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.archive.ProviderTaxID
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.DocumentNaming
import com.ar.dosarcusina.catalog.FieldRules
import com.ar.dosarcusina.catalog.PlannedObligation
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.providers.ProviderActions
import com.ar.dosarcusina.store.providers.ProviderTrade
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.templates.TemplateStore
import com.ar.dosarcusina.store.templates.behavior
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
 * The iOS app's answers for what a person does to a section, and the firms in the binder
 * (shared/test-vectors/sections/, written by ios/DosarCuSinaTests/SectionVectorsTests.swift), run
 * through this store's own actions on a real Room store: the deadlines a new section starts with
 * ticked, making a section with its deadlines, where a section can move and moving it, where a new
 * section goes when nobody said, a document's name, and a firm found by its CUI or its name. Today
 * is 2026-11-26 in Bucharest, as the iOS cases run.
 */
class SectionVectorsTest {
    private companion object {
        const val TODAY = "2026-11-26"
    }

    private val catalog = Catalog.builtIn

    private fun cases(name: String): List<JsonObject> {
        val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
        val file = File(shared, "test-vectors/sections/$name.json")
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content

    private fun JsonObject.textOrNull(key: String) = this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

    private fun JsonObject.bool(key: String) = text(key).toBooleanStrict()

    private fun values(json: JsonElement): FieldValues = requireNotNull(FieldValues.codec.decode(json))

    private fun nullable(text: String?): JsonElement = text?.let(::JsonPrimitive) ?: JsonNull

    private fun binder(): TestBinderStore =
        TestBinderStore(now = noon(TODAY)).also { it.launch.installBuiltIns(noon(TODAY)) }

    private fun actions(binder: TestBinderStore) =
        AssetActions(binder.unit, now = { noon(TODAY) }, zone = { bucharest })

    private fun template(binder: TestBinderStore, key: String): CategoryTemplate =
        requireNotNull(TemplateStore(binder.unit, binder.locks).template(key)) { "No category $key" }

    private fun fields(template: CategoryTemplate) = template.keptSections.items.flatMap { it.fields }

    // Which deadlines start ticked

    @TestFactory
    fun startsSelected(): List<DynamicTest> {
        val binder = binder()
        return cases("starts-selected").map { case ->
            DynamicTest.dynamicTest(case.text("name")) {
                val template = template(binder, case.text("category"))
                val typed = values(case.getValue("values"))
                val fields = fields(template)
                val keys = FieldRules.normalizingChoices(typed, fields)
                val kept = FieldRules.applying(keys, fields, null, catalog.documentTypes)
                assertEquals(values(case.getValue("kept")), kept, "The values as saving keeps them")
                val planned = actions(binder).plannedObligations(template, typed).map { plan ->
                    JsonObject(
                        mapOf(
                            "key" to JsonPrimitive(plan.blueprint.key),
                            "firstDue" to nullable(plan.firstDue?.isoString),
                            "isSelected" to JsonPrimitive(plan.isSelected),
                            "asksFirstDate" to JsonPrimitive(plan.asksFirstDate),
                            "startsSelected" to
                                JsonPrimitive(PlannedObligation.startsSelected(plan.blueprint, plan.firstDue)),
                        ),
                    )
                }
                assertTrue(JsonTrees.same(case.getValue("planned"), JsonArray(planned)), "Planned: $planned")
            }
        }
    }

    // Making a section

    @TestFactory
    fun create(): List<DynamicTest> = cases("create").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val binder = binder()
            val actions = actions(binder)
            val made = LinkedHashMap<String, Asset>()
            for (item in case.getValue("sections").jsonArray.map { it.jsonObject }) {
                val template = template(binder, item.text("category"))
                val typed = values(item.getValue("values"))
                val chosen = (item["plan"] as? JsonArray)?.map { it.jsonObject }?.associateBy { it.text("key") }
                val plan = actions.plannedObligations(template, typed).map { planned ->
                    val choice = chosen?.get(planned.blueprint.key) ?: return@map planned
                    val day = choice.textOrNull("firstDue")?.let { requireNotNull(CalendarDay.parse(it)) }
                    planned.copy(isSelected = choice.bool("isSelected"), firstDue = day ?: planned.firstDue)
                }
                val name = item.text("name")
                made[name] = actions.create(
                    name, template, typed, obligations = plan, parent = item.textOrNull("parent")?.let(made::getValue),
                )
            }
            val snapshot = binder.snapshot()
            for (expected in case.getValue("made").jsonArray.map { it.jsonObject }) {
                val asset = requireNotNull(snapshot.row(Tables.assets, made.getValue(expected.text("name")).pk))
                assertEquals(values(expected.getValue("values")), asset.keptValues.value, "${asset.name}'s values")
                val parent = asset.parent?.let { snapshot.row(Tables.assets, it) }?.name
                assertEquals(expected.textOrNull("parent"), parent, "${asset.name}'s parent")
                val obligations = snapshot.all(Tables.obligations).filter { it.asset == asset.pk }
                    .sortedBy { it.blueprintKey.orEmpty() }.map(::obligation)
                assertTrue(
                    JsonTrees.same(expected.getValue("obligations"), JsonArray(obligations)),
                    "${asset.name}'s deadlines: $obligations",
                )
                val readings = snapshot.all(Tables.readings).filter { it.asset == asset.pk }.sortedBy { it.value }.map {
                    JsonObject(
                        mapOf(
                            "value" to MachineText.number(it.value),
                            "unit" to JsonPrimitive(it.unit),
                            "kind" to JsonPrimitive(it.kindRaw),
                        ),
                    )
                }
                assertTrue(JsonTrees.same(expected.getValue("readings"), JsonArray(readings)), "Readings: $readings")
            }
            val household = snapshot.all(Tables.obligations).filter { it.asset == null }
                .sortedBy { it.blueprintKey.orEmpty() }.map(::obligation)
            assertTrue(JsonTrees.same(case.getValue("household"), JsonArray(household)), "Household: $household")
        }
    }

    private fun obligation(obligation: Obligation): JsonObject {
        val reminders = obligation.reminders
        val cost = obligation.estimatedCostAmount?.let { Money(it, obligation.estimatedCostCurrency ?: "RON").toJson() }
        return JsonObject(
            mapOf(
                "blueprintKey" to nullable(obligation.blueprintKey),
                "title" to JsonPrimitive(obligation.title),
                "kind" to JsonPrimitive(obligation.kindRaw),
                "dueDay" to JsonPrimitive(obligation.dueDayISO),
                "dueMetric" to (obligation.dueMetric?.let(MachineText::number) ?: JsonNull),
                "leadDays" to JsonArray(reminders.leadDays.map { MachineText.number(it.toLong()) }),
                "consequence" to JsonPrimitive(reminders.consequence),
                "graceDays" to MachineText.number(reminders.graceDays.toLong()),
                "followUpAfterLapse" to JsonPrimitive(reminders.followUpAfterLapse),
                "travelMarginDays" to MachineText.number(reminders.travelMarginDays.toLong()),
                "notes" to nullable(obligation.notes),
                "recurrence" to obligation.keptRecurrence.json,
                "estimatedCost" to (cost ?: JsonNull),
                "isExample" to JsonPrimitive(obligation.isExample),
            ),
        )
    }

    // Moving

    /** The household every move case starts from, made in the iOS case's order. */
    private class Household(val binder: TestBinderStore, val actions: AssetActions, val made: Map<String, Asset>)

    private fun household(): Household {
        val binder = binder()
        val actions = actions(binder)
        val made = LinkedHashMap<String, Asset>()
        fun add(name: String, key: String, values: FieldValues = FieldValues(), under: String? = null) {
            val parent = under?.let(made::getValue)
            val example = name.startsWith("Exemplu")
            made[name] = actions.create(name, template(binder, key), values, parent = parent, isExample = example)
        }
        val idCard = FieldValues(mapOf("document.type" to FieldValue.Text("documentType.idCard")))
        add("Manole Corina", "member")
        add("Popescu Ion", "member")
        add("Exemplu Persoană", "member")
        add("Carte de identitate – Manole Corina", "documents", idCard, under = "Manole Corina")
        add("Buletinul vechi", "documents", idCard)
        add("Apartament", "home")
        add("Casa de la țară", "home")
        add("Chiriaș etaj 2", "tenancy", under = "Apartament")
        val gas = FieldValues(mapOf("subscription.service" to FieldValue.Text("service.gas")))
        add("Gaz", "subscription", gas, under = "Apartament")
        add("Ferigă", "plants")
        add("VW Golf 2018", "vehicle")
        return Household(binder, actions, made)
    }

    @TestFactory
    fun move(): List<DynamicTest> {
        val start = household()
        val view = start.binder.snapshot()
        val byName = view.all(Tables.assets).associateBy { it.name }
        return cases("move").map { case ->
            val title = case.textOrNull("move") ?: case.text("section")
            DynamicTest.dynamicTest(title) {
                if (case.containsKey("move")) checkMove(case) else checkPlaces(case, view, byName)
            }
        }
    }

    private fun checkPlaces(case: JsonObject, view: BinderView, byName: Map<String, Asset>) {
        val asset = byName.getValue(case.text("section"))
        val strings = { key: String -> case.getValue(key).jsonArray.map { it.jsonPrimitive.content } }
        assertEquals(strings("parentKeys"), SectionPlaces.parentKeys(view, asset).sorted(), "parentKeys")
        assertEquals(case.bool("canMove"), SectionPlaces.canMove(view, asset), "canMove")
        assertEquals(case.bool("offersNewMember"), SectionPlaces.offersNewMember(view, asset), "offersNewMember")
        assertEquals(case.bool("offersStandalone"), SectionPlaces.offersStandalone(view, asset), "offersStandalone")
        val destinations = SectionPlaces.moveDestinations(view, asset).map { it.name }
        assertEquals(strings("destinations"), destinations, "destinations")
        val renamed = case.getValue("renamedFor").jsonObject.textOrNull("Popescu Ion")
        assertEquals(renamed, SectionPlaces.renamedForHolder(view, asset, "Popescu Ion"), "renamedForHolder")
    }

    private fun checkMove(case: JsonObject) {
        val household = household()
        val child = household.made.getValue(case.text("section"))
        val member = case.textOrNull("newMember")
        val to = case.textOrNull("to")
        val target = when {
            member != null -> MoveTarget.NewMember(member)
            to != null -> MoveTarget.ToSection(household.made.getValue(to).id)
            else -> MoveTarget.Standalone
        }
        household.actions.move(child, target, case.textOrNull("renamingTo"))
        val view = household.binder.snapshot()
        val moved = requireNotNull(view.row(Tables.assets, child.pk))
        val parent = moved.parent?.let { view.row(Tables.assets, it) }
        assertEquals(case.text("name"), moved.name)
        assertEquals(case.textOrNull("parent"), parent?.name)
        assertEquals(case.textOrNull("parentCategory"), parent?.templateKey)
        val people = view.all(Tables.assets).filter { it.templateKey == "member" }.map { it.name }.sorted()
        assertEquals(case.getValue("people").jsonArray.map { it.jsonPrimitive.content }, people)
    }

    // Where a new section goes

    @TestFactory
    fun automaticParent(): List<DynamicTest> = cases("automatic-parent").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val binder = binder()
            val actions = actions(binder)
            for (home in case.getValue("homes").jsonArray.map { it.jsonObject }) {
                val example = home.bool("isExample")
                actions.create(home.text("name"), template(binder, "home"), FieldValues(), isExample = example)
            }
            val view = binder.snapshot()
            for ((key, answer) in case.getValue("categories").jsonObject) {
                val behavior = template(binder, key).behavior
                for ((side, expected) in answer.jsonObject) {
                    val example = side == "example"
                    val possible = SectionPlaces.possibleParents(view, behavior, example).map { it.name }
                    assertEquals(
                        expected.jsonObject.getValue("possibleParents").jsonArray.map { it.jsonPrimitive.content },
                        possible,
                        "$key, $side: where it can stand",
                    )
                    assertEquals(
                        expected.jsonObject.textOrNull("automaticParent"),
                        SectionPlaces.automaticParent(view, behavior, example)?.name,
                        "$key, $side: where it goes",
                    )
                }
            }
        }
    }

    // A document's name

    @TestFactory
    fun documentNames(): List<DynamicTest> {
        val types = catalog.documentTypes
        return cases("document-names").mapIndexed { index, case ->
            DynamicTest.dynamicTest("Case $index") {
                when {
                    "type" in case -> {
                        val type = case.text("type")
                        val variant = case.textOrNull("variant")
                        assertEquals(case.text("documentName"), types.documentName(type, variant))
                        assertEquals(case.textOrNull("validityMonths")?.toInt(), types.validityMonths(type, variant))
                        if (variant == null) {
                            assertEquals(case.bool("keepsBackSide"), types.keepsBackSide(type))
                            assertEquals(case.text("travelMarginDays").toInt(), types.travelMarginDays(type))
                            assertEquals(case.bool("isDatedByIssue"), types.isDatedByIssue(type))
                        }
                    }
                    "typeText" in case -> {
                        val text = case.text("typeText")
                        assertEquals(case.bool("keepsBackSide"), types.keepsBackSide(text))
                        assertEquals(case.text("travelMarginDays").toInt(), types.travelMarginDays(text))
                    }
                    "values" in case ->
                        assertEquals(
                            case.textOrNull("nameFromValues"),
                            types.documentName(values(case.getValue("values"))),
                        )
                    "validUntil" in case -> {
                        val rule = case.getValue("validUntil").jsonObject
                        val issued = requireNotNull(CalendarDay.parse(rule.text("issued")))
                        val until = types.validUntil(issued, rule.text("type"), rule.textOrNull("variant"))
                        assertEquals(rule.textOrNull("until"), until?.isoString)
                    }
                    "nameOf" in case -> {
                        val input = case.getValue("nameOf").jsonObject
                        val name = DocumentNaming.name(input.text("document"), input.textOrNull("holder"))
                        assertEquals(case.text("name"), name)
                    }
                    "renamed" in case -> {
                        val input = case.getValue("renamed").jsonObject
                        val from = input.textOrNull("from")
                        val result = DocumentNaming.renamed(input.text("name"), from, input.text("to"))
                        assertEquals(case.textOrNull("result"), result)
                    }
                    else -> {
                        val input = case.getValue("retyped").jsonObject
                        val from = input.textOrNull("from")
                        val result = DocumentNaming.retyped(input.text("name"), from, input.text("to"))
                        assertEquals(case.textOrNull("result"), result)
                    }
                }
            }
        }
    }

    // Firms

    @TestFactory
    fun firms(): List<DynamicTest> = cases("firms").mapIndexed { index, case ->
        DynamicTest.dynamicTest(case.textOrNull("name") ?: "CUI $index") {
            if ("taxIDText" in case) {
                assertEquals(case.textOrNull("normalized"), ProviderTaxID.normalized(case.text("taxIDText")))
                return@dynamicTest
            }
            val binder = binder()
            val providers = ProviderActions(binder.unit, now = { noon(TODAY) })
            val made = case.getValue("firms").jsonArray.map { it.jsonObject }.map { firm ->
                val provider = providers.create(firm.text("name"), listOf(ProviderTrade.OTHER))
                binder.unit.perform { step ->
                    val row = requireNotNull(step.row(Tables.providers, provider.pk))
                    step.update(row.copy(taxID = firm.textOrNull("taxID")))
                }
                provider
            }
            val find = case.getValue("find").jsonObject
            val found = providers.findOrCreate(
                find.text("name"), find.textOrNull("taxID"), requireNotNull(ProviderTrade.of(find.text("trade"))),
            )
            val expected = case.getValue("found")
            val index = found?.let { firm -> made.indexOfFirst { it.id == firm.id } }
            val answer: JsonElement = when {
                found == null -> JsonNull
                index == null || index < 0 -> JsonPrimitive("new")
                else -> MachineText.number(index.toLong())
            }
            assertTrue(JsonTrees.same(expected, answer), "Found $answer")
            val after = binder.snapshot().all(Tables.providers).map { firm ->
                JsonObject(
                    mapOf(
                        "name" to JsonPrimitive(firm.name),
                        "taxID" to nullable(firm.taxID),
                        "trades" to JsonArray(firm.trades.map(::JsonPrimitive)),
                    ),
                )
            }
            assertTrue(JsonTrees.same(case.getValue("after"), JsonArray(after)), "After: $after")
        }
    }
}
