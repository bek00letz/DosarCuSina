package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.TextRules

/**
 * How search reads text, as the iOS app's `SearchText` (ios/DosarCuSina/Models/Templates/ComponentCatalog.swift):
 * the folded words of `RomanianText` and nothing else, so "polita" finds "poliță", "şcoala" with a
 * cedilla finds "școala" with a comma below, and "B-123-ABC" is the words "b", "123" and "abc".
 * Never a fold of its own.
 */
object SearchText {
    /** The folded words of [text], one space between them. */
    fun normalize(text: String): String = RomanianText.words(text).joinToString(" ")

    /** The folded words of a query, each of which must start a word of what it finds. */
    fun tokens(text: String): List<String> = RomanianText.words(text)

    /**
     * Whether [word] starts with [token], character by character as a person sees them (Swift's
     * `hasPrefix`): the end of [token] has to fall between two characters of [word].
     */
    internal fun startsWith(word: String, token: String): Boolean {
        if (!word.startsWith(token)) return false
        if (word.length == token.length) return true
        return TextRules.prefix(word, TextRules.characters(token).size) == token
    }
}
