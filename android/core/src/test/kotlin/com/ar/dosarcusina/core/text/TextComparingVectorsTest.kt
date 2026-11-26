package com.ar.dosarcusina.core.text

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.asTextOrNull
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/** IBANs, `RomanianText`'s comparing and the patterns the rules are written in give the iOS app's answers. */
class TextComparingVectorsTest {
    @TestFactory
    fun `IBANs are checked and found as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("iban", { label(it, "text") }) { case ->
            val text = Built.expand(case.text("text"))
            assertEquals(case.bool("isValid"), IBAN.isValid(text), "isValid")
            val expected = case.getValue("ranges").jsonArray.map { range ->
                val found = range.jsonObject
                found.int("at") to Built.expand(found.text("text"))
            }
            assertEquals(expected, IBAN.ranges(text).map { it.first to text.substring(it) }, "ranges")
        }

    @TestFactory
    fun `values compact as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("romanian-text-compact", { label(it, "input") }) { case ->
            assertEquals(case.text("compact"), RomanianText.compact(case.text("input")))
        }

    @TestFactory
    fun `text splits into words as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("romanian-text-words", { label(it, "input") }) { case ->
            assertEquals(case.texts("words"), RomanianText.words(case.text("input")))
        }

    @TestFactory
    fun `keywords are found as on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("romanian-text-contains-word", { "${it.text("phrase")} in ${it.text("text")}" }) { case ->
            val match = when (case.textOrNull("match")) {
                "word" -> RomanianText.WordMatch.WORD
                "stem" -> RomanianText.WordMatch.STEM
                else -> null
            }
            val natural = RomanianText.WordMatch.natural(RomanianText.fold(case.text("phrase")))
            assertEquals(case.text("natural"), natural.name.lowercase(), "natural")
            val found = RomanianText.containsWord(case.text("phrase"), case.text("text"), match)
            assertEquals(case.bool("found"), found, "found")
        }

    @TestFactory
    fun `patterns match as ICU's do on the iPhone`(): List<DynamicTest> =
        TextVectors.tests("text-pattern", { "${it.text("pattern")} in ${it.text("text")}" }) { case ->
            val expected = case.getValue("matches").jsonArray.map { match ->
                val found = match.jsonObject
                val groups = found.getValue("groups").jsonArray.map { it.asTextOrNull() }
                Triple(found.int("at"), found.int("length"), groups)
            }
            val matches = TextPattern.matches(case.text("pattern"), case.text("text"), case.bool("caseInsensitive"))
            assertEquals(expected, matches.map { Triple(it.range.first, it.range.count(), it.groups) })
        }
}
