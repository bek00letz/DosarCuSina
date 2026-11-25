package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement

/**
 * A list stored as JSON that a newer build may have written, as the iOS app's `KeptList`
 * (ios/DosarCuSina/Models/Values/KeptList.swift): the entries this build can read, and the ones
 * it can't, kept raw in their places and written back unchanged. A template's sections,
 * deadlines and parts, and a section's rows under Date importante.
 *
 * An entry this build can't read goes only when one it can read takes its place (the same key
 * or id), so editing the readable ones never loses the others. An entry it reads keeps the JSON
 * it was read from, by its key or id, and is written over it ([KeptJson.laying]), so a key
 * inside it that this build doesn't know stays too.
 *
 * [identity] is an entry's id (its `id` or `key`), compared without case.
 */
class KeptList<E> private constructor(
    /** The entries this build reads, in order. */
    val items: List<E>,
    /** The entries it can't, raw, each with its place in the list as it was read. */
    val unreadable: List<Unreadable>,
    private val origins: Map<String, Origin<E>>,
    private val codec: JsonCodec<E>,
    private val identity: (E) -> Any,
) {
    /** An entry this build can't read: its place among all the entries when it was read, and its JSON. */
    data class Unreadable(val position: Int, val raw: JsonElement) {
        /** The key or id it is known by, when it has one this build can read. */
        val identity: String? get() = KeptJson.keptIdentity(raw)
    }

    private class Origin<E>(val stored: JsonElement, val asRead: E)

    /** Whether every entry could be read. */
    val isFullyRead: Boolean get() = unreadable.isEmpty()

    /** The keys or ids of every entry, readable or not. */
    val identities: Set<String> get() = items.map(::idOf).toSet() + unreadable.mapNotNull { it.identity }

    /**
     * [items] in place of the readable entries, with every entry this build can't read that none
     * of them replaces (the same key or id). An entry keeps what it was read from while one with
     * its key or id is among them.
     */
    fun replacingItems(items: List<E>): KeptList<E> {
        val ids = items.map(::idOf).toSet()
        return KeptList(
            items,
            unreadable.filter { entry -> entry.identity?.let { it !in ids } ?: true },
            origins.filterKeys { it in ids },
            codec,
            identity,
        )
    }

    /**
     * Every part kept that this build doesn't read changed by [transform], or left out when it
     * gives null: an entry it can't read, whole, and inside an entry it reads, what it doesn't
     * read there ([KeptJson.mappingKept]).
     */
    fun mappingKept(transform: (JsonElement) -> JsonElement?): KeptList<E> {
        val kept = unreadable.mapNotNull { entry -> transform(entry.raw)?.let { Unreadable(entry.position, it) } }
        val mapped = origins.mapValues { (_, origin) ->
            Origin(KeptJson.mappingKept(origin.stored, codec.encode(origin.asRead), transform), origin.asRead)
        }
        return KeptList(items, kept, mapped, codec, identity)
    }

    /**
     * Only the entries [isIncluded] keeps, readable or not: a readable one with the JSON it was
     * read from, one this build can't read ([keepsRaw]) raw.
     */
    fun filtered(isIncluded: (E) -> Boolean, keepsRaw: (JsonElement) -> Boolean): KeptList<E> {
        val items = items.filter(isIncluded)
        val ids = items.map(::idOf).toSet()
        val kept = unreadable.filter { keepsRaw(it.raw) }
        return KeptList(items, kept, origins.filterKeys { it in ids }, codec, identity)
    }

    /**
     * This list without the entries [other] has (the same key or id), then [other]'s entries,
     * readable or not, each with what it kept: [other] takes the place of what it replaces.
     */
    fun replacingEntries(other: KeptList<E>): KeptList<E> {
        val ids = other.identities
        val kept = filtered({ idOf(it) !in ids }, { raw -> KeptJson.keptIdentity(raw)?.let { it !in ids } ?: true })
        val start = kept.items.size + kept.unreadable.size
        return KeptList(
            kept.items + other.items,
            kept.unreadable + other.unreadable.map { Unreadable(start + it.position, it.raw) },
            kept.origins + other.origins,
            codec,
            identity,
        )
    }

    /** The JSON it writes: each entry it reads laid over what it was read from, the others where they were. */
    fun toJson(): JsonArray {
        val written = ArrayList<JsonElement>()
        val pending = ArrayDeque(unreadable.sortedBy { it.position })
        fun writeUnreadable(upTo: Int) {
            while (pending.isNotEmpty() && pending.first().position <= upTo) written.add(pending.removeFirst().raw)
        }
        for (item in items) {
            writeUnreadable(written.size)
            written.add(laidOver(item) ?: codec.encode(item))
        }
        writeUnreadable(Int.MAX_VALUE)
        return JsonArray(written)
    }

    /** An entry as it is written over the JSON it was read from, or null for one made here. */
    private fun laidOver(item: E): JsonElement? {
        val origin = origins[idOf(item)] ?: return null
        if (item == origin.asRead) return origin.stored
        return KeptJson.laying(codec.encode(item), origin.stored, codec.encode(origin.asRead))
    }

    private fun idOf(item: E): String = identity(item).toString().lowercase()

    override fun equals(other: Any?): Boolean {
        if (other !is KeptList<*> || other.items != items || other.origins.keys != origins.keys) return false
        if (other.unreadable.size != unreadable.size) return false
        return other.unreadable.zip(unreadable).all { (theirs, mine) ->
            theirs.position == mine.position && JsonTrees.same(theirs.raw, mine.raw)
        }
    }

    override fun hashCode(): Int = items.hashCode()

    companion object {
        /** A list made here: nothing kept beside it. */
        fun <E> made(items: List<E>, codec: JsonCodec<E>, identity: (E) -> Any): KeptList<E> =
            KeptList(items, emptyList(), emptyMap(), codec, identity)

        /** The list as stored, with whatever couldn't be read; empty when [stored] isn't a list. */
        fun <E> read(stored: JsonElement?, codec: JsonCodec<E>, identity: (E) -> Any): KeptList<E> {
            val raws = stored as? JsonArray ?: return made(emptyList(), codec, identity)
            val items = ArrayList<E>()
            val unreadable = ArrayList<Unreadable>()
            val origins = LinkedHashMap<String, Origin<E>>()
            for ((position, raw) in raws.withIndex()) {
                val item = codec.decode(raw)
                if (item == null) {
                    unreadable.add(Unreadable(position, raw))
                    continue
                }
                items.add(item)
                origins.putIfAbsent(identity(item).toString().lowercase(), Origin(raw, item))
            }
            return KeptList(items, unreadable, origins, codec, identity)
        }
    }
}
