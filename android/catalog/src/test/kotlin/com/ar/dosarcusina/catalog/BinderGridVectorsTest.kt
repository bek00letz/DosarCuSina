package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.catalog.BinderLayout.CategoryInfo
import com.ar.dosarcusina.catalog.BinderLayout.SectionInfo
import com.ar.dosarcusina.core.attention.SectionNoun
import com.ar.dosarcusina.core.values.MachineText
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/**
 * The binder grid's data ([BinderLayout.holds], [BinderLayout.defaultOrder],
 * [BinderLayout.addBoxNames]) and what „Adaugă o secțiune” offers ([SectionOffers]), pinned
 * against the iOS app's answers in shared/test-vectors/attention/ (by
 * ios/DosarCuSinaTests/AttentionVectorsTests.swift). Placeholder data only.
 */
class BinderGridVectorsTest {
    private companion object {
        const val WRITE = "TEST_RUNNER_ATTENTION_VECTORS_WRITE"
    }

    private fun cases(name: String): List<JsonObject> {
        val shared = checkNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared to shared/" }
        val file = File(shared, "test-vectors/attention/$name.json")
        check(file.isFile) { "${file.path} is missing: run the iOS AttentionVectorsTests with $WRITE=1" }
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content

    private fun JsonObject.textOrNull(key: String): String? =
        this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

    private fun JsonObject.int(key: String): Int = text(key).toInt()

    private fun JsonObject.bool(key: String): Boolean = text(key).toBooleanStrict()

    private fun JsonObject.texts(key: String): List<String> = getValue(key).jsonArray.map { it.jsonPrimitive.content }

    private fun JsonObject.objects(key: String): List<JsonObject> = getValue(key).jsonArray.map { it.jsonObject }

    private fun JsonObject.moment(key: String): Instant = Instant.ofEpochSecond(text(key).toLong())

    private fun category(json: JsonObject) = CategoryInfo(
        key = json.text("key"),
        name = json.text("name"),
        homeOrder = json.int("homeOrder"),
        isOnHome = json.bool("isOnHome"),
        behavior = Behavior(
            box = checkNotNull(Box.of(json.text("box"))) { "${json.text("box")} isn't a box" },
            role = json.textOrNull("role")?.let { checkNotNull(Role.of(it)) { "$it isn't a role" } },
            addedOnlyUnderParent = json.bool("addedOnlyUnderParent"),
            shortlistOrder = json.textOrNull("shortlistOrder")?.toInt(),
        ),
        groupsSections = json.bool("groupsSections"),
        createdAt = json.moment("createdAt"),
    )

    private fun section(json: JsonObject) = SectionInfo(
        id = UUID.fromString(json.text("id")),
        templateKey = json.text("templateKey"),
        isTopLevel = json.bool("isTopLevel"),
        createdAt = json.moment("createdAt"),
    )

    @TestFactory
    fun `what Adauga o sectiune offers`(): List<DynamicTest> = cases("section-offers").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val categories = case.objects("categories").map(::category)
            val offers = SectionOffers.of(categories)
            assertEquals(case.texts("shortlist"), offers.shortlist.map { it.key }, "Cele mai des folosite")
            assertEquals(case.texts("others"), offers.others.map { it.key }, "Alte categorii")
            assertEquals(case.texts("inOrder"), offers.inOrder.map { it.key })
            val groups = case.getValue("groups").jsonObject
            for (category in categories) {
                val raw = groups.getValue(category.key)
                val expected = if (raw is JsonNull) null else raw.jsonPrimitive.content
                assertEquals(expected, SectionOffers.group(category.behavior)?.name?.lowercase(), category.key)
            }
        }
    }

    @TestFactory
    fun `the binder's boxes and the add box`(): List<DynamicTest> = cases("binder-grid").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val categories = case.objects("categories").map(::category)
            val sections = case.objects("sections").map(::section)
            val byKey = categories.associateBy { it.key }
            val offered = case.texts("offered").map { byKey.getValue(it) }
            val holding = categories.filter { BinderLayout.holdsAnything(it, byKey, sections) }.map { it.key }
            assertEquals(case.texts("holdsAnything"), holding, "What holds something")
            val order = BinderLayout.defaultOrder(categories, sections, case.bool("hasContacts"))
            assertEquals(case.texts("defaultOrder"), order.map { it.storageKey }, "The boxes")
            val names = case.getValue("addBoxNames").jsonObject
            assertEquals(
                BinderLayout.AddBoxNames(names.texts("names"), names.bool("more")),
                BinderLayout.addBoxNames(offered, categories, sections),
                "The add box",
            )
        }
    }

    @Test
    fun `a box counts a category's sections in its noun, or as sections`() {
        assertEquals(SectionNoun.PLANT, Behavior(sectionNoun = "plant").noun)
        assertEquals(SectionNoun.ESPRESSO_MACHINE, Behavior(sectionNoun = "espressoMachine").noun)
        assertEquals(null, Behavior(sectionNoun = "boat").noun, "A noun a newer build wrote counts them as sections")
        assertEquals(null, Behavior().noun)
        val nouns = Catalog.builtIn.all.mapNotNull { Behavior.of(it.behavior).sectionNoun }
        for (raw in nouns) assertEquals(raw, SectionNoun.of(raw)?.raw, "The catalog's $raw is a noun this build knows")
    }
}
