package com.ar.dosarcusina.core.text

import java.text.BreakIterator
import java.util.Locale

/**
 * The characters of one text around a place in it, as Swift's `String` gives them by index
 * (`text[i]`, `text.index(before: i)`, `suffix(_:)`): what a person sees as one character, an
 * extended grapheme cluster. Places are UTF-16 offsets, as a pattern's ranges are.
 */
internal class Characters(private val text: String) {
    private val breaks: BreakIterator = BreakIterator.getCharacterInstance(Locale.ROOT).also { it.setText(text) }

    /** The character that ends at [offset], or null at the start. */
    fun before(offset: Int): String? {
        if (offset <= 0) return null
        return text.substring(breaks.preceding(offset), offset)
    }

    /** The character at [offset] (the one it falls in, as Swift rounds an index down), or null at the end. */
    fun at(offset: Int): String? {
        if (offset >= text.length) return null
        val start = if (breaks.isBoundary(offset)) offset else breaks.preceding(offset)
        return text.substring(start, breaks.following(start))
    }

    /** The last [count] characters before [offset]. */
    fun suffix(offset: Int, count: Int): String {
        var start = offset
        repeat(count) { if (start > 0) start = breaks.preceding(start) }
        return text.substring(start, offset)
    }
}
