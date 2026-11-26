package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.TextRules

/**
 * A Romanian postal address split into the parts that tell two places apart, as the iOS app's `PostalAddress`
 * (ios/DosarCuSina/Services/Subscriptions/PostalAddress.swift): "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12,
 * sector 3, București". The same place is written many ways ("Strada" or "Str.", "nr." or none, with or without
 * diacritics), so two addresses are compared part by part ([agreement]), never as text. Read with [read].
 *
 * Every part is folded ([RomanianText.fold]).
 */
data class PostalAddress(
    /** The street's name in words, without its type: "exemplului". */
    val street: List<String>,
    /** The street's type, in one form ("strada", "bulevardul", "calea"…), when printed. */
    val streetType: String?,
    val number: String?,
    val block: String?,
    val staircase: String?,
    val apartment: String?,
    val sector: String?,
    /** The city, town, commune or village, in words. */
    val locality: List<String>,
    /** The county, when printed ("jud. Brașov"). Not compared: the town tells places apart. */
    val county: List<String>,
) {
    /** How sure it is that two addresses name the same place, from least to most. */
    enum class Agreement {
        /** A part both print differs: another number, block, staircase, apartment, sector or town, or street. */
        DIFFERENT,

        /** Too little to compare. */
        UNKNOWN,

        /** Nothing differs, but something is missing or only nearly the same. */
        LIKELY,

        /** The same street and number and, at the most precise level either one names, the same unit. */
        SAME,
    }

    fun agreement(other: PostalAddress): Agreement {
        // A part both print and that differs is another place, whatever else agrees.
        val parts = listOf(
            number to other.number, block to other.block, staircase to other.staircase,
            apartment to other.apartment, sector to other.sector,
        )
        val partDiffers = parts.any { (mine, theirs) -> mine != null && theirs != null && mine != theirs }
        val townDiffers = locality.isNotEmpty() && other.locality.isNotEmpty() && locality.none { it in other.locality }
        if (partDiffers || townDiffers) return Agreement.DIFFERENT
        return when (PostalStreets.compare(street, other.street)) {
            PostalStreets.Agreement.DIFFERENT -> Agreement.DIFFERENT
            PostalStreets.Agreement.UNKNOWN -> villageAgreement(other)
            PostalStreets.Agreement.SIMILAR -> Agreement.LIKELY
            PostalStreets.Agreement.SAME -> sameStreetAgreement(other)
        }
    }

    /** A village without streets: the same village and the same number. */
    private fun villageAgreement(other: PostalAddress): Agreement {
        val sameVillage = street.isEmpty() && other.street.isEmpty() && locality.isNotEmpty() &&
            other.locality.isNotEmpty() && number != null && number == other.number
        return if (sameVillage) Agreement.LIKELY else Agreement.UNKNOWN
    }

    private fun sameStreetAgreement(other: PostalAddress): Agreement = when {
        number == null || other.number == null -> Agreement.LIKELY
        streetType != null && other.streetType != null && streetType != other.streetType -> Agreement.LIKELY
        sameUnit(other) -> Agreement.SAME
        else -> Agreement.LIKELY
    }

    /**
     * The most precise unit either address names (an apartment, else a staircase, else a block) is named by both.
     * Coarser parts only one side prints don't count against it. Neither naming one: a house.
     */
    private fun sameUnit(other: PostalAddress): Boolean {
        val levels = listOf(apartment to other.apartment, staircase to other.staircase, block to other.block)
        val precise = levels.firstOrNull { it.first != null || it.second != null } ?: return true
        return precise.first != null && precise.second != null
    }

    companion object {
        /**
         * Reads an address; null when the text doesn't name a place: a street with its type or a number, or a village
         * or town with a number.
         */
        fun read(text: String): PostalAddress? {
            val parser = PostalAddressParser().apply { parse(text) }
            // A street without its type counts only beside a printed marker ("nr.", "bl.", a town).
            val hasStreet = parser.street.isNotEmpty() &&
                (parser.streetType != null || (parser.number != null && parser.hasMarkers))
            val hasVillage = parser.street.isEmpty() && parser.locality.isNotEmpty() && parser.number != null
            return if (hasStreet || hasVillage) parser.address() else null
        }

        /**
         * Whether a line names only where a street is ("Sector 3, București", "Jud. Brașov"): the rest of an address on
         * two lines.
         */
        fun namesOnlyThePlace(line: String): Boolean {
            val parts = PostalAddressParser().apply { parse(line) }
            val unit = listOf(parts.number, parts.block, parts.staircase, parts.apartment).any { it != null }
            return parts.street.isEmpty() && parts.streetType == null && !unit &&
                (parts.sector != null || parts.locality.isNotEmpty() || parts.county.isNotEmpty())
        }

        /**
         * Whether a word starts or marks a part of an address ("Str.", "nr.", "bl.", "jud.", "sector"), in any case,
         * with or without its dot.
         */
        fun isMarker(word: String): Boolean {
            val folded = TextRules.characters(RomanianText.fold(word)).filter(TextRules::isLetter).joinToString("")
            return folded.isNotEmpty() && PostalAddressParser.marker(folded) != null
        }
    }
}

/** Comparing two streets' names. */
internal object PostalStreets {
    enum class Agreement { SAME, SIMILAR, DIFFERENT, UNKNOWN }

    private const val SHORTEST_SHARED_WORD = 4
    private const val SHORTEST_ABBREVIATION = 2
    private const val LONGEST_ABBREVIATION = 3
    private const val SHORTEST_SHARED_START = 5
    private const val SHARED_SHARE = 0.8

    /** Words that name nothing on their own: not "de" or "la". */
    private val fillers = setOf("de", "la", "si", "lui", "din", "cu")

    /**
     * Two street names: every word on each side found on the other (an abbreviation counts, "Gh." for "Gheorghe");
     * or, at least, a longer word they share or nearly share ("Exemplu" and "Exemplului").
     */
    fun compare(mine: List<String>, theirs: List<String>): Agreement {
        val left = significant(mine)
        val right = significant(theirs)
        if (left.isEmpty() || right.isEmpty()) return Agreement.UNKNOWN
        val allFound = left.all { word -> right.any { sameWord(word, it) } } &&
            right.all { word -> left.any { sameWord(word, it) } }
        if (allFound) return Agreement.SAME
        val shares = left.any { word ->
            length(word) >= SHORTEST_SHARED_WORD && right.any { sameWord(word, it) || nearlySameWord(word, it) }
        }
        return if (shares) Agreement.SIMILAR else Agreement.DIFFERENT
    }

    /** Words that name a street: not initials, not "de" or "la". */
    private fun significant(words: List<String>): List<String> =
        words.filter { (length(it) >= 2 || allNumbers(it)) && it !in fillers }

    /** The same word, or a short abbreviation of it. */
    private fun sameWord(a: String, b: String): Boolean {
        if (a == b) return true
        val (short, long) = if (length(a) < length(b)) a to b else b to a
        return length(short) in SHORTEST_ABBREVIATION..LONGEST_ABBREVIATION &&
            TextRules.characters(short).none(TextRules::isNumber) && long.startsWith(short)
    }

    /** Another ending of the same word: "exemplu", "exemplului". */
    private fun nearlySameWord(a: String, b: String): Boolean {
        val left = TextRules.characters(a)
        val right = TextRules.characters(b)
        val shared = left.zip(right).takeWhile { it.first == it.second }.size
        return shared >= SHORTEST_SHARED_START && shared >= SHARED_SHARE * minOf(left.size, right.size)
    }

    internal fun length(word: String): Int = TextRules.characters(word).size

    internal fun allNumbers(word: String): Boolean = TextRules.characters(word).all(TextRules::isNumber)
}
