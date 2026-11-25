package com.ar.dosarcusina.core.values

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset

/**
 * Text written for machines, not people: ISO days, moments, hex digests and machine JSON, as the
 * iOS app's `MachineText` (ios/Shared/MachineText.swift). ASCII digits, zero-padded, never
 * localized, so stored values, archives and fingerprints read the same on every phone and on
 * both platforms. The one place such text is written.
 */
object MachineText {
    /** `padded(7, 2)` is "07"; a longer number is kept whole. */
    fun padded(number: Long, width: Int): String {
        val digits = number.toString()
        return "0".repeat(maxOf(0, width - digits.length)) + digits
    }

    /** An ISO 8601 calendar date: `2031-03-12`. */
    fun isoDay(year: Int, month: Int, day: Int): String =
        "${padded(year.toLong(), YEAR_WIDTH)}-${isoMonthDay(month, day)}"

    /** A month and day as ISO writes them inside a date: `03-12`. */
    fun isoMonthDay(month: Int, day: Int): String = "${padded(month.toLong(), 2)}-${padded(day.toLong(), 2)}"

    /** Bytes as lowercase hex, two digits each: a digest's fingerprint. */
    fun hex(bytes: ByteArray): String {
        val text = StringBuilder(bytes.size * 2)
        for (byte in bytes) {
            val value = byte.toInt() and BYTE_MASK
            text.append(HEX_DIGITS[value ushr NIBBLE]).append(HEX_DIGITS[value and NIBBLE_MASK])
        }
        return text.toString()
    }

    // Moments

    /** A moment as machine JSON writes it: ISO 8601 in UTC, to the second (`2026-11-02T08:00:00Z`), no fraction. */
    fun moment(instant: Instant): String {
        val time = LocalDateTime.ofEpochSecond(instant.epochSecond, 0, ZoneOffset.UTC)
        val clock = listOf(time.hour, time.minute, time.second).joinToString(":") { padded(it.toLong(), 2) }
        return isoDay(time.year, time.monthValue, time.dayOfMonth) + "T" + clock + "Z"
    }

    /**
     * A moment written as ISO 8601, as the iOS reader reads it; null when it isn't one. It reads
     * what every writer so far wrote: with or without fractional seconds, with any UTC offset,
     * or a day alone (its start in UTC). See [MomentReader] for the forms it takes.
     */
    fun moment(raw: String): Instant? = MomentReader.read(raw)

    // JSON

    /** How machine JSON is laid out. Every layout sorts its keys, so the same value always gives the same bytes. */
    enum class JsonLayout {
        /** One line, slashes escaped: what the app keeps and hands its parts. */
        COMPACT,

        /** Indented by two spaces, `"key" : value`, slashes as they are: a `.dosar` archive, which people may open. */
        READABLE,
    }

    /** The one JSON writer for machine text: [element] as the iOS app's `MachineText.jsonEncoder` writes it. */
    fun json(element: JsonElement, layout: JsonLayout = JsonLayout.COMPACT): String =
        StringBuilder().also { JsonTextWriter(it, layout).write(element, 0) }.toString()

    /** Reads JSON text into a tree that keeps every number's text as written. Throws [SerializationException]. */
    fun parse(text: String): JsonElement = reader.parseToJsonElement(text)

    /** [text] read as JSON, or null when it isn't. */
    fun parseOrNull(text: String): JsonElement? =
        try {
            parse(text)
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }

    /** The kotlinx reader and writer the value rules decode and encode records with, as the iOS coders do. */
    @OptIn(ExperimentalSerializationApi::class) // Nothing written for null, as Swift's encodeIfPresent.
    val reader: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    /** A whole number as JSON. */
    fun number(value: Long): JsonPrimitive = JsonPrimitive(value)

    /**
     * A Double as the iOS app's JSON writer writes it: its shortest digits, plain between 0.0001
     * and 2^53 and with an exponent otherwise (`1e-05`, `1.8014398509481984e+16`), and no `.0`
     * after a whole number. Not a number or an infinity has no JSON form.
     */
    fun number(value: Double): JsonPrimitive {
        require(value.isFinite()) { "JSON has no form for $value" }
        return parse(DoubleText.write(value)) as JsonPrimitive
    }

    private const val YEAR_WIDTH = 4
    private const val BYTE_MASK = 0xFF
    private const val NIBBLE = 4
    private const val NIBBLE_MASK = 0x0F
    private const val HEX_DIGITS = "0123456789abcdef"
}

/** How the iOS app writes a Double: Swift's `description`, without a `.0` after a whole number. */
internal object DoubleText {
    private const val MOST_DIGITS = 17
    private const val PLAIN_ABOVE = 9_007_199_254_740_992.0 // 2^53
    /** 0.0001 is 0.1 × 10^-3, written plain; 0.00001 is 0.1 × 10^-4, written with an exponent. */
    private const val SMALLEST_PLAIN_EXPONENT = -3

    fun write(value: Double): String {
        if (value == 0.0) return if (1.0 / value < 0) "-0" else "0"
        val digits = shortest(value)
        val negative = value < 0
        val unscaled = digits.unscaledValue().abs().toString().trimEnd('0').ifEmpty { "0" }
        // The value is 0.unscaled × 10^exponent.
        val exponent = digits.precision() - digits.scale()
        val magnitude = Math.abs(value)
        val text = if (magnitude > PLAIN_ABOVE || exponent < SMALLEST_PLAIN_EXPONENT) {
            exponential(unscaled, exponent - 1)
        } else {
            plain(unscaled, exponent)
        }
        return if (negative) "-$text" else text
    }

    /** The fewest significant digits that read back as [value], the closest of them to it. */
    private fun shortest(value: Double): BigDecimal {
        val exact = BigDecimal(value)
        return (1..MOST_DIGITS).firstNotNullOfOrNull { precision ->
            // The nearest of this many digits, or the one on the other side when only it reads back.
            listOf(RoundingMode.HALF_EVEN, RoundingMode.FLOOR, RoundingMode.CEILING)
                .map { exact.round(MathContext(precision, it)) }
                .filter { it.toString().toDouble() == value }
                .minByOrNull { (it - exact).abs() }
        } ?: exact.round(MathContext(MOST_DIGITS, RoundingMode.HALF_EVEN))
    }

    private fun exponential(digits: String, exponent: Int): String {
        val mantissa = if (digits.length == 1) digits else digits[0] + "." + digits.substring(1)
        val sign = if (exponent < 0) "-" else "+"
        return mantissa + "e" + sign + MachineText.padded(Math.abs(exponent).toLong(), 2)
    }

    private fun plain(digits: String, exponent: Int): String = when {
        exponent <= 0 -> "0." + "0".repeat(-exponent) + digits
        exponent >= digits.length -> digits + "0".repeat(exponent - digits.length)
        else -> digits.substring(0, exponent) + "." + digits.substring(exponent)
    }
}

/** Writes a JSON tree as the iOS app's JSON encoder does, byte for byte. */
private class JsonTextWriter(private val out: StringBuilder, layout: MachineText.JsonLayout) {
    private val readable = layout == MachineText.JsonLayout.READABLE

    fun write(element: JsonElement, depth: Int) {
        when (element) {
            is JsonObject -> writeObject(element, depth)
            is JsonArray -> writeArray(element, depth)
            is JsonNull -> out.append("null")
            is JsonPrimitive -> if (element.isString) writeString(element.content) else out.append(element.content)
        }
    }

    private fun writeObject(element: JsonObject, depth: Int) {
        // Keys sorted by their code points, as Swift sorts them.
        val keys = element.keys.sortedWith(CodePointOrder)
        writeContainer('{', '}', keys.size, depth) { index ->
            val key = keys[index]
            writeString(key)
            out.append(if (readable) " : " else ":")
            write(element.getValue(key), depth + 1)
        }
    }

    private fun writeArray(element: JsonArray, depth: Int) {
        writeContainer('[', ']', element.size, depth) { index -> write(element[index], depth + 1) }
    }

    private inline fun writeContainer(open: Char, close: Char, count: Int, depth: Int, entry: (Int) -> Unit) {
        out.append(open)
        if (!readable) {
            for (index in 0 until count) {
                if (index > 0) out.append(',')
                entry(index)
            }
            out.append(close)
            return
        }
        out.append('\n')
        if (count == 0) out.append('\n')
        for (index in 0 until count) {
            indent(depth + 1)
            entry(index)
            out.append(if (index < count - 1) ",\n" else "\n")
        }
        indent(depth)
        out.append(close)
    }

    private fun indent(depth: Int) {
        repeat(depth) { out.append("  ") }
    }

    private fun writeString(text: String) {
        out.append('"')
        for (char in text) {
            when {
                char == '"' -> out.append("\\\"")
                char == '\\' -> out.append("\\\\")
                char == '/' && !readable -> out.append("\\/")
                char == '\n' -> out.append("\\n")
                char == '\r' -> out.append("\\r")
                char == '\t' -> out.append("\\t")
                char == '\b' -> out.append("\\b")
                char == '\u000C' -> out.append("\\f")
                char < ' ' -> out.append("\\u00").append(HEX[char.code ushr NIBBLE])
                    .append(HEX[char.code and LOW_NIBBLE])
                else -> out.append(char)
            }
        }
        out.append('"')
    }

    private companion object {
        const val HEX = "0123456789abcdef"
        const val NIBBLE = 4
        const val LOW_NIBBLE = 0x0F
    }
}

/** Text in the order of its code points: how Swift's JSON encoder sorts keys. */
internal object CodePointOrder : Comparator<String> {
    override fun compare(left: String, right: String): Int {
        var i = 0
        var j = 0
        while (i < left.length && j < right.length) {
            val a = left.codePointAt(i)
            val b = right.codePointAt(j)
            if (a != b) return a.compareTo(b)
            i += Character.charCount(a)
            j += Character.charCount(b)
        }
        return (left.length - i).compareTo(right.length - j)
    }
}
