package com.ar.dosarcusina.core.text

import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.ints
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/** The card rule gives the iOS app's answers for every case in shared/test-vectors/text/. */
class CardNumberVectorsTest {
    private val nothing = { PaymentCardNumbers.KeptWhole.NOTHING }

    @TestFactory
    fun `card numbers are masked as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("card-number-redact", { label(it, "text") }) { case ->
            val text = Built.expand(case.text("text"))
            assertEquals(Built.expand(case.text("redacted")), PaymentCardNumbers.redact(text), "redacted")
            assertEquals(Built.expand(case.text("strict")), PaymentCardNumbers.redact(text, strict = true), "strict")
            assertEquals(case.bool("contains"), PaymentCardNumbers.containsCardNumber(text), "contains")
            assertEquals(case.textOrNull("lastFour"), PaymentCardNumbers.lastFour(text), "lastFour")
            val lastFourStrict = PaymentCardNumbers.lastFour(text, strict = true)
            assertEquals(case.textOrNull("lastFourStrict"), lastFourStrict, "lastFourStrict")
        }

    @TestFactory
    fun `the check digit and the networks are read as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("card-number-luhn", { label(it, "digits") }) { case ->
            val digits = Built.expand(case.text("digits"))
            assertEquals(case.bool("passesLuhn"), CardNumberRuns.passesLuhn(digits), "passesLuhn")
            assertEquals(case.textOrNull("network"), PaymentCardNumbers.network(digits), "network")
            val lengths = if (case.isNull("lengths")) null else case.ints("lengths")
            val brand = CardNumberRuns.brand(digits)
            assertEquals(lengths, brand?.let { listOf(it.lengths.first, it.lengths.last) }, "lengths")
        }

    @TestFactory
    fun `only the last four digits are kept as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("card-number-last-four", { label(it, "value") }) { case ->
            assertEquals(case.textOrNull("lastFour"), PaymentCardNumbers.lastFourOf(case.text("value")))
        }

    @TestFactory
    fun `a field's type keeps its value whole as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("card-number-keeps-whole", { label(it, "text") }) { case ->
            val text = Built.expand(case.text("text"))
            assertEquals(case.bool("keepsWhole"), PaymentCardNumbers.keepsWhole(text, case.textOrNull("type")))
        }

    @TestFactory
    fun `a section's own values stay whole in its words as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("card-number-kept-whole", { label(it, "text") }) { case ->
            val values = case.getValue("values").jsonArray.map { value ->
                val entry = value.jsonObject
                PaymentCardNumbers.TypedText(Built.expand(entry.text("text")), entry.text("type"))
            }
            val kept = PaymentCardNumbers.KeptWhole.typed(values)
            val text = Built.expand(case.text("text"))
            assertEquals(case.bool("isEmpty"), kept.isEmpty, "isEmpty")
            val strict = PaymentCardNumbers.redact(text, strict = true, keeping = kept)
            val redacted = PaymentCardNumbers.redact(text, keeping = kept)
            assertEquals(Built.expand(case.text("redacted")), redacted, "redacted")
            assertEquals(Built.expand(case.text("strict")), strict, "strict")
            assertEquals(case.bool("contains"), PaymentCardNumbers.containsCardNumber(text, keeping = kept), "contains")
        }

    @TestFactory
    fun `a section's values are sanitized as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("card-number-sanitizing", { it.getValue("values").toString().take(60) }) { case ->
            val entries = case.getValue("values").jsonObject.mapValues { it.value.jsonObject }
            val texts = entries.mapValues { Built.expand(it.value.text("text")) }
            val fields = entries.toSortedMap().mapNotNull { (key, entry) ->
                entry.textOrNull("type")?.let { PaymentCardNumbers.TypedField(key, it) }
            }
            val sealed = case.getValue("sealed").jsonArray.map { texts.getValue(it.jsonPrimitive.content) }.toSet()
            var fieldsRead = 0
            val changes = PaymentCardNumbers.sanitizing(texts, { fieldsRead += 1; fields }, { it in sealed })
            val after = texts.keys.associateWith { key -> if (key in changes) changes[key] else texts[key] }
            val expected = case.getValue("sanitized").jsonObject.mapValues { (_, value) ->
                if (value is JsonNull) null else Built.expand(value.jsonPrimitive.content)
            }
            assertEquals(expected, after)
            assertTrue(fieldsRead <= 1, "The fields are read once at most")
        }

    @TestFactory
    fun `JSON a newer build wrote is masked as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("card-number-redacting-json", { label(it, "json") }) { case ->
            val sealed = case.getValue("sealed").jsonArray.map { it.jsonPrimitive.content }.toSet()
            val redacted = PaymentCardNumbers.redacting(case.getValue("json")) { it in sealed }
            assertTrue(JsonTrees.same(case.getValue("redacted"), redacted), "$redacted")
        }

    @TestFactory
    fun `a record's words are masked as the unit of work masks them on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("free-text-mask", { label(it, "before") }) { case ->
            when (case.text("kind")) {
                "text" -> {
                    val masked = FreeTextMasking.masked(Built.expand(case.text("before")), nothing)
                    assertEquals(case.textOrNull("masked")?.let(Built::expand), masked)
                }
                else -> {
                    val before = case.getValue("before").jsonArray.map { Built.expand(it.jsonPrimitive.content) }
                    val expected = if (case.isNull("masked")) null else case.texts("masked").map(Built::expand)
                    assertEquals(expected, FreeTextMasking.masked(before, nothing))
                }
            }
        }
}
