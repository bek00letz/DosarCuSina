package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** An exit's rule for a part this build doesn't read: the part as it goes out, or null to leave it out. */
typealias JsonExit = (JsonElement) -> JsonElement?

/**
 * The one rule for writing again a stored JSON value a newer build may have written, as the iOS
 * app's `JSONValue.laying` (ios/DosarCuSina/Models/Values/KeptJSON.swift): what this build
 * changed goes in, and everything else stays exactly as it was stored, keys and values this
 * build doesn't know included, at any depth. [KeptObject] (one object) and [KeptList] (a list's
 * entries) write through it, and [ThreeWay] lays a form's edit over what is stored now by it.
 *
 * It works on three forms of the same value: as stored; as read (what this build made of it,
 * written again); and as edited. Where the edit left a part as read, the stored part stays: a
 * key this build doesn't know, or a value it read as something else. Where the edit changed a
 * part, the edit wins. Two rules say when a part is still the same thing:
 * - an object with a `type` is another value once its type is another: a rule that became
 *   another kind of rule keeps nothing of the old one;
 * - a list's entries pair by their `key` or `id`, else by being unchanged, else by their place
 *   when the list kept its length; an entry the edit took out goes, with what it kept.
 *
 * Trees are kotlinx's, which keep each number's text as it was read; two values are compared
 * as the iOS app compares them ([JsonTrees.same]).
 */
object KeptJson {
    /** What [edited] writes over [stored], which this build read as [asRead]. */
    fun laying(edited: JsonElement, stored: JsonElement, asRead: JsonElement): JsonElement = when {
        JsonTrees.same(edited, asRead) -> stored
        stored is JsonObject && asRead is JsonObject && edited is JsonObject -> layingObject(edited, stored, asRead)
        stored is JsonArray && asRead is JsonArray && edited is JsonArray -> layingList(edited, stored, asRead)
        else -> edited
    }

    private fun layingObject(made: JsonObject, kept: JsonObject, read: JsonObject): JsonElement {
        if (!JsonTrees.sameOrBothMissing(kept["type"], made["type"])) return made
        val merged = LinkedHashMap<String, JsonElement>()
        for ((key, value) in made) {
            val wasRead = read[key]
            val wasKept = kept[key]
            when {
                wasRead != null && wasKept != null -> merged[key] = laying(value, wasKept, wasRead)
                // Left as read, and no longer stored: it was taken out since, and stays out.
                wasRead != null && JsonTrees.same(value, wasRead) -> Unit
                else -> merged[key] = value
            }
        }
        // What this build didn't read, and the edit didn't set.
        for ((key, value) in kept) {
            if (read[key] == null && made[key] == null) merged[key] = value
        }
        return JsonObject(merged)
    }

    private fun layingList(made: JsonArray, kept: JsonArray, read: JsonArray): JsonElement {
        val origins = storedIndices(read, kept)
        val taken = HashSet<Int>()
        val merged = ArrayList<JsonElement>()
        for ((index, value) in made.withIndex()) {
            val match = readEntry(value, index, made.size, read, taken)
            match?.let { taken.add(it) }
            val origin = match?.let { origins[it] }
            when {
                match == null -> merged.add(value)
                origin != null -> merged.add(laying(value, kept[origin], read[match]))
                // An entry known by its key or id, left as read, and no longer stored: taken out
                // since, it stays out.
                keptIdentity(read[match]) == null || !JsonTrees.same(value, read[match]) -> merged.add(value)
            }
        }
        // Entries stored with a key or id this build never read, and the edit didn't make: added
        // since, they stay.
        val known = (read + made).mapNotNull(::keptIdentity).toSet()
        merged += kept.filter { entry -> keptIdentity(entry)?.let { it !in known } ?: false }
        return JsonArray(merged)
    }

    /**
     * The same value as [stored] with every part this build doesn't read (a part [asRead] lacks,
     * or holds otherwise) changed by [transform]: the rules every exit applies (secrets, card
     * numbers) reach what a newer build wrote. A part [transform] gives null for is left out;
     * one this build also reads, otherwise, is then kept as this build reads it.
     */
    fun mappingKept(stored: JsonElement, asRead: JsonElement, transform: JsonExit): JsonElement =
        when {
            JsonTrees.same(stored, asRead) -> stored
            stored is JsonObject && asRead is JsonObject && sameType(stored, asRead) ->
                mappingKeptObject(stored, asRead, transform)
            stored is JsonArray && asRead is JsonArray -> mappingKeptList(stored, asRead, transform)
            else -> transform(stored) ?: asRead
        }

    private fun sameType(left: JsonObject, right: JsonObject): Boolean =
        JsonTrees.sameOrBothMissing(left["type"], right["type"])

    private fun mappingKeptObject(stored: JsonObject, asRead: JsonObject, transform: JsonExit): JsonElement {
        val result = LinkedHashMap<String, JsonElement>()
        for ((key, value) in stored) {
            val wasRead = asRead[key]
            if (wasRead != null) {
                result[key] = mappingKept(value, wasRead, transform)
            } else {
                transform(value)?.let { result[key] = it }
            }
        }
        return JsonObject(result)
    }

    private fun mappingKeptList(stored: JsonArray, asRead: JsonArray, transform: JsonExit): JsonElement {
        val readFor = HashMap<Int, Int>()
        for ((match, origin) in storedIndices(asRead, stored).withIndex()) {
            if (origin != null && origin !in readFor) readFor[origin] = match
        }
        val result = ArrayList<JsonElement>()
        for ((index, value) in stored.withIndex()) {
            val match = readFor[index]
            if (match != null) {
                result.add(mappingKept(value, asRead[match], transform))
            } else {
                transform(value)?.let { result.add(it) }
            }
        }
        return JsonArray(result)
    }

    /** The key or id an entry of a stored list is known by: its `key`'s text, else its `id`'s, without case. */
    fun keptIdentity(entry: JsonElement): String? {
        val fields = entry as? JsonObject ?: return null
        return (text(fields["key"]) ?: text(fields["id"]))?.lowercase()
    }

    private fun text(element: JsonElement?): String? = (element as? JsonPrimitive)?.takeIf { it.isString }?.content

    // Pairing a list's entries

    /**
     * For each entry as read, the place of the stored entry it was read from: the one with the
     * same key or id, else the same place when nothing was left out in reading.
     */
    private fun storedIndices(read: List<JsonElement>, kept: List<JsonElement>): List<Int?> =
        read.mapIndexed { index, entry ->
            val id = keptIdentity(entry)
            when {
                id != null -> kept.indexOfFirst { keptIdentity(it) == id }.takeIf { it >= 0 }
                kept.size == read.size -> index
                else -> null
            }
        }

    /**
     * The entry as read that [value] (at [index] of [count] edited entries) is: the same key or
     * id, else one left as it was, else the one in its place when the list kept its length.
     */
    private fun readEntry(value: JsonElement, index: Int, count: Int, read: List<JsonElement>, taken: Set<Int>): Int? {
        val free = read.indices.filter { it !in taken }
        val id = keptIdentity(value)
        return if (id != null) {
            free.firstOrNull { keptIdentity(read[it]) == id }
        } else {
            free.firstOrNull { JsonTrees.same(read[it], value) }
                ?: index.takeIf { count == read.size && it in free && keptIdentity(read[it]) == null }
        }
    }
}
