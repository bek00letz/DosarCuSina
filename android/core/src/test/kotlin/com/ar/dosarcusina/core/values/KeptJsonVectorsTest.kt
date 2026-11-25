package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * Values a newer version wrote, kept raw and written back by the one rule, pinned against the
 * iOS app's answers. Placeholder data only.
 */
class KeptJsonVectorsTest {
    @TestFactory
    fun `an edit is laid over what was stored by the one rule`(): List<DynamicTest> =
        Vectors.tests("json-laying", { label(it, "name") }) { case ->
            val written = KeptJson.laying(case.getValue("edited"), case.getValue("stored"), case.getValue("read"))
            assertSameJson(case.getValue("written"), written)
        }

    @TestFactory
    fun `an exit's rule reaches what this build doesn't read`(): List<DynamicTest> =
        Vectors.tests("json-mapping-kept", { label(it, "name") }) { case ->
            val rule = transform(case.text("transform"))
            val written = KeptJson.mappingKept(case.getValue("stored"), case.getValue("read"), rule)
            assertSameJson(case.getValue("written"), written)
        }

    @TestFactory
    fun `a form saves only what was changed in it`(): List<DynamicTest> =
        Vectors.tests("three-way", { label(it, "name", "value") }) { case ->
            if (case.containsKey("value")) {
                val (edited, stored, base) = case.texts("value")
                assertEquals(case.text("written"), ThreeWay.value(edited, stored, base))
                return@tests
            }
            val written = ThreeWay.laying(case.getValue("edited"), case.getValue("stored"), case.getValue("base"))
            assertSameJson(case.getValue("written"), written)
        }

    @TestFactory
    fun `a list keeps the entries it can't read, in their places`(): List<DynamicTest> =
        Vectors.tests("kept-list", { label(it, "name") }) { case ->
            val read = KeptList.read(case.getValue("stored"), RowCodec, Row::id)
            assertEquals(case.getValue("items").jsonArray.map { requireNotNull(RowCodec.decode(it)) }, read.items)
            assertEquals(case.ints("unreadablePositions"), read.unreadable.map { it.position })
            assertEquals(case.bool("isFullyRead"), read.isFullyRead)
            assertEquals(case.texts("identities"), read.identities.sortedWith(CodePointOrder))
            val argument = case.getValue("argument")
            val result = when (case.text("operation")) {
                "replaceItems" -> read.replacingItems(argument.jsonArray.map { requireNotNull(RowCodec.decode(it)) })
                "mappingKept" -> read.mappingKept(transform(argument.asTextOrNull().orEmpty()))
                "replaceEntries" -> read.replacingEntries(KeptList.read(argument, RowCodec, Row::id))
                "filtered" -> read.filtered({ it.id != argument.asTextOrNull() }, { KeptJson.keptIdentity(it) != null })
                else -> read
            }
            assertSameJson(case.getValue("written"), result.toJson())
        }

    @TestFactory
    fun `an object keeps what it can't read`(): List<DynamicTest> =
        Vectors.tests("kept-object", { label(it, "name") }) { case ->
            val fallback = Rule("none")
            var kept = if (case.isNull("stored")) {
                KeptObject.made(fallback, RuleCodec)
            } else {
                KeptObject.read(case.getValue("stored"), RuleCodec, fallback)
            }
            assertSameJson(case.getValue("value"), RuleCodec.encode(kept.value))
            assertEquals(case.bool("keepsMore"), kept.keepsMore)
            if (!case.isNull("edited")) {
                val rule = requireNotNull(RuleCodec.decode(case.getValue("edited")))
                kept = if (case.isNull("stored")) KeptObject.made(rule, RuleCodec) else kept.replacingValue(rule)
            }
            case.textOrNull("transform")?.let { kept = kept.mappingKept(transform(it)) }
            assertSameJson(case.getValue("written"), kept.json)
            assertEquals(case.bool("keepsMoreWritten"), kept.keepsMore)
        }

    /** The same JSON, keys in any order, each number's text as written. */
    private fun assertSameJson(expected: JsonElement, actual: JsonElement) {
        assertEquals(expected, actual, "Expected ${MachineText.json(expected)}\n     got ${MachineText.json(actual)}")
        assertTrue(JsonTrees.same(expected, actual))
    }

    /** The exits' rules the vectors use, as the iOS test names them. */
    private fun transform(name: String): (JsonElement) -> JsonElement? = when (name) {
        "upper" -> { value -> JsonTrees.mappingStrings(value) { it.uppercase() } }
        "dropSealed" -> { value ->
            value.takeUnless { JsonTrees.containsString(it) { text -> text.startsWith(SEALED) } }
        }
        else -> { value -> value }
    }

    private companion object {
        const val SEALED = "sealed:v1:"
    }

    /** A row as a list keeps it, as the iOS test's `Row`: read only when its id and label are text. */
    data class Row(val id: String, val label: String, val isSensitive: Boolean? = null)

    /** `Row`'s Swift Codable: id and label text, isSensitive a yes or no when there (null is missing). */
    object RowCodec : JsonCodec<Row> {
        override fun decode(json: JsonElement): Row? {
            val fields = json as? JsonObject ?: return null
            val id = fields.textField("id") ?: return null
            val label = fields.textField("label") ?: return null
            val sensitive = fields["isSensitive"]
            val isSensitive = when {
                sensitive.isNullOrMissing() -> null
                sensitive is JsonPrimitive && !sensitive.isString && sensitive.content == "true" -> true
                sensitive is JsonPrimitive && !sensitive.isString && sensitive.content == "false" -> false
                else -> return null
            }
            return Row(id, label, isSensitive)
        }

        override fun encode(value: Row): JsonElement = JsonObject(
            buildMap {
                put("id", JsonPrimitive(value.id))
                put("label", JsonPrimitive(value.label))
                value.isSensitive?.let { put("isSensitive", JsonPrimitive(it)) }
            },
        )
    }

    /** A rule as an object keeps it, as the iOS test's `Rule`: read only when its type is text. */
    data class Rule(val type: String, val every: Long? = null, val unit: String? = null)

    /** `Rule`'s Swift Codable: type text, every a whole number and unit text when there. */
    object RuleCodec : JsonCodec<Rule> {
        override fun decode(json: JsonElement): Rule? {
            val fields = json as? JsonObject ?: return null
            val type = fields.textField("type") ?: return null
            val every = when (val value = fields["every"]) {
                null, is JsonNull -> null
                is JsonPrimitive -> {
                    if (value.isString) return null
                    (JsonNumber.read(value.content) as? JsonNumber.Whole)?.value ?: return null
                }
                else -> return null
            }
            val unit = when (val value = fields["unit"]) {
                null, is JsonNull -> null
                is JsonPrimitive -> if (value.isString) value.content else return null
                else -> return null
            }
            return Rule(type, every, unit)
        }

        override fun encode(value: Rule): JsonElement = JsonObject(
            buildMap {
                put("type", JsonPrimitive(value.type))
                value.every?.let { put("every", JsonPrimitive(it)) }
                value.unit?.let { put("unit", JsonPrimitive(it)) }
            },
        )
    }
}

private fun JsonObject.textField(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
