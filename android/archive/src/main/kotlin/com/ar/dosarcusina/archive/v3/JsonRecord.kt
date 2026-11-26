package com.ar.dosarcusina.archive.v3

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.JsonNumber
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

/** A JSON value that isn't what a record needs: the record, and so its file, can't be read. */
class UnreadableRecord : Exception()

/**
 * One JSON object read key by key, as Swift's `Codable` reads a record: a key that is missing
 * or `null` is none, and a key that is there with the wrong shape refuses the whole record
 * ([UnreadableRecord]), as a `DecodingError` does on iOS. Numbers are read as the iOS app
 * reads them ([JsonNumber]): a whole number (`3`, `3.0`) for a count, any number for a Double.
 */
// One reader per shape of JSON value a record holds.
@Suppress("TooManyFunctions")
internal class JsonRecord(val fields: JsonObject) {
    /** The value under [key], or null when it is missing or `null`. */
    fun element(key: String): JsonElement? = fields[key]?.takeUnless { it is JsonNull }

    fun has(key: String): Boolean = element(key) != null

    fun string(key: String): String = stringOrNull(key) ?: throw UnreadableRecord()

    fun stringOrNull(key: String): String? = element(key)?.let(::text)

    fun bool(key: String): Boolean = boolOrNull(key) ?: throw UnreadableRecord()

    fun boolOrNull(key: String): Boolean? = element(key)?.let(::bool)

    fun int(key: String): Int = intOrNull(key) ?: throw UnreadableRecord()

    fun intOrNull(key: String): Int? = element(key)?.let(::int)

    fun long(key: String): Long = element(key)?.let(::long) ?: throw UnreadableRecord()

    fun double(key: String): Double = doubleOrNull(key) ?: throw UnreadableRecord()

    fun doubleOrNull(key: String): Double? = element(key)?.let(::double)

    fun instant(key: String): Instant = instantOrNull(key) ?: throw UnreadableRecord()

    fun instantOrNull(key: String): Instant? =
        stringOrNull(key)?.let { MachineText.moment(it) ?: throw UnreadableRecord() }

    fun day(key: String): CalendarDay = dayOrNull(key) ?: throw UnreadableRecord()

    fun dayOrNull(key: String): CalendarDay? =
        stringOrNull(key)?.let { CalendarDay.parse(it) ?: throw UnreadableRecord() }

    fun moneyOrNull(key: String): Money? = element(key)?.let { Money.fromJson(it) ?: throw UnreadableRecord() }

    fun strings(key: String): List<String> = stringsOrNull(key) ?: throw UnreadableRecord()

    fun stringsOrNull(key: String): List<String>? = element(key)?.let { list(it).map(::text) }

    fun list(key: String): JsonArray = element(key)?.let(::list) ?: throw UnreadableRecord()

    fun obj(key: String): JsonObject = objOrNull(key) ?: throw UnreadableRecord()

    fun objOrNull(key: String): JsonObject? = element(key)?.let { it as? JsonObject ?: throw UnreadableRecord() }

    companion object {
        fun of(element: JsonElement): JsonRecord = JsonRecord(element as? JsonObject ?: throw UnreadableRecord())

        fun text(element: JsonElement): String =
            (element as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw UnreadableRecord()

        fun bool(element: JsonElement): Boolean {
            val primitive = element as? JsonPrimitive
            if (primitive == null || primitive.isString) throw UnreadableRecord()
            return when (primitive.content) {
                "true" -> true
                "false" -> false
                else -> throw UnreadableRecord()
            }
        }

        fun int(element: JsonElement): Int {
            val whole = number(element) as? JsonNumber.Whole ?: throw UnreadableRecord()
            if (whole.value !in Int.MIN_VALUE..Int.MAX_VALUE) throw UnreadableRecord()
            return whole.value.toInt()
        }

        fun long(element: JsonElement): Long = (number(element) as? JsonNumber.Whole)?.value ?: throw UnreadableRecord()

        fun double(element: JsonElement): Double = when (val number = number(element)) {
            is JsonNumber.Whole -> number.value.toDouble()
            is JsonNumber.Fraction -> number.value
            JsonNumber.Unreadable -> throw UnreadableRecord()
        }

        fun list(element: JsonElement): JsonArray = element as? JsonArray ?: throw UnreadableRecord()

        private fun number(element: JsonElement): JsonNumber {
            val primitive = element as? JsonPrimitive
            if (primitive == null || primitive.isString || primitive is JsonNull) throw UnreadableRecord()
            if (primitive.content == "true" || primitive.content == "false") throw UnreadableRecord()
            return JsonNumber.read(primitive.content)
        }
    }
}

/**
 * A record's JSON object written key by key, as the iOS writer's `encodeIfPresent`: a value
 * that is null writes nothing.
 */
internal class JsonWriting {
    private val fields = LinkedHashMap<String, JsonElement>()

    fun put(key: String, value: JsonElement?) {
        if (value != null) fields[key] = value
    }

    fun put(key: String, value: String?) = put(key, value?.let(::JsonPrimitive))

    fun put(key: String, value: Boolean?) = put(key, value?.let(::JsonPrimitive))

    fun put(key: String, value: Int?) = put(key, value?.let { MachineText.number(it.toLong()) })

    fun put(key: String, value: Double?) = put(key, value?.let(MachineText::number))

    fun put(key: String, value: Instant?) = put(key, value?.let(MachineText::moment))

    fun put(key: String, value: CalendarDay?) = put(key, value?.isoString)

    fun put(key: String, value: Money?) = put(key, value?.toJson())

    fun putStrings(key: String, value: List<String>?) =
        put(key, value?.let { list -> JsonArray(list.map(::JsonPrimitive)) })

    fun build(): JsonObject = JsonObject(fields)
}

/** A JSON object made key by key. */
internal fun jsonObject(build: JsonWriting.() -> Unit): JsonObject = JsonWriting().apply(build).build()
