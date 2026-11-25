package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonElement

/**
 * What a form's save writes: only what the person changed in it, laid over what is stored now,
 * as the iOS app's `ThreeWay` (ios/DosarCuSina/Models/Values/ThreeWay.swift). A part the person
 * didn't change keeps what is stored now; a part they changed is theirs, even over a newer
 * change to the same part. A value stored as JSON is laid part by part ([KeptJson.laying]):
 * field by field, a row by its id.
 */
object ThreeWay {
    /** One value, whole: the edit when the person changed it, else what is stored now. */
    fun <V> value(edited: V, stored: V, base: V): V = if (edited == base) stored else edited

    /** A value stored as JSON, part by part: each part the person changed, over what is stored now. */
    fun laying(edited: JsonElement, stored: JsonElement, base: JsonElement): JsonElement = when {
        JsonTrees.same(edited, base) -> stored
        JsonTrees.same(stored, base) -> edited
        else -> KeptJson.laying(edited, stored, base)
    }

    /** A value [codec] reads and writes, part by part; the edit as it is when the merged JSON can't be read back. */
    fun <V> laying(edited: V, stored: V, base: V, codec: JsonCodec<V>): V {
        if (edited == base) return stored
        if (stored == base) return edited
        val merged = KeptJson.laying(codec.encode(edited), codec.encode(stored), codec.encode(base))
        return codec.decode(merged) ?: edited
    }
}
