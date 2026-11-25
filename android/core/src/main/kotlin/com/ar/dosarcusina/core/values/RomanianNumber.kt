package com.ar.dosarcusina.core.values

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.util.regex.Pattern

/** What a number is, so the reader knows which rule settles a doubtful case. */
enum class NumberKind(val key: String) {
    /** An amount of money: decimals allowed. */
    MONEY("money"),

    /** Something counted: whole numbers only. */
    COUNT("count"),

    /** A meter index or another measured value (a weight): decimals allowed. */
    METER_INDEX("meterIndex"),

    /** A kilometre reading: whole numbers only. */
    KILOMETRES("kilometres"),
    ;

    /** Kilometres and counts have no decimals, so "45,724 km" can only be 45724. */
    val isWhole: Boolean get() = this == COUNT || this == KILOMETRES

    companion object {
        /**
         * The kind of a typed field's number: kilometres by their unit, whole numbers when the
         * field shows no decimals, any other measured value otherwise.
         */
        fun forField(unit: MeasurementUnit?, allowsDecimals: Boolean = true): NumberKind = when {
            unit == MeasurementUnit.KILOMETRES -> KILOMETRES
            allowsDecimals -> METER_INDEX
            else -> COUNT
        }
    }
}

/** Where a number comes from: a document's number that could be read two ways is marked "Verifică". */
enum class NumberOrigin { TYPED, DOCUMENT }

/**
 * The one reader for numbers written by people and printed on Romanian documents, as the iOS
 * app's `RomanianNumber` (ios/DosarCuSina/Models/Values/RomanianNumber.swift). The rule, the
 * owner's:
 *
 * - a comma is the decimal mark and a dot groups thousands: "1.250,50" is 1250.5;
 * - a number with both marks takes the last one as the decimal mark ("1,250.50" too);
 * - kilometres and counts are whole, so any single mark followed by three digits groups
 *   thousands: "45,724 km" and "45.724 km" are both 45724;
 * - a money amount or a meter index with one mark and exactly three digits after it follows
 *   the Romanian rule ("3,750" is 3,75 and "45.724" is 45724) and is ambiguous: from a document
 *   it gets "Verifică";
 * - anything it can't read clearly ("-", ".", "12-5", "5²", "12 km" for money) is refused,
 *   never read as 0 or cut short.
 *
 * Numbers are [BigDecimal]s, never Doubles. Archives and stored JSON use the machine form
 * ("1250.5"), read with [canonical].
 */
object RomanianNumber {
    /** A number read clearly. */
    data class Reading(val value: BigDecimal, val isAmbiguous: Boolean, val needsCheck: Boolean)

    /** Why a text isn't a number of the kind asked for. */
    enum class Problem(val key: String) {
        /** Nothing written. */
        EMPTY("empty"),

        /** Not a number that can be read one way only. */
        UNREADABLE("unreadable"),

        /** Below zero. */
        NEGATIVE("negative"),

        /** Decimals where the kind is whole (kilometres, counts). */
        NOT_WHOLE("notWhole"),
    }

    /** A reading, or why there is none. */
    sealed interface Outcome {
        data class Read(val reading: Reading) : Outcome

        data class Refused(val problem: Problem) : Outcome
    }

    // Reading

    /**
     * Reads [raw] as a number of [kind]. A label before a colon ("Index nou: 12.345") and the
     * kind's unit after the number ("86.420 km", "350 lei", or [unit]) are allowed.
     */
    fun read(
        raw: String,
        kind: NumberKind,
        origin: NumberOrigin = NumberOrigin.TYPED,
        unit: MeasurementUnit? = null,
    ): Outcome {
        var text = raw
        for (space in listOf("\u00A0", "\u202F", "\u2009", "\t")) text = text.replace(space, " ")
        text = TextRules.trimming(text, TextRules::isWhitespaceOrNewline)
        if (text.isEmpty()) return Outcome.Refused(Problem.EMPTY)
        return number(droppingUnit(droppingLabel(text), kind, unit), kind, origin)
    }

    /** The number [text] is once its label and unit are gone: a sign, then digits read by the rule. */
    private fun number(text: String, kind: NumberKind, origin: NumberOrigin): Outcome {
        val sign = TextRules.characters(text).firstOrNull()?.takeIf { it == "-" || it == "\u2212" }
        val negative = sign != null
        val unsigned = sign?.let { TextRules.trimming(text.substring(it.length), TextRules::isWhitespace) } ?: text
        val parsed = GroupedDigits.read(unsigned, kind)
        val problem = when {
            parsed == null -> Problem.UNREADABLE
            negative && parsed.value.signum() != 0 -> Problem.NEGATIVE
            kind.isWhole && DecimalText.normalized(parsed.value).scale() > 0 -> Problem.NOT_WHOLE
            else -> null
        }
        if (parsed == null || problem != null) return Outcome.Refused(problem ?: Problem.UNREADABLE)
        val needsCheck = parsed.ambiguous && origin == NumberOrigin.DOCUMENT
        return Outcome.Read(Reading(parsed.value, parsed.ambiguous, needsCheck))
    }

    /** The value of [raw], or null when it isn't clearly a number of [kind]. */
    fun value(
        raw: String,
        kind: NumberKind,
        origin: NumberOrigin = NumberOrigin.TYPED,
        unit: MeasurementUnit? = null,
    ): BigDecimal? = (read(raw, kind, origin, unit) as? Outcome.Read)?.reading?.value

    /** Reads the plain machine form archives and stored JSON use: "1250.5", "-3", "45724". */
    fun canonical(raw: String): BigDecimal? {
        val text = TextRules.trimming(raw, TextRules::isWhitespace)
        if (!CANONICAL.matcher(text).find()) return null
        return DecimalText.read(text)
    }

    // Writing

    /**
     * How a number reads in a field or on screen, the Romanian way: "45.724", "1.250,5", with
     * between [fewestFractionDigits] and [mostFractionDigits] decimals, half rounded to even.
     * What this writes, [read] reads back to the same value.
     */
    fun format(
        value: BigDecimal,
        fewestFractionDigits: Int = 0,
        mostFractionDigits: Int = 2,
        groupsDigits: Boolean = true,
    ): String {
        var rounded = value.setScale(mostFractionDigits, RoundingMode.HALF_EVEN)
        // Trailing zeros go, down to the fewest decimals asked for.
        while (rounded.scale() > fewestFractionDigits && rounded.unscaledValue().mod(BigInteger.TEN).signum() == 0) {
            rounded = rounded.setScale(rounded.scale() - 1)
        }
        val plain = rounded.abs().toPlainString()
        val whole = plain.substringBefore('.')
        val fraction = plain.substringAfter('.', "")
        val grouped = if (groupsDigits) whole.reversed().chunked(GROUP).joinToString(".").reversed() else whole
        val sign = if (value.signum() < 0) "-" else ""
        return sign + grouped + (if (fraction.isEmpty()) "" else ",$fraction")
    }

    // Pieces

    private const val GROUP = 3

    /** The machine form: digits (Unicode's, as the iOS pattern reads them), maybe a dot and more. */
    private val CANONICAL: Pattern = Pattern.compile("^-?\\d+(\\.\\d+)?$", Pattern.UNICODE_CHARACTER_CLASS)

    /** "Index nou: 12.345" → "12.345". Only a label without digits is dropped, so "12:30" stays unreadable. */
    private fun droppingLabel(text: String): String {
        val characters = TextRules.characters(text)
        val colon = characters.lastIndexOf(":")
        if (colon < 0) return text
        val label = characters.subList(0, colon)
        if (label.any(TextRules::isNumber) || label.none(TextRules::isLetter)) return text
        val value = characters.subList(colon + 1, characters.size).joinToString("")
        return TextRules.trimming(value, TextRules::isWhitespace)
    }

    /** Units a kind may carry after its number, folded; measured ones from the unit catalog, in every spelling. */
    private fun units(kind: NumberKind): List<String> = when (kind) {
        NumberKind.MONEY -> listOf("lei", "leu", "ron", "eur", "euro", "€", "usd", "$")
        NumberKind.KILOMETRES -> MeasurementUnit.KILOMETRES.spellings.toList()
        NumberKind.METER_INDEX -> MeasurementUnit.METER_UNITS.flatMap { it.spellings }
        NumberKind.COUNT -> emptyList()
    }

    private fun droppingUnit(text: String, kind: NumberKind, unit: MeasurementUnit?): String {
        val folded = MeasurementUnit.fold(text)
        val candidates = (units(kind) + (unit?.spellings?.toList() ?: emptyList()))
            .filter { it.isNotEmpty() }
            .sortedByDescending { TextRules.characters(it).size }
        return candidates.filter { folded.endsWith(it) }.firstNotNullOfOrNull { candidate ->
            val number = TextRules.droppingLast(text, TextRules.characters(candidate).size)
            val kept = TextRules.trimming(number, TextRules::isWhitespace)
            // "12km" and "12 km" both drop the unit; "kkm" never leaves letters behind.
            val last = TextRules.characters(kept).lastOrNull()
            kept.takeUnless { last != null && TextRules.isLetter(last) }
        } ?: text
    }
}

/**
 * Digits with dots, commas or spaces between them, read by [RomanianNumber]'s rule: which mark
 * groups thousands and which one is the decimal mark, and when that is a doubt.
 */
private object GroupedDigits {
    private const val GROUP = 3

    /** Digits with dots, commas or spaces between them. */
    private val GROUPED: Pattern = Pattern.compile("^\\d+([., ]\\d+)*$", Pattern.UNICODE_CHARACTER_CLASS)

    class Parsed(val value: BigDecimal, val ambiguous: Boolean)

    /** Thousands groups: the first of one to three digits, every other of exactly three. */
    private fun groupsThousands(parts: List<String>): Boolean {
        val first = parts.firstOrNull() ?: return false
        if (TextRules.characters(first).size !in 1..GROUP) return false
        if (parts.size > 1 && first.startsWith("0")) return false
        return parts.drop(1).all { TextRules.characters(it).size == GROUP }
    }

    private fun number(whole: List<String>, fraction: String?, ambiguous: Boolean = false): Parsed? {
        val plain = whole.joinToString("") + (fraction?.let { ".$it" } ?: "")
        return DecimalText.read(plain)?.let { Parsed(it, ambiguous) }
    }

    /** Digits with dots, commas or spaces between them, read by the rule above. */
    @Suppress("CyclomaticComplexMethod", "ReturnCount") // The rule, case by case, as on iOS.
    fun read(text: String, kind: NumberKind): Parsed? {
        if (!GROUPED.matcher(text).find()) return null
        val groups = mutableListOf<String>()
        val marks = mutableListOf<String>()
        val current = StringBuilder()
        for (character in TextRules.characters(text)) {
            if (TextRules.isNumber(character)) {
                current.append(character)
            } else {
                groups.add(current.toString())
                marks.add(character)
                current.clear()
            }
        }
        groups.add(current.toString())

        if (marks.isEmpty()) return number(groups, null)

        val distinct = marks.filter { it != " " }.toCollection(LinkedHashSet())
        val last = marks.last()
        return when (distinct.size) {
            // Spaces only: "1 250 000".
            0 -> if (groupsThousands(groups)) number(groups, null) else null
            // "1.250,50" or "1,250.50": the last mark is the decimal one, once, after groups.
            2 -> {
                if (last == " " || marks.count { it == last } != 1 || !groupsThousands(groups.dropLast(1))) return null
                number(groups.dropLast(1), groups.last())
            }
            else -> oneMark(groups, marks, distinct.first(), kind)
        }
    }

    /** One dot or comma, maybe after space groups ("1 250,50"), or the same mark several times. */
    private fun oneMark(groups: List<String>, marks: List<String>, mark: String, kind: NumberKind): Parsed? {
        if (marks.count { it == mark } > 1) {
            // "1.250.500": only thousands.
            return if (groupsThousands(groups)) number(groups, null) else null
        }
        // It has to be the last mark.
        if (marks.last() != mark) return null
        val before = groups.dropLast(1)
        val after = groups.last()
        val canGroup = TextRules.characters(after).size == GROUP && groupsThousands(groups)
        val canBeDecimal = before.size == 1 || groupsThousands(before)
        return when {
            canGroup && kind.isWhole -> number(groups, null)
            // The doubtful case: the Romanian rule decides, and says so.
            canGroup && canBeDecimal ->
                if (mark == ",") number(before, after, ambiguous = true) else number(groups, null, ambiguous = true)
            canGroup -> number(groups, null)
            canBeDecimal -> number(before, after)
            else -> null
        }
    }
}
