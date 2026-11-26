package com.ar.dosarcusina.core.values

import java.text.Normalizer
import java.util.Locale
import java.util.regex.Pattern

/**
 * The one answer to "do these two texts say the same thing?", as the iOS app's `RomanianText`
 * (ios/Shared/RomanianText.swift): how Romanian text is folded for comparing ([fold]), a value
 * compared without spaces, punctuation, case or diacritics ([compact]), its words ([words]) and
 * how a keyword is found in it ([Keyword], [containsWord]). The number reader, the unit catalog,
 * the IBAN check and the card rule read it; search and capture will.
 */
object RomanianText {
    private const val WIDE_FIRST = 0xFF01
    private const val WIDE_LAST = 0xFF5E
    private const val WIDE_TO_NARROW = 0xFEE0
    private const val IDEOGRAPHIC_SPACE = 0x3000

    /**
     * Text without case, diacritics or wide forms: ș and ț with a cedilla as with a comma below,
     * a typographic minus as `-`, no-break spaces as spaces. Spacing and punctuation are kept, so
     * a folded line still lines up with what was read.
     */
    fun fold(text: String): String {
        val commas = text
            .replace("ş", "ș").replace("ţ", "ț").replace("Ş", "Ș").replace("Ţ", "Ț")
            .replace("\u2212", "-")
        return caseFolded(withoutMarksAndWidth(commas))
            .lowercase()
            .replace('\u00A0', ' ')
            .replace('\u202F', ' ')
    }

    /**
     * Foundation's case-insensitive folding, which is Unicode's full case folding, not
     * lowercasing: "\u00DF", "\u1E9E" and "\uFB00" fold to two letters ("ss", "ff"), a final "\u03C2" and "\u00B5" to
     * "\u03C3" and "\u03BC". Each character goes to its capitals and back, one at a time (so no final
     * sigma is made), except the two whose round trip isn't their folding: the dotless "\u0131",
     * which folds to itself, and the capital "\u1E9E", whose capital is itself.
     */
    private fun caseFolded(text: String): String {
        val folded = StringBuilder(text.length)
        var at = 0
        while (at < text.length) {
            val codePoint = text.codePointAt(at)
            at += Character.charCount(codePoint)
            when {
                codePoint < ASCII_END -> folded.append(codePoint.toChar().lowercaseChar())
                codePoint == DOTLESS_I -> folded.appendCodePoint(codePoint)
                codePoint == CAPITAL_SHARP_S -> folded.append("ss")
                else -> folded.append(roundTrip(codePoint))
            }
        }
        return folded.toString()
    }

    /** A character to its capitals and back. */
    private fun roundTrip(codePoint: Int): String =
        String(Character.toChars(codePoint)).uppercase(Locale.ROOT).lowercase(Locale.ROOT)

    private const val ASCII_END = 0x80
    private const val DOTLESS_I = 0x0131
    private const val CAPITAL_SHARP_S = 0x1E9E

    /**
     * A value as compared and checked: folded, in capitals, letters and digits only, so
     * "B-123 ABC", "b 123 abc" and "B123ABC" are one plate, "RO49 AAAA …" one IBAN and
     * "Service Exemplu S.R.L." the same firm as "SERVICE EXEMPLU SRL". The one way every code,
     * number, plate and name is compared without spaces, punctuation, case or diacritics.
     */
    fun compact(text: String): String =
        TextRules.characters(fold(text).uppercase())
            .filter { TextRules.isLetter(it) || TextRules.isNumber(it) }
            .joinToString("")

    /** The folded words of [text]: runs of letters and digits, everything else dropped. */
    fun words(text: String): List<String> {
        val words = mutableListOf<String>()
        val current = StringBuilder()
        for (character in TextRules.characters(fold(text))) {
            if (TextRules.isLetter(character) || TextRules.isNumber(character)) {
                current.append(character)
            } else if (current.isNotEmpty()) {
                words.add(current.toString())
                current.clear()
            }
        }
        if (current.isNotEmpty()) words.add(current.toString())
        return words
    }

    /** How a keyword's last word has to match. */
    enum class WordMatch {
        /** The whole word and nothing more: "index" is not "indexare", "rca" is not "marca". */
        WORD,

        /**
         * The start of a word, so Romanian endings still match: "garanti" finds "garanția",
         * "scadent" finds "scadentă". Never the middle of a word: "achitat" doesn't find "neachitat".
         */
        STEM,
        ;

        companion object {
            private const val SHORT_WORD = 4

            /** Short single words must match whole; longer words and phrases may take an ending. */
            fun natural(phrase: String): WordMatch =
                if (TextRules.characters(phrase).size <= SHORT_WORD && !phrase.contains(" ")) WORD else STEM
        }
    }

    /**
     * A keyword ready to look for in folded text, compiled once and used on many lines. [phrase]
     * is folded here. Its words must follow each other in the text, separated only by spaces or
     * punctuation; each starts a word, and every word but the last is whole. The last is whole
     * too, unless the match is [WordMatch.STEM]. Letters next to digits count as a new word
     * ("120kwh" has "kwh").
     */
    class Keyword(val phrase: String, match: WordMatch? = null) {
        private val pattern: Pattern? = words(phrase).map(Pattern::quote).takeIf { it.isNotEmpty() }?.let { parts ->
            val mode = match ?: WordMatch.natural(fold(phrase))
            val ending = if (mode == WordMatch.WORD) NOT_AFTER_LETTER else ""
            Pattern.compile(NOT_BEFORE_LETTER + parts.joinToString(BETWEEN_WORDS) + ending)
        }

        /** Whether the keyword is in [folded], which is already folded ([fold]). */
        fun isFound(folded: String): Boolean = pattern?.matcher(folded)?.find() ?: false

        private companion object {
            const val NOT_BEFORE_LETTER = """(?<!\p{L})"""
            const val NOT_AFTER_LETTER = """(?!\p{L})"""
            const val BETWEEN_WORDS = """(?![\p{L}])[^\p{L}\p{N}]+"""
        }
    }

    /**
     * Whether [phrase] is in [text], as a whole word or phrase ([WordMatch.WORD]), or with an
     * ending on its last word ([WordMatch.STEM]). Both are folded first.
     */
    fun containsWord(phrase: String, text: String, match: WordMatch? = null): Boolean =
        Keyword(phrase, match).isFound(fold(text))

    /** Foundation's folding without diacritics and width: marks off letters, wide letters and digits as narrow ones. */
    private fun withoutMarksAndWidth(text: String): String {
        val decomposed = Normalizer.normalize(text, Normalizer.Form.NFD)
        val folded = StringBuilder(decomposed.length)
        var at = 0
        while (at < decomposed.length) {
            val codePoint = decomposed.codePointAt(at)
            at += Character.charCount(codePoint)
            when {
                Character.getType(codePoint) == Character.NON_SPACING_MARK.toInt() -> Unit
                codePoint in WIDE_FIRST..WIDE_LAST -> folded.appendCodePoint(codePoint - WIDE_TO_NARROW)
                codePoint == IDEOGRAPHIC_SPACE -> folded.append(' ')
                else -> folded.appendCodePoint(codePoint)
            }
        }
        return Normalizer.normalize(folded, Normalizer.Form.NFC)
    }
}
