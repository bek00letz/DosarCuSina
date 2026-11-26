package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.isNullOrMissing
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.util.UUID

/** The readiness checks' answers, in shared/test-vectors/readiness/, by the iOS ReadinessVectorsTests. */
object ReadinessVectors : VectorFolder(
    folderName = "readiness",
    files = setOf("checklists", "citizenship", "requirements", "trips"),
    writtenBy = "the iOS ReadinessVectorsTests with TEST_RUNNER_READINESS_VECTORS_WRITE=1",
)

/**
 * A stand-in for the iOS app's `Policyholders.bonusMalus` in these tests only: the one member whose
 * name is the policyholder's, word for word without case or diacritics, and their class as printed.
 * The real rule comes with capture (`CaptureMapping.matchingMember`).
 */
object ExactNamePolicyholders : PolicyholderClasses {
    override fun of(policyholder: String?, among: List<ReadinessAsset>): String? {
        val name = policyholder?.let(RomanianText::fold)?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val keys = TravelData.builtIn.keys
        val matching = among.filter { it.role == ReadinessRole.HOLDER && RomanianText.fold(it.name).trim() == name }
        return matching.singleOrNull()?.values?.text(keys.bonusMalus)?.substringAfter('.')?.uppercase()
    }
}

class ReadinessVectorsTest {
    private val data = TravelData.builtIn
    private val engine = ReadinessEngine(data, ExactNamePolicyholders)

    @Test
    fun `every file of answers is read by a test`() {
        val files = ReadinessVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
        assertEquals(ReadinessVectors.files, files.map { it.nameWithoutExtension }.toSet())
    }

    @TestFactory
    fun `the checklists are as on the iPhone`(): List<DynamicTest> =
        ReadinessVectors.tests("checklists", { it.text("name") }) { case ->
            val today = parseDay(case.text("today"))
            val assets = case.getValue("sections").jsonArray.map { section(it.jsonObject) }
            val scenario = scenario(case.getValue("scenario").jsonObject)
            val expected = ReadinessJson.normalizingMoney(case.getValue("checklist"))
            assertEquals(expected, ReadinessJson.checklist(engine.checklist(scenario, assets, today)), "checklist")
            assertEquals(case.bool("readsLocked"), engine.readsSensitive(route(scenario), assets), "readsLocked")
            val candidates = ReadinessJson.candidates(engine.tripCandidates(assets))
            assertEquals(case.getValue("candidates"), candidates, "candidates")
            val opener = uuid(case.text("defaultTripFrom"))
            val trip = engine.defaultTrip(parseDay("2027-05-03"), parseDay("2027-05-10"), opener, assets)
            assertEquals(case.getValue("defaultTrip"), ReadinessJson.plan(trip, withID = false), "defaultTrip")
        }

    @TestFactory
    fun `what a traveller carries is as on the iPhone`(): List<DynamicTest> =
        ReadinessVectors.tests("requirements", { it.textOrNull("citizenship") ?: "not known" }) { case ->
            val citizenship = case.textOrNull("citizenship")
            assertEquals(case.text("group"), data.citizenship.group(citizenship).raw)
            val regions = JsonObject(TripRegion.entries.associate { region ->
                region.raw to JsonArray(data.rules.requirementsOf(citizenship, region).map(ReadinessJson::requirement))
            })
            assertEquals(case.getValue("regions"), regions)
        }

    @TestFactory
    fun `citizenships are read as on the iPhone`(): List<DynamicTest> =
        ReadinessVectors.tests("citizenship", ::citizenshipLabel) { case ->
            val citizenship = data.citizenship
            val key = data.keys.citizenship
            when (case.text("rule")) {
                "key(forNationality:)" ->
                    assertEquals(case.textOrNull("key"), citizenship.keyForNationality(case.text("text")))
                "printed(on:)" ->
                    assertEquals(case.textOrNull("key"), citizenship.printed(values(case.obj("document"))))
                "kept(in:), of(person:documents:)" -> {
                    val person = person(case["person"], key)
                    val documents = case.getValue("documents").jsonArray.map { values(it.jsonObject) }
                    assertEquals(case.texts("kept"), citizenship.kept(person), "kept")
                    assertEquals(case.texts("of"), citizenship.of(person, documents), "of")
                    val alone = citizenship.of(person, emptyList())
                    assertEquals(case.texts("ofWithoutDocuments"), alone, "of, without documents")
                }
                "keeping(_:in:)" -> {
                    val kept = citizenship.keeping(case.texts("citizenships"), person(case["person"], key))
                    val expected = case["kept"].takeUnless { it.isNullOrMissing() }?.let { value(it.jsonObject) }
                    assertEquals(expected, kept?.get(key))
                }
                else -> error("A rule this test doesn't know: ${case.text("rule")}")
            }
        }

    @TestFactory
    fun `trips are kept as on the iPhone`(): List<DynamicTest> =
        ReadinessVectors.tests("trips", { "${it.text("rule")}: ${it.textOrNull("name") ?: it["plan"]}" }) { case ->
            fun plans(key: String) = case.getValue(key).jsonArray.map { plan(it.jsonObject) }
            fun json(plans: List<TripPlan>) = JsonArray(plans.map { ReadinessJson.plan(it) })
            when (case.text("rule")) {
                "load(today:)" -> {
                    val single = case["single"].takeUnless { it.isNullOrMissing() }?.let { plan(it.jsonObject) }
                    val storage = MemoryStorage(plans("stored"), single)
                    assertEquals(case.getValue("kept"), json(TripPlans(storage).load(parseDay(case.text("today")))))
                    assertEquals(case.bool("writes"), storage.writes > 0, "writes")
                }
                "save(_:)" -> {
                    val storage = MemoryStorage(plans("stored"), null)
                    TripPlans(storage).save(plan(case.getValue("saved").jsonObject))
                    assertEquals(case.getValue("kept"), json(storage.trips()))
                }
                "remove(_:)" -> {
                    val storage = MemoryStorage(plans("stored"), null)
                    TripPlans(storage).remove(uuid(case.text("removed")))
                    assertEquals(case.getValue("kept"), json(storage.trips()))
                }
                "isValid, isOver(by:)" -> {
                    val plan = plan(case.getValue("plan").jsonObject)
                    assertEquals(case.bool("isValid"), plan.isValid)
                    assertEquals(case.bool("isOver"), plan.isOver(parseDay(case.text("today"))))
                }
                else -> error("A rule this test doesn't know: ${case.text("rule")}")
            }
        }

    /** Trips kept in memory, counting how often the list is written. */
    private class MemoryStorage(private var kept: List<TripPlan>, private var single: TripPlan?) : TripPlanStorage {
        var writes = 0

        override fun trips(): List<TripPlan> = kept

        override fun singleTrip(): TripPlan? = single

        override fun write(trips: List<TripPlan>) {
            writes += 1
            kept = trips
            single = null
        }
    }

    // Reading what the iOS test wrote

    private fun JsonObject.obj(key: String): JsonObject = getValue(key).jsonObject

    private fun citizenshipLabel(case: JsonObject): String =
        "${case.text("rule")}: ${case.textOrNull("text") ?: case.textOrNull("name") ?: case["document"]}"

    private fun parseDay(text: String): CalendarDay = requireNotNull(CalendarDay.parse(text)) { "Not a day: $text" }

    private fun uuid(text: String): UUID = UUID.fromString(text)

    private fun JsonObject.uuidOrNull(key: String): UUID? = textOrNull(key)?.let(::uuid)

    private fun JsonObject.dayOrNull(key: String): CalendarDay? = textOrNull(key)?.let { parseDay(it) }

    private fun value(json: JsonObject): ReadinessValue = when {
        "text" in json -> ReadinessValue.Text(json.text("text"))
        "date" in json -> ReadinessValue.Day(parseDay(json.text("date")))
        "choices" in json -> ReadinessValue.Choices(json.texts("choices"))
        else -> ReadinessValue.Other
    }

    private fun values(json: JsonObject): ReadinessValues =
        ReadinessValues(
            json.mapValues { (_, element) -> if (element is JsonObject) value(element) else ReadinessValue.Other },
        )

    private fun person(json: JsonElement?, key: String): ReadinessValues =
        ReadinessValues(json.takeUnless { it.isNullOrMissing() }?.let { mapOf(key to value(it.jsonObject)) }.orEmpty())

    private fun money(json: JsonElement): Money = requireNotNull(Money.fromJson(json)) { "Not money: $json" }

    private fun obligation(json: JsonObject) = ReadinessObligation(
        id = uuid(json.text("id")),
        due = parseDay(json.text("due")),
        lastDone = json.dayOrNull("lastDone"),
        lastCycleDue = json.dayOrNull("lastCycleDue"),
        reference = json.textOrNull("reference"),
        title = json.text("title"),
        kind = json.text("kind"),
        amount = json["amount"].takeUnless { it.isNullOrMissing() }?.let(::money),
    )

    private fun section(json: JsonObject) = ReadinessAsset(
        id = uuid(json.text("id")),
        name = json.text("name"),
        templateKey = json.text("templateKey"),
        role = ReadinessRole.of(json.textOrNull("role")),
        parentId = json.uuidOrNull("parentId"),
        isSensitive = json.bool("isSensitive"),
        wasReplaced = json.bool("wasReplaced"),
        values = values(json.getValue("values").jsonObject),
        obligations = json.obj("obligations").mapValues { (_, deadline) -> obligation(deadline.jsonObject) },
        otherObligations = json.getValue("otherObligations").jsonArray.map { obligation(it.jsonObject) },
        historyCount = json.int("historyCount"),
        documentKinds = json.texts("documentKinds"),
        facts = json.getValue("facts").jsonArray.map { it.jsonObject }.map { facts ->
            val fields = facts.getValue("fields").jsonObject.mapValues { (_, field) -> field.jsonPrimitive.content }
            ReadinessFacts(facts.text("blueprintKey"), facts.text("title"), fields)
        },
    )

    private fun traveller(json: JsonElement): TripTraveller =
        if (json is JsonPrimitive && json.content == "unfiled") {
            TripTraveller.Unfiled
        } else {
            TripTraveller.Member(uuid(json.jsonObject.text("member")))
        }

    private fun plan(json: JsonObject) = TripPlan(
        id = uuid(json.text("id")),
        start = parseDay(json.text("start")),
        end = parseDay(json.text("end")),
        region = requireNotNull(TripRegion.of(json.text("region"))),
        destination = json.text("destination"),
        travellers = json.getValue("travellers").jsonArray.map(::traveller).toSet(),
        vehicles = json.texts("vehicles").map(::uuid).toSet(),
        pets = json.texts("pets").map(::uuid).toSet(),
    )

    private fun scenario(json: JsonObject): ReadinessScenario = when {
        "trip" in json -> ReadinessScenario.Trip(plan(json.getValue("trip").jsonObject))
        "sale" in json -> ReadinessScenario.Sale(uuid(json.text("sale")))
        else -> json.getValue("claim").jsonObject.let {
            ReadinessScenario.Claim(uuid(it.text("section")), it.textOrNull("blueprint"))
        }
    }

    private fun route(scenario: ReadinessScenario): ReadinessRoute = when (scenario) {
        is ReadinessScenario.Trip -> ReadinessRoute.Trip(null)
        is ReadinessScenario.Sale -> ReadinessRoute.Sale(scenario.assetID)
        is ReadinessScenario.Claim -> ReadinessRoute.Claim(scenario.assetID)
    }
}

/** What the engine gives, written as the iOS test writes it, to compare with its answers. */
internal object ReadinessJson {
    private fun text(text: String?): JsonElement = text?.let(::JsonPrimitive) ?: JsonNull

    private fun id(id: UUID?): JsonElement = text(id?.written)

    private fun day(day: CalendarDay?): JsonElement = text(day?.isoString)

    private fun strings(values: List<String>) = JsonArray(values.map(::JsonPrimitive))

    /** [json] with every amount written in this app's stored form, so an amount is compared by its value. */
    fun normalizingMoney(json: JsonElement): JsonElement = when (json) {
        is JsonObject -> JsonObject(
            json.mapValues { (key, value) ->
                if (key == "money") requireNotNull(Money.fromJson(value)).toJson() else normalizingMoney(value)
            },
        )
        is JsonArray -> JsonArray(json.map(::normalizingMoney))
        else -> json
    }

    fun words(words: ReadinessWords): JsonObject = JsonObject(
        mapOf(
            "phrase" to JsonPrimitive(words.phrase.raw),
            "arguments" to JsonArray(
                words.arguments.map { argument ->
                    when (argument) {
                        is ReadinessArgument.Day -> JsonObject(mapOf("day" to JsonPrimitive(argument.day.isoString)))
                        is ReadinessArgument.Number -> JsonObject(mapOf("number" to JsonPrimitive(argument.number)))
                        is ReadinessArgument.Text -> JsonObject(mapOf("text" to JsonPrimitive(argument.text)))
                        is ReadinessArgument.Amount -> JsonObject(mapOf("money" to argument.money.toJson()))
                    }
                },
            ),
        ),
    )

    private fun action(action: ReadinessAction?): JsonElement = when (action) {
        null -> JsonNull
        is ReadinessAction.Open -> JsonObject(
            mapOf(
                "open" to JsonObject(
                    when (val target = action.target) {
                        is ReadinessTarget.Section -> mapOf("section" to id(target.id))
                        is ReadinessTarget.Deadline -> mapOf("deadline" to id(target.id))
                    },
                ),
            ),
        )
        is ReadinessAction.AddPersonalDocument -> JsonObject(mapOf("addPersonalDocument" to id(action.holderID)))
        is ReadinessAction.AddDocument -> JsonObject(mapOf("addDocument" to id(action.assetID)))
        is ReadinessAction.AddDeadline -> JsonObject(
            mapOf(
                "addDeadline" to JsonObject(
                    mapOf("section" to id(action.assetID), "blueprint" to JsonPrimitive(action.blueprintKey)),
                ),
            ),
        )
        is ReadinessAction.EditSection -> JsonObject(mapOf("editSection" to id(action.assetID)))
        is ReadinessAction.ChooseCitizenship -> JsonObject(mapOf("chooseCitizenship" to id(action.holderID)))
    }

    private fun item(item: ReadinessItem) = JsonObject(
        mapOf(
            "id" to JsonPrimitive(item.id),
            "status" to JsonPrimitive(item.status.name.lowercase()),
            "need" to JsonPrimitive(item.need.name.lowercase()),
            "title" to words(item.title),
            "detail" to words(item.detail),
            "action" to action(item.action),
        ),
    )

    private fun policy(policy: ReadinessPolicy?): JsonElement = policy?.let {
        JsonObject(
            mapOf(
                "blueprintKey" to JsonPrimitive(it.blueprintKey),
                "title" to JsonPrimitive(it.title),
                "whenToUse" to (it.whenToUse?.let(::words) ?: JsonNull),
                "insurer" to text(it.insurer),
                "policyNumber" to text(it.policyNumber),
                "claimsPhone" to text(it.claimsPhone),
                "deadlineID" to id(it.deadlineID),
                "validUntil" to day(it.validUntil),
                "policyholderClass" to text(it.policyholderClass),
            ),
        )
    } ?: JsonNull

    fun checklist(checklist: ReadinessChecklist) = JsonObject(
        mapOf(
            "groups" to JsonArray(
                checklist.groups.map { group ->
                    JsonObject(
                        mapOf(
                            "id" to JsonPrimitive(group.id),
                            "title" to words(group.title),
                            "symbol" to JsonPrimitive(group.symbol),
                            "items" to JsonArray(group.items.map(::item)),
                        ),
                    )
                },
            ),
            "items" to strings(checklist.items.map { it.id }),
            "policy" to policy(checklist.policy),
            "policyOptions" to JsonArray(checklist.policyOptions.map(::policy)),
            "attentionCount" to JsonPrimitive(checklist.attentionCount),
            "missingCount" to JsonPrimitive(checklist.missingCount),
            "isAllReady" to JsonPrimitive(checklist.isAllReady),
        ),
    )

    fun candidates(candidates: TripCandidates) = JsonObject(
        mapOf(
            "travellers" to JsonArray(
                candidates.travellers.map {
                    JsonObject(mapOf("traveller" to traveller(it.traveller), "name" to words(it.name)))
                },
            ),
            "vehicles" to JsonArray(candidates.vehicles.map(::option)),
            "pets" to JsonArray(candidates.pets.map(::option)),
        ),
    )

    private fun option(option: TripCandidates.Option) =
        JsonObject(mapOf("id" to id(option.id), "name" to JsonPrimitive(option.name)))

    private fun traveller(traveller: TripTraveller): JsonElement = when (traveller) {
        is TripTraveller.Member -> JsonObject(mapOf("member" to id(traveller.id)))
        TripTraveller.Unfiled -> JsonPrimitive("unfiled")
    }

    fun plan(plan: TripPlan, withID: Boolean = true): JsonObject {
        val fields = mutableMapOf(
            "start" to day(plan.start),
            "end" to day(plan.end),
            "region" to JsonPrimitive(plan.region.raw),
            "destination" to JsonPrimitive(plan.destination),
            "travellers" to JsonArray(plan.travellers.sortedBy { it.key }.map(::traveller)),
            "vehicles" to strings(plan.vehicles.map { it.written }.sorted()),
            "pets" to strings(plan.pets.map { it.written }.sorted()),
        )
        if (withID) fields["id"] = id(plan.id)
        return JsonObject(fields)
    }

    fun requirement(requirement: TravelRequirement) = JsonObject(
        mapOf(
            "need" to JsonPrimitive(requirement.need.raw),
            "accepted" to strings(requirement.accepted),
            "countsTravelCutoff" to JsonPrimitive(requirement.countsTravelCutoff),
            "monthsValidAfterReturn" to JsonPrimitive(requirement.monthsValidAfterReturn),
        ),
    )
}
