package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.text.Normalizer

/**
 * JSON trees as the iOS app's `JSONValue` sees them: when two are the same value, and the walks
 * over every text inside one that the exits' rules (secrets, card numbers) use.
 */
object JsonTrees {
    /**
     * Whether two trees are the same value, as the iOS app compares them: objects by their keys
     * whatever their order, lists entry by entry, text as Unicode compares it (`é` written either
     * way), and numbers by what they read as there ([JsonNumber]: `1.0` is `1`). Keys are
     * matched as written.
     */
    fun same(left: JsonElement, right: JsonElement): Boolean = when {
        left is JsonObject && right is JsonObject -> sameObject(left, right)
        left is JsonArray && right is JsonArray ->
            left.size == right.size && left.indices.all { same(left[it], right[it]) }
        left is JsonNull || right is JsonNull -> left is JsonNull && right is JsonNull
        left is JsonPrimitive && right is JsonPrimitive -> samePrimitive(left, right)
        else -> false
    }

    /** [same] for two values that may be missing: both missing is the same too. */
    fun sameOrBothMissing(left: JsonElement?, right: JsonElement?): Boolean =
        if (left == null || right == null) left == null && right == null else same(left, right)

    private fun sameObject(left: JsonObject, right: JsonObject): Boolean =
        left.size == right.size && left.all { (key, value) -> right[key]?.let { same(value, it) } ?: false }

    private fun samePrimitive(left: JsonPrimitive, right: JsonPrimitive): Boolean = when {
        left.isString != right.isString -> false
        left.isString -> left.content == right.content || nfc(left.content) == nfc(right.content)
        isBool(left) || isBool(right) -> left.content == right.content
        else -> JsonNumber.read(left.content) == JsonNumber.read(right.content)
    }

    private fun isBool(value: JsonPrimitive): Boolean = value.content == "true" || value.content == "false"

    private fun nfc(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFC)

    /** Every text inside [element] changed by [transform]. */
    fun mappingStrings(element: JsonElement, transform: (String) -> String): JsonElement = when (element) {
        is JsonObject -> JsonObject(element.mapValues { mappingStrings(it.value, transform) })
        is JsonArray -> JsonArray(element.map { mappingStrings(it, transform) })
        is JsonPrimitive -> if (element.isString) JsonPrimitive(transform(element.content)) else element
    }

    /** Whether any text inside [element] matches. */
    fun containsString(element: JsonElement, match: (String) -> Boolean): Boolean = when (element) {
        is JsonObject -> element.values.any { containsString(it, match) }
        is JsonArray -> element.any { containsString(it, match) }
        is JsonPrimitive -> element.isString && match(element.content)
    }
}

/**
 * What a JSON number reads as in the iOS app's `JSONValue`, pinned by
 * shared/test-vectors/values/json-numbers.json: a whole number within 64 bits (`1`, and `1.0` or
 * `1e2` too), else a Double (`1.5`, `1e21`, `12345678901234567890`); a number too large for a
 * Double can't be read there at all.
 */
sealed interface JsonNumber {
    data class Whole(val value: Long) : JsonNumber

    data class Fraction(val value: Double) : JsonNumber

    /** Larger than any Double: the iOS app can't read it. */
    data object Unreadable : JsonNumber

    companion object {
        private const val TWO_TO_63 = 9.223372036854775807e18

        fun read(text: String): JsonNumber {
            val whole = text.toLongOrNull()
            val double = text.toDoubleOrNull()
            return when {
                whole != null -> Whole(whole)
                double == null || !double.isFinite() -> Unreadable
                readsWhole(text, double) -> Whole(BigDecimal(double).toLong())
                else -> Fraction(double)
            }
        }

        /** A whole number within 64 bits written with a fraction or exponent; digits alone stay a Double. */
        private fun readsWhole(text: String, double: Double): Boolean {
            val hasFractionOrExponent = text.any { it == '.' || it == 'e' || it == 'E' }
            val fits = double >= -TWO_TO_63 && double < TWO_TO_63
            return hasFractionOrExponent && fits && double == Math.floor(double)
        }
    }
}
