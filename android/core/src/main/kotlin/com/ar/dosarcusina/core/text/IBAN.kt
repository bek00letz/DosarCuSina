package com.ar.dosarcusina.core.text

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.TextRules

/**
 * An IBAN (ISO 13616), as a field checks it and as the card rule leaves it whole wherever it is
 * printed ([PaymentCardNumbers]), as the iOS app's `IBAN` (ios/Shared/IBAN.swift).
 */
object IBAN {
    /**
     * How many characters an IBAN has in each country that issues them, as the ISO 13616 registry
     * lists them: each country's letters, then its length. A country not listed is checked by its
     * check digits alone.
     */
    private const val REGISTRY =
        "AD24 AE23 AL28 AT20 AZ28 BA20 BE16 BG22 BH22 BR29 BY28 CH21 CR22 CY28 CZ24 DE22 DJ27 DK18 DO28 EE20 " +
            "EG29 ES24 FI18 FK18 FO18 FR27 GB22 GE22 GI23 GL18 GR27 GT28 HR21 HU28 IE22 IL23 IQ23 IS26 IT27 JO30 " +
            "KW30 KZ20 LB28 LC32 LI21 LT20 LU20 LV21 LY25 MC27 MD24 ME22 MK19 MN20 MR27 MT31 MU30 NL18 NO15 OM23 " +
            "PK24 PL28 PS29 PT25 QA29 RO24 RS22 RU33 SA24 SC31 SD18 SE24 SI19 SK24 SM27 SO23 ST25 SV28 TL23 TN24 " +
            "TR26 UA29 VA22 VG24 XK20 YE30"

    /** The countries that issue IBANs, with how many characters each one's have. */
    val lengths: Map<String, Int> = REGISTRY.split(' ').associate { it.take(2) to it.drop(2).toInt() }

    private const val SHORTEST = 15
    private const val LONGEST = 34
    private const val HEAD = 4
    private const val CHECK_FIRST = 2
    private const val CHECK_LAST = 3
    private const val MODULUS = 97
    private const val LETTER_OFFSET = 55
    private const val DECIMAL = 10

    /**
     * ISO 13616 check: two letters for the country, two check digits, the country's length
     * ([lengths]), then the first four characters moved to the end and checked mod 97.
     */
    fun isValid(raw: String): Boolean {
        val iban = TextRules.characters(RomanianText.compact(raw))
        if (iban.size !in SHORTEST..LONGEST || !iban.all(::isASCII)) return false
        val head = iban.take(HEAD)
        if (!startsLikeAnIBAN(head)) return false
        val length = lengths[head[0] + head[1]]
        if (length != null && iban.size != length) return false
        var remainder = 0
        for (character in iban.drop(HEAD) + head) {
            // Each character is one ASCII letter or digit by now: compacted, all ASCII.
            val code = character[0]
            val chunk = if (code in '0'..'9') character else (code.code - LETTER_OFFSET).toString()
            for (digit in chunk) remainder = (remainder * DECIMAL + (digit - '0')) % MODULUS
        }
        return remainder == 1
    }

    /** Two letters for the country and two check digits. */
    private fun startsLikeAnIBAN(head: List<String>): Boolean =
        TextRules.isLetter(head[0]) && TextRules.isLetter(head[1]) &&
            TextRules.isNumber(head[CHECK_FIRST]) && TextRules.isNumber(head[CHECK_LAST])

    /**
     * Where the text holds an IBAN that passes its check ([isValid]), however its groups are
     * spaced: in one piece, in groups of four, with a space or a dash between any of its
     * characters after the first four. It starts a word with a listed country's letters and its
     * two check digits ("RO49"), and is taken at that country's length ([lengths]), so a word that
     * happens to be two letters ("de", "cu") never starts one. Ranges are in UTF-16 code units.
     */
    fun ranges(text: String): List<IntRange> = Scan(text).ranges()

    /** A character Swift calls ASCII: one ASCII scalar, or a carriage return and line feed. */
    private fun isASCII(character: String): Boolean =
        (character.length == 1 && character[0].code < ASCII_END) || character == "\r\n"

    private const val ASCII_END = 0x80

    /** One text read character by character, as Swift's `Array(text.indices)` gives them. */
    private class Scan(private val text: String) {
        private val characters = TextRules.characters(text)
        private val starts = characters.runningFold(0) { offset, character -> offset + character.length }

        private fun character(offset: Int): String? = characters.getOrNull(offset)

        private fun isWordCharacter(offset: Int): Boolean =
            character(offset)?.let { TextRules.isLetter(it) || TextRules.isNumber(it) } ?: false

        private fun isCode(offset: Int): Boolean =
            character(offset)?.let { isASCII(it) && (TextRules.isLetter(it) || TextRules.isNumber(it)) } ?: false

        private fun isSeparator(offset: Int): Boolean = character(offset).let { it == " " || it == "-" }

        private fun isASCIIDigit(offset: Int): Boolean =
            character(offset)?.let { isASCII(it) && TextRules.isNumber(it) } ?: false

        /** The offset just after the IBAN that starts at [start], if one does. */
        private fun end(start: Int): Int? {
            val first = character(start) ?: return null
            val second = character(start + 1) ?: return null
            val length = lengths[(first + second).uppercase()] ?: return null
            if (!isASCIIDigit(start + CHECK_FIRST) || !isASCIIDigit(start + CHECK_LAST)) return null
            val compact = StringBuilder()
            var count = 0
            var offset = start
            while (count < length) {
                if (isCode(offset)) {
                    compact.append(characters[offset])
                    count += 1
                    offset += 1
                } else if (count >= HEAD && isSeparator(offset) && isCode(offset + 1)) {
                    offset += 1
                } else {
                    break
                }
            }
            return offset.takeIf { count == length && !isWordCharacter(offset) && isValid(compact.toString()) }
        }

        fun ranges(): List<IntRange> {
            val found = mutableListOf<IntRange>()
            var start = 0
            while (start + 1 < characters.size) {
                val startsWord = !isWordCharacter(start - 1) && isCode(start) && TextRules.isLetter(characters[start])
                val after = if (startsWord) end(start) else null
                if (after != null) {
                    found.add(starts[start] until starts[after])
                    start = after
                } else {
                    start += 1
                }
            }
            return found
        }
    }
}
