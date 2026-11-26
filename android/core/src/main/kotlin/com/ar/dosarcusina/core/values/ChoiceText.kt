package com.ar.dosarcusina.core.values

/**
 * Whether text names an option of a choice, as the iOS app's `ChoiceOption.matches`
 * (ios/DosarCuSina/Models/Fields/ChoiceOptions.swift): its key as it is, or its label or one of
 * its other spellings without case or diacritics, whitespace collapsed, signs kept ("A+" and "A-"
 * stay apart). The one rule for every choice: a category's options, a document's type, a
 * citizenship.
 */
object ChoiceText {
    private val spaces = Regex("\\s+")

    /** [text] folded ([RomanianText.fold]) with its whitespace collapsed. */
    fun fold(text: String): String = RomanianText.fold(text).split(spaces).filter { it.isNotEmpty() }.joinToString(" ")

    /** Whether [text] names the option of [key], [label] and [aliases]. */
    fun names(text: String, key: String, label: String, aliases: List<String>): Boolean {
        if (text == key) return true
        val needle = fold(text)
        return needle.isNotEmpty() && (listOf(label) + aliases).any { fold(it) == needle }
    }
}
