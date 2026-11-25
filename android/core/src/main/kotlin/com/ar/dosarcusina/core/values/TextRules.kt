package com.ar.dosarcusina.core.values

import java.text.BreakIterator
import java.util.Locale

/**
 * How the iOS app's text rules see text, so the value rules ported from Swift read it the same:
 * characters as a person sees them (Swift's `Character`, an extended grapheme cluster), the
 * spaces Foundation trims, what Swift calls a number or a letter, and Swift's `Int(_:)`.
 */
internal object TextRules {
    /** The characters of [text] as Swift counts them: what a person sees as one character. */
    fun characters(text: String): List<String> {
        if (text.isEmpty()) return emptyList()
        val breaks = BreakIterator.getCharacterInstance(Locale.ROOT)
        breaks.setText(text)
        val result = ArrayList<String>(text.length)
        var start = breaks.first()
        var end = breaks.next()
        while (end != BreakIterator.DONE) {
            result.add(text.substring(start, end))
            start = end
            end = breaks.next()
        }
        return result
    }

    /** The first [count] characters of [text]. */
    fun prefix(text: String, count: Int): String = characters(text).take(count).joinToString("")

    /** [text] without its last [count] characters. */
    fun droppingLast(text: String, count: Int): String = characters(text).dropLast(count).joinToString("")

    /** Foundation's `CharacterSet.whitespaces`: spaces (Unicode's Zs) and the tab. */
    fun isWhitespace(codePoint: Int): Boolean =
        codePoint == TAB || Character.getType(codePoint) == Character.SPACE_SEPARATOR.toInt()

    /** Foundation's `CharacterSet.whitespacesAndNewlines`: Unicode's Z*, the tab, U+000A–U+000D and U+0085. */
    fun isWhitespaceOrNewline(codePoint: Int): Boolean {
        if (codePoint in TAB..CARRIAGE_RETURN || codePoint == NEXT_LINE) return true
        return when (Character.getType(codePoint)) {
            Character.SPACE_SEPARATOR.toInt(),
            Character.LINE_SEPARATOR.toInt(),
            Character.PARAGRAPH_SEPARATOR.toInt(),
            -> true
            else -> false
        }
    }

    /** [text] without the code points [trims] at either end, as Foundation's `trimmingCharacters(in:)`. */
    fun trimming(text: String, trims: (Int) -> Boolean): String {
        var start = 0
        var end = text.length
        while (start < end) {
            val codePoint = text.codePointAt(start)
            if (!trims(codePoint)) break
            start += Character.charCount(codePoint)
        }
        while (end > start) {
            val codePoint = text.codePointBefore(end)
            if (!trims(codePoint)) break
            end -= Character.charCount(codePoint)
        }
        return text.substring(start, end)
    }

    /** Swift's `Character.isNumber`: its first code point has a numeric value (Unicode's Nd, Nl and No). */
    fun isNumber(character: String): Boolean {
        if (character.isEmpty()) return false
        return when (Character.getType(character.codePointAt(0))) {
            Character.DECIMAL_DIGIT_NUMBER.toInt(),
            Character.LETTER_NUMBER.toInt(),
            Character.OTHER_NUMBER.toInt(),
            -> true
            else -> false
        }
    }

    /** Swift's `Character.isLetter`: its first code point is alphabetic. */
    fun isLetter(character: String): Boolean =
        character.isNotEmpty() && Character.isAlphabetic(character.codePointAt(0))

    /** Swift's `Int(_:)`: an optional sign and ASCII digits only, within 64 bits; null otherwise. */
    fun swiftInt(text: String): Long? {
        if (text.isEmpty()) return null
        val digits = if (text[0] == '+' || text[0] == '-') text.substring(1) else text
        if (digits.isEmpty() || digits.any { it !in '0'..'9' }) return null
        return text.toLongOrNull()
    }

    /**
     * Swift's `split(separator:)`: the pieces between the characters that are [separator],
     * without empty ones. A separator with a mark on it is another character, so it splits nothing.
     */
    fun pieces(text: String, separator: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        for (character in characters(text)) {
            if (character == separator) {
                if (current.isNotEmpty()) result.add(current.toString())
                current.clear()
            } else {
                current.append(character)
            }
        }
        if (current.isNotEmpty()) result.add(current.toString())
        return result
    }

    private const val TAB = 0x09
    private const val CARRIAGE_RETURN = 0x0D
    private const val NEXT_LINE = 0x85
}
