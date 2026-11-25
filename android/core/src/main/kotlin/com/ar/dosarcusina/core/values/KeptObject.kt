package com.ar.dosarcusina.core.values

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * How a value this build knows is read from and written to JSON: the Android counterpart of a
 * Swift type's `Codable`. [decode] gives null when this build can't read the JSON as the value,
 * which is what keeps it raw instead.
 */
interface JsonCodec<T> {
    fun decode(json: JsonElement): T?

    fun encode(value: T): JsonElement

    companion object {
        /** A codec from a kotlinx serializer, as the iOS coders do: unknown keys unread, nothing for null. */
        fun <T> of(serializer: KSerializer<T>, format: Json = MachineText.reader): JsonCodec<T> =
            SerializerCodec(serializer, format)
    }
}

/** A [JsonCodec] over a kotlinx serializer. */
private class SerializerCodec<T>(private val serializer: KSerializer<T>, private val format: Json) : JsonCodec<T> {
    override fun decode(json: JsonElement): T? =
        try {
            format.decodeFromJsonElement(serializer, json)
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }

    override fun encode(value: T): JsonElement = format.encodeToJsonElement(serializer, value)
}

/**
 * One object stored as JSON that a newer build may have written, as the iOS app's `KeptObject`
 * (ios/DosarCuSina/Models/Values/KeptObject.swift): a category's behaviour, a deadline's
 * recurrence, a document's framing, a section's values. The value this build reads, and the
 * JSON it was read from, so writing it again keeps every key this build doesn't know, at any
 * depth, and every value it read as something else, as stored ([KeptJson.laying]).
 *
 * Code reads and edits [value]; a value made here, with nothing read, writes as it always did.
 */
class KeptObject<T> private constructor(
    /** The value as this build reads it, with any edit. */
    val value: T,
    private val origin: Origin<T>?,
    private val codec: JsonCodec<T>,
) {
    private class Origin<T>(val stored: JsonElement, val asRead: T)

    /** The same, with [value] in place of this one's: what it kept stays. */
    fun replacingValue(value: T): KeptObject<T> = KeptObject(value, origin, codec)

    /** The JSON it writes: the value laid over what it was read from. */
    val json: JsonElement
        get() {
            val edited = codec.encode(value)
            val origin = origin ?: return edited
            if (value == origin.asRead) return origin.stored
            return KeptJson.laying(edited, origin.stored, codec.encode(origin.asRead))
        }

    /** Whether it writes anything [value] doesn't say: something a newer build wrote. */
    val keepsMore: Boolean get() = origin != null && !JsonTrees.same(json, codec.encode(value))

    /**
     * Every part kept that this build doesn't read changed by [transform], or left out when it
     * gives null ([KeptJson.mappingKept]): the rules every exit applies reach them too.
     */
    fun mappingKept(transform: (JsonElement) -> JsonElement?): KeptObject<T> {
        val origin = origin ?: return this
        val mapped = KeptJson.mappingKept(origin.stored, codec.encode(origin.asRead), transform)
        return KeptObject(value, Origin(mapped, origin.asRead), codec)
    }

    /** Null when it is [isDefault] and keeps nothing more: a record stores nothing then. */
    fun omitted(isDefault: (T) -> Boolean): KeptObject<T>? = if (isDefault(value) && !keepsMore) null else this

    override fun equals(other: Any?): Boolean {
        if (other !is KeptObject<*>) return false
        if (other.value != value) return false
        val mine = origin
        val theirs = other.origin
        if (mine == null || theirs == null) return mine == null && theirs == null
        return theirs.asRead == mine.asRead && JsonTrees.same(theirs.stored, mine.stored)
    }

    override fun hashCode(): Int = value.hashCode()

    companion object {
        /** A value made here: nothing kept beside it. */
        fun <T> made(value: T, codec: JsonCodec<T>): KeptObject<T> = KeptObject(value, null, codec)

        /** [stored], which this build reads with [codec], or as [fallback] when it can't read it at all. */
        fun <T> read(stored: JsonElement, codec: JsonCodec<T>, fallback: T): KeptObject<T> {
            val asRead = codec.decode(stored) ?: fallback
            return KeptObject(asRead, Origin(stored, asRead), codec)
        }

        /** [stored] read with [codec], or null when this build can't read it (as decoding one on iOS fails). */
        fun <T> decode(stored: JsonElement, codec: JsonCodec<T>): KeptObject<T>? =
            codec.decode(stored)?.let { KeptObject(it, Origin(stored, it), codec) }
    }
}
