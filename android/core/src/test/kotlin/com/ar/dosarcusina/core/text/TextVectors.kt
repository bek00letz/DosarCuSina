package com.ar.dosarcusina.core.text

import com.ar.dosarcusina.core.values.VectorFolder
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The text rules' answers, in shared/test-vectors/text/, written by
 * ios/DosarCuSinaTests/TextVectorsTests.swift: the card rule, the IBAN check, `RomanianText`'s
 * comparing and `TextPattern`.
 */
object TextVectors : VectorFolder(
    folderName = "text",
    files = setOf(
        "card-number-keeps-whole", "card-number-kept-whole", "card-number-last-four", "card-number-luhn",
        "card-number-redact", "card-number-redacting-json", "card-number-sanitizing", "free-text-mask", "iban",
        "romanian-text-compact", "romanian-text-contains-word", "romanian-text-words", "text-pattern",
    ),
    writtenBy = "the iOS TextVectorsTests with TEST_RUNNER_TEXT_VECTORS_WRITE=1",
)

/**
 * The numbers a case needs that pass a check, built when the test runs as the iOS test builds
 * them (`TextVectorsTests.Built`), so the repository never holds one: `{luhn:DIGITS}` is DIGITS as
 * written with the Luhn check digit after them; `{iban:CC:BBAN}` the IBAN of country CC with that
 * BBAN and its check digits; `{iban4:CC:BBAN}` the same in groups of four; `{fours:DIGITS}` DIGITS
 * in groups of four. Answers name the same tokens, so both sides are built alike.
 */
object Built {
    private val token = Regex("""\{(luhn|iban|iban4|fours):([^{}]*)\}""")
    private const val MODULUS = 97
    private const val LETTER_OFFSET = 55

    fun expand(template: String): String = token.replace(template) { match ->
        val (kind, content) = match.destructured
        when (kind) {
            "luhn" -> content + checkDigit(content.filter(Char::isDigit))
            "fours" -> grouped(content)
            else -> {
                val (country, bban) = content.split(":", limit = 2)
                val iban = country + checkDigits(country, bban) + bban
                if (kind == "iban4") grouped(iban) else iban
            }
        }
    }

    private fun checkDigit(digits: String): Int {
        val sum = digits.reversed().withIndex().sumOf { (index, character) ->
            val digit = character - '0'
            val doubled = if (index % 2 == 0) digit * 2 else digit
            if (doubled > 9) doubled - 9 else doubled
        }
        return (10 - sum % 10) % 10
    }

    private fun checkDigits(country: String, bban: String): String {
        var remainder = 0
        for (character in bban + country + "00") {
            val value = if (character.isDigit()) character.toString() else (character.code - LETTER_OFFSET).toString()
            for (digit in value) remainder = (remainder * 10 + (digit - '0')) % MODULUS
        }
        return (98 - remainder).toString().padStart(2, '0')
    }

    private fun grouped(text: String): String = text.chunked(4).joinToString(" ")
}

class TextVectorFilesTest {
    @Test
    fun `every file of answers is read by a test`() {
        val files = TextVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
        val present = files.map { it.nameWithoutExtension }.toSet()
        assertEquals(TextVectors.files, present, "Each file of answers needs its test, and each test its file")
    }

    @Test
    fun `a built number passes its check`() {
        assertTrue(CardNumberRuns.passesLuhn(Built.expand("{luhn:64200000000123}")))
        assertTrue(IBAN.isValid(Built.expand("{iban4:RO:AAAA4111111111111111}")))
        assertEquals("5555 5555 5555 4444", Built.expand("{fours:5555555555554444}"))
    }
}
