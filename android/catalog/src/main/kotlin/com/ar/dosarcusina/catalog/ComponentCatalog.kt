package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.core.search.SearchText

/** A heading on the visit checklist and the parts and jobs under it, as the iOS app's `ComponentGroup`. */
data class ComponentGroup(val title: String, val components: List<ComponentDefinition>)

/**
 * Matching free text to a category's parts and jobs, as the iOS app's `ComponentCatalog`
 * (ios/DosarCuSina/Models/Templates/ComponentCatalog.swift): line items point at a part by its key, so the
 * history answers "when did I last change it" whatever the invoice called it. The parts are the
 * category's (`components`), the catalog's for a built-in.
 */
object ComponentCatalog {
    /** What a part of one's own's key starts with: one the category doesn't list. */
    const val CUSTOM_KEY_PREFIX = "custom."

    /** The category's parts grouped for the visit checklist, in the catalog's order. */
    fun checklist(components: List<ComponentDefinition>): List<ComponentGroup> =
        components.groupBy { it.group }.map { (title, parts) -> ComponentGroup(title, parts) }

    /**
     * The part whose name or one of whose synonyms appears in [text], the longest match winning
     * ("plăcuțe frână spate" picks the rear pads, not just "plăcuțe"); the first listed on a tie.
     */
    fun match(text: String, components: List<ComponentDefinition>): ComponentDefinition? {
        val haystack = SearchText.normalize(text)
        if (haystack.isEmpty()) return null
        var best: ComponentDefinition? = null
        var length = 0
        for (component in components) {
            for (phrase in listOf(component.name) + component.synonyms) {
                val needle = SearchText.normalize(phrase)
                if (needle.isEmpty() || !SearchText.containsPhrase(haystack, needle)) continue
                val size = needle.codePointCount(0, needle.length)
                if (size > length) {
                    best = component
                    length = size
                }
            }
        }
        return best
    }

    /** The catalog's key for [text], or a stable `custom.<slug>` key for anything the catalog doesn't know. */
    fun key(text: String, components: List<ComponentDefinition>): String {
        match(text, components)?.let { return it.key }
        val slug = SearchText.normalize(text).split(' ').filter { it.isNotEmpty() }.joinToString("-")
        return CUSTOM_KEY_PREFIX + slug.ifEmpty { "item" }
    }
}
