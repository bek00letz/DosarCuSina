package com.ar.dosarcusina.app.phone

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/** How this phone's own values read from their JSON: whatever isn't what is expected is left out. */
internal object PhoneJson {
    /** The texts of a list; nothing for anything else. */
    fun strings(kept: JsonElement?): List<String> =
        (kept as? JsonArray).orEmpty().mapNotNull { text(it) }

    /** A text; none for anything else. */
    fun text(kept: JsonElement?): String? = (kept as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** A list of texts. */
    fun list(texts: List<String>): JsonArray = JsonArray(texts.map(::JsonPrimitive))
}
