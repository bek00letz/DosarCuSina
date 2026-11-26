package com.ar.dosarcusina.core.text

/**
 * How [CardNumberRuns] reads a number printed in groups, as the iOS app's rule does
 * (ios/Shared/CardNumberRule.swift, "Runs of digits"): what may stand between two groups, a digit
 * of any script as its ASCII digit, and where the groups of a run sit.
 */
internal object DigitGroups {
    private const val DECIMAL = 10
    private const val LARGEST_DIGIT = 9
    private const val YEAR = 4
    private const val LONGEST_DAY = 2
    private const val LAST_DAY = 31
    private const val LAST_MONTH = 12

    /**
     * What may stand between two groups of a number's digits: a run of spaces (any kind of space, a
     * tab included), or one dash, dot or slash with spaces around it or none.
     */
    const val GAP = """(?:[\t\p{Zs}]*+[-./][\t\p{Zs}]*+|[\t\p{Zs}]++)"""

    /** Whether a character is part of what stands between two groups ([GAP]). */
    fun isGapCharacter(character: Char): Boolean =
        character == '-' || character == '.' || character == '/' || character == '\t' ||
            Character.getType(character) == Character.SPACE_SEPARATOR.toInt()

    /** A decimal digit of any script as its ASCII digit ("٤", "４" and "4" are all "4"), or null. */
    fun digit(codePoint: Int): Char? {
        if (Character.getType(codePoint) != Character.DECIMAL_DIGIT_NUMBER.toInt()) return null
        val value = Character.digit(codePoint, DECIMAL)
        return if (value in 0..LARGEST_DIGIT) '0' + value else null
    }

    /** The groups of digits in [range]: the pieces between its gaps. */
    fun groups(text: String, range: IntRange): List<IntRange> {
        val groups = mutableListOf<IntRange>()
        var groupStart: Int? = null
        for (index in range) {
            if (isGapCharacter(text[index])) {
                groupStart?.let { groups.add(it until index) }
                groupStart = null
            } else if (groupStart == null) {
                groupStart = index
            }
        }
        groupStart?.let { groups.add(it..range.last) }
        return groups
    }

    /** How many groups a date has. */
    const val DATE_GROUPS = 3

    /**
     * Whether three groups, by their sizes and values, are a date: a day and a month (either way
     * round) then a year of four digits ("01.02.2026", "2/1/2026"), or the year first ("2026-02-01").
     */
    fun isDate(sizes: List<Int>, values: List<Int>): Boolean = when {
        isDayOrMonth(sizes[0]) && isDayOrMonth(sizes[1]) && sizes[2] == YEAR ->
            isDayAndMonth(values[0], values[1]) || isDayAndMonth(values[1], values[0])
        sizes[0] == YEAR && isDayOrMonth(sizes[1]) && isDayOrMonth(sizes[2]) -> isDayAndMonth(values[2], values[1])
        else -> false
    }

    private fun isDayOrMonth(size: Int): Boolean = size in 1..LONGEST_DAY

    private fun isDayAndMonth(day: Int, month: Int): Boolean = day in 1..LAST_DAY && month in 1..LAST_MONTH

    /** Whether two places in a text share a character. */
    fun overlaps(left: IntRange, right: IntRange): Boolean = left.first <= right.last && right.first <= left.last

    /** What stands between two groups of a run. */
    class Gap(text: String) {
        enum class Kind { SPACE, DASH, DOT, SLASH }

        val kind: Kind = when {
            '-' in text -> Kind.DASH
            '.' in text -> Kind.DOT
            '/' in text -> Kind.SLASH
            else -> Kind.SPACE
        }

        /** One space or one dash: the way most numbers are printed in groups. */
        val isNarrow: Boolean = text == " " || text == "-"
    }
}
