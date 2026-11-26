package com.ar.dosarcusina.store.templates

import com.ar.dosarcusina.catalog.Behavior
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.store.schema.CategoryTemplate

// Finding a category by what it does, as the iOS app's CategoryRoles.swift: never by its key, so
// code never asks "is this the built-in X" and a category of one's own can take a built-in's part.

/** The keys of the categories that play [role]: what a screen's query asks instead of naming a built-in. */
fun Iterable<CategoryTemplate>.keys(playing: Role): Set<String> =
    filter { it.behavior.role == playing }.map { it.key }.toSet()

/**
 * The category that plays [role], from categories in the binder's order: a built-in comes first
 * when one of one's own plays the same part.
 */
fun List<CategoryTemplate>.template(withRole: Role): CategoryTemplate? =
    filter { it.behavior.role == withRole }.sortedBy { if (it.isBuiltIn) 0 else 1 }.firstOrNull()

/** The key of the category that plays [role], a built-in first, then by its place on the binder. */
fun Map<String, CategoryTemplate>.key(withRole: Role): String? =
    values.filter { it.behavior.role == withRole }
        .sortedWith(compareBy({ if (it.isBuiltIn) 0 else 1 }, { it.homeOrder }))
        .firstOrNull()?.key

/** What the category [key] does; a category that isn't installed behaves as standard. */
fun Map<String, CategoryTemplate>.behavior(of: String): Behavior = this[of]?.behavior ?: Behavior.STANDARD

/** Whether the category [key] plays [role]. */
fun Map<String, CategoryTemplate>.plays(role: Role, key: String): Boolean = this[key]?.behavior?.role == role

/**
 * Each category once, by key, as the iOS app's `CategoryTemplate.oncePerKey`: until copies of one
 * are joined, the first in the binder's order (its place, then when it was made) is the one read.
 */
fun Iterable<CategoryTemplate>.byKey(): Map<String, CategoryTemplate> {
    val chosen = LinkedHashMap<String, CategoryTemplate>()
    for (template in this) {
        val current = chosen[template.key]
        if (current != null && compareValuesBy(current, template, { it.homeOrder }, { it.createdAt }) <= 0) continue
        chosen[template.key] = template
    }
    return chosen
}
