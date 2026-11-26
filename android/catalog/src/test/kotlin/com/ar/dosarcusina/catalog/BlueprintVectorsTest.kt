package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.io.File

/**
 * The iOS app's answers for what a category's usual deadlines say and the facts a deadline's page puts
 * at hand (shared/test-vectors/deadlines/blueprints.json and facts.json, written by
 * ios/DosarCuSinaTests/DeadlineVectorsTests.swift), over this build's catalog, which the iOS app exported.
 */
class BlueprintVectorsTest {
    private fun cases(name: String): List<JsonObject> {
        val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
        val file = File(shared, "test-vectors/deadlines/$name.json")
        check(file.isFile) {
            "${file.path} is missing: run the iOS DeadlineVectorsTests with TEST_RUNNER_DEADLINE_VECTORS_WRITE=1"
        }
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content

    private fun JsonObject.textOrNull(key: String): String? =
        this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

    private fun JsonObject.bool(key: String): Boolean = text(key).toBooleanStrict()

    private fun values(json: JsonElement?): FieldValues =
        json?.let { requireNotNull(FieldValues.codec.decode(it)) } ?: FieldValues()

    private fun profile(json: JsonElement): ReminderProfile = requireNotNull(ReminderProfile.codec.decode(json))

    private fun blueprints(category: String) =
        requireNotNull(Catalog.builtIn.definition(category)) { "No built-in $category" }.blueprints

    private val today = CalendarDay(2026, 11, 26)
    private val yesterday = CalendarDay(2026, 11, 25)

    @TestFactory
    fun blueprints(): List<DynamicTest> = cases("blueprints").mapIndexed { index, case ->
        DynamicTest.dynamicTest("blueprints #$index: ${case.text("blueprint")}") {
            val blueprint = blueprints(case.text("category")).first { it.key == case.text("blueprint") }
            if ("remindersFor" in case) {
                val values = values(case["values"])
                assertEquals(profile(case.getValue("remindersFor")), blueprint.remindersFor(values))
                assertEquals(case.bool("worthYesterdayFor"), blueprint.isWorthScheduling(yesterday, today, values))
                return@dynamicTest
            }
            assertEquals(case.text("completion"), blueprint.completionKind.raw)
            assertEquals(case.bool("isFieldDriven"), blueprint.isFieldDriven)
            assertEquals(case.textOrNull("drivingField"), blueprint.drivingField)
            val facts = case.getValue("facts").jsonObject.mapValues { it.value.jsonPrimitive.content }
            assertEquals(facts, blueprint.factFields?.fields.orEmpty().mapKeys { it.key.raw })
            assertEquals(case.bool("worthYesterday"), blueprint.isWorthScheduling(yesterday, today))
            assertEquals(case.bool("worthToday"), blueprint.isWorthScheduling(today, today))
            assertEquals(profile(case.getValue("reminders")), blueprint.remindersFor(FieldValues()))
        }
    }

    @TestFactory
    fun facts(): List<DynamicTest> = cases("facts").mapIndexed { index, case ->
        DynamicTest.dynamicTest("facts #$index: ${case.textOrNull("blueprint")}") {
            val found = DeadlineFacts.of(
                case.textOrNull("blueprint"), blueprints(case.text("category")), values(case["values"]),
                case.textOrNull("reference"),
            )
            val expected = case.getValue("facts").jsonObject
            assertEquals(expected.textOrNull("insurer"), found.insurer)
            assertEquals(expected.textOrNull("policyNumber"), found.policyNumber)
            assertEquals(expected.textOrNull("claimsPhone"), found.claimsPhone)
            assertEquals(expected.textOrNull("policyholder"), found.policyholder)
            val sum = expected["insuredSum"]?.takeUnless { it is JsonNull }?.let(Money::fromJson)
            assertEquals(sum?.amount, found.insuredSum?.amount)
            assertEquals(sum?.currency, found.insuredSum?.currency)
        }
    }
}
