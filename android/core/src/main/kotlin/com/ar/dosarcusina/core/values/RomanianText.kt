package com.ar.dosarcusina.core.values

import java.text.Normalizer

/**
 * Romanian text as the app compares it, as the iOS app's `RomanianText`
 * (ios/Shared/RomanianText.swift). Today only [fold], which the number reader and the unit
 * catalog read units with; search and capture bring the rest.
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
        return withoutMarksAndWidth(commas)
            .lowercase()
            .replace('\u00A0', ' ')
            .replace('\u202F', ' ')
    }

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
