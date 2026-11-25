package com.ar.dosarcusina.archive.v3

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.JsonCodec
import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID

/**
 * A value stored in a section's field, as the iOS app's `FieldValue`
 * (ios/DosarCuSina/Models/Fields/FieldValue.swift), in the archive's form:
 * `{"type": "text", "value": "B-123-ABC"}`, `{"type": "number", "value": 142500}`,
 * `{"type": "money", "amount": "350.00", "currency": "RON"}`, `{"type": "date", "value": "2027-03-31"}`,
 * `{"type": "bool", "value": true}`, `{"type": "choices", "value": ["Căpușe", "Purici"]}`.
 */
sealed interface FieldValue {
    data class Text(val value: String) : FieldValue

    data class Number(val value: Double) : FieldValue

    data class Amount(val value: Money) : FieldValue

    data class Day(val value: CalendarDay) : FieldValue

    data class Toggle(val value: Boolean) : FieldValue

    data class Choices(val value: List<String>) : FieldValue

    /** Carries nothing worth keeping: empty text, an empty list. */
    val isEmpty: Boolean
        get() = when (this) {
            is Text -> value.isBlank()
            is Choices -> value.isEmpty()
            else -> false
        }

    val textValue: String? get() = (this as? Text)?.value

    fun toJson(): JsonObject = when (this) {
        is Text -> typed("text", JsonPrimitive(value))
        is Number -> typed("number", MachineText.number(value))
        is Amount -> JsonObject(mapOf("type" to JsonPrimitive("money")) + value.toJson())
        is Day -> typed("date", JsonPrimitive(value.isoString))
        is Toggle -> typed("bool", JsonPrimitive(value))
        is Choices -> typed("choices", JsonArray(value.map(::JsonPrimitive)))
    }

    companion object {
        private fun typed(type: String, value: JsonElement) =
            JsonObject(mapOf("type" to JsonPrimitive(type), "value" to value))

        /** The value [json] holds, or null when this build can't read it (a type from a newer build). */
        fun read(json: JsonElement): FieldValue? = try {
            val record = JsonRecord.of(json)
            when (record.string("type")) {
                "text" -> Text(record.string("value"))
                "number" -> Number(record.double("value"))
                "money" -> Amount(Money.fromJson(json) ?: throw UnreadableRecord())
                "date" -> Day(record.day("value"))
                "bool" -> Toggle(record.bool("value"))
                "choices" -> Choices(record.strings("value"))
                else -> null
            }
        } catch (_: UnreadableRecord) {
            null
        }
    }
}

/**
 * A section's values by field key, as the iOS app's `FieldValues`: a value this build can't
 * read (a type a newer build wrote) is kept as stored and written back, and goes only when its
 * field gets a new value. A value set empty is no value.
 */
class FieldValues private constructor(
    val storage: Map<String, FieldValue>,
    /** Values this build can't read, raw, by key. */
    val unreadable: Map<String, JsonElement>,
) {
    constructor(storage: Map<String, FieldValue> = emptyMap()) : this(storage.filterValues { !it.isEmpty }, emptyMap())

    operator fun get(key: String): FieldValue? = storage[key]

    /** The same values with [key] set to [value], or without it for null or an empty one. */
    fun with(key: String, value: FieldValue?): FieldValues {
        val next = storage.toMutableMap()
        if (value != null && !value.isEmpty) next[key] = value else next.remove(key)
        return FieldValues(next, unreadable - key)
    }

    /** The same values with every value this build can't read changed by [transform], or left out for null. */
    fun mappingUnreadable(transform: (JsonElement) -> JsonElement?): FieldValues =
        FieldValues(storage, unreadable.mapNotNull { (key, raw) -> transform(raw)?.let { key to it } }.toMap())

    /** The same values with every one [other] can't read, raw, for each field that has none here. */
    fun addingUnreadable(of: FieldValues): FieldValues {
        val added = unreadable.toMutableMap()
        for ((key, raw) in of.unreadable) if (storage[key] == null && added[key] == null) added[key] = raw
        return FieldValues(storage, added)
    }

    fun toJson(): JsonObject {
        val fields = LinkedHashMap<String, JsonElement>()
        for ((key, raw) in unreadable) if (storage[key] == null) fields[key] = raw
        for ((key, value) in storage) fields[key] = value.toJson()
        return JsonObject(fields)
    }

    override fun equals(other: Any?): Boolean =
        other is FieldValues && other.storage == storage && other.unreadable.keys == unreadable.keys &&
            unreadable.all { (key, raw) -> JsonTrees.same(raw, other.unreadable.getValue(key)) }

    override fun hashCode(): Int = storage.hashCode()

    override fun toString(): String = toJson().toString()

    companion object {
        /** Reads every value it can; one it can't is kept raw, so the rest of the section still reads. */
        val codec: JsonCodec<FieldValues> = object : JsonCodec<FieldValues> {
            override fun decode(json: JsonElement): FieldValues? {
                val fields = json as? JsonObject ?: return null
                val read = LinkedHashMap<String, FieldValue>()
                val kept = LinkedHashMap<String, JsonElement>()
                for ((key, raw) in fields) {
                    val value = FieldValue.read(raw)
                    if (value != null) read[key] = value else kept[key] = raw
                }
                return FieldValues(read, kept)
            }

            override fun encode(value: FieldValues): JsonElement = value.toJson()
        }
    }
}

/**
 * A free row under Date importante, as the iOS app's `CustomFact`: "Loc în port", "Ponton 3".
 * A secret row ([isSecret], an alarm or Wi-Fi code) holds only sealed text and never leaves the
 * phone ([SecretRules]).
 */
data class CustomFact(
    val id: UUID,
    val label: String,
    val value: String,
    val isSensitive: Boolean = false,
    val isSecret: Boolean = false,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id.toString())
        put("label", label)
        put("value", value)
        if (isSensitive || isSecret) put("isSensitive", true)
        if (isSecret) put("isSecret", true)
    }

    companion object {
        /** Read as iOS reads one: an id that isn't one gets a new id; a secret row is sensitive too. */
        val codec: JsonCodec<CustomFact> = object : JsonCodec<CustomFact> {
            override fun decode(json: JsonElement): CustomFact? = try {
                val record = JsonRecord.of(json)
                val secret = record.boolOrNull("isSecret") ?: false
                CustomFact(
                    id = record.stringOrNull("id")?.let(Ids::parse) ?: UUID.randomUUID(),
                    label = record.string("label"),
                    value = record.string("value"),
                    isSensitive = (record.boolOrNull("isSensitive") ?: false) || secret,
                    isSecret = secret,
                )
            } catch (_: UnreadableRecord) {
                null
            }

            override fun encode(value: CustomFact): JsonElement = value.toJson()
        }
    }
}
