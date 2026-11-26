package com.ar.dosarcusina.core.values

/**
 * An option of a choice, as the iOS app's `ChoiceOption` names it: its stored [key], its [label] and
 * other ways it is written ([aliases]: older text, what people type). A category's field options
 * (the archive's `ChoiceOption`) and the subscription catalog's services, groups and billing cycles
 * are all named this way, and found from text by the one rule here.
 */
interface NamedChoice {
    val key: String
    val label: String
    val aliases: List<String>

    /** Whether [text] names it: its key, or its label or an alias without case or diacritics. */
    fun matches(text: String): Boolean {
        if (text == key) return true
        val needle = fold(text)
        return needle.isNotEmpty() && (listOf(label) + aliases).any { fold(it) == needle }
    }

    companion object {
        /** Folded, whitespace collapsed, signs kept ("A+" and "A-" stay apart). */
        fun fold(text: String): String =
            RomanianText.fold(text).split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
    }
}

/** The option [text] names, as the iOS app's `option(for:)`: one whose key it is, else the first it matches. */
fun <T : NamedChoice> List<T>.option(text: String): T? =
    firstOrNull { it.key == text } ?: firstOrNull { it.matches(text) }
