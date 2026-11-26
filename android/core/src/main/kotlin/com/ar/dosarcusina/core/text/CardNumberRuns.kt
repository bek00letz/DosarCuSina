package com.ar.dosarcusina.core.text

import com.ar.dosarcusina.core.values.TextRules

/**
 * How [PaymentCardNumbers] finds card numbers in text, as the iOS app's rule does
 * (ios/Shared/CardNumberRule.swift, "Runs of digits" and "Brands"): runs of digits with at most
 * one space or dash between them, the parts of a longer run that are printed like a card, what of
 * a run belongs to an IBAN or a code, the networks' issuer ranges and the Luhn check.
 */
internal object CardNumberRuns {
    private const val SHORTEST_CARD = 14
    private const val LONGEST_CARD = 19
    private val cardLengths = SHORTEST_CARD..LONGEST_CARD
    private const val ANYWHERE_LEAST = 12
    private const val STRICT_LEAST = 8
    private const val GROUP = 4
    private const val SIXTEEN = 16
    private const val IBAN_HEAD_REACH = 48
    private const val DECIMAL = 10
    private const val LARGEST_DIGIT = 9

    /** A run of digits found in a text, or a part of one: its groups, the pieces between single spaces or dashes. */
    class Run(text: String, val groups: List<IntRange>, val isWhole: Boolean) {
        val range: IntRange = groups.first().first..groups.last().last
        private val pieces = groups.map { group -> text.substring(group).filter { it in '0'..'9' } }
        val digits: String = pieces.joinToString("")
        val groupSizes: List<Int> = pieces.map { it.length }

        /** Printed in groups of four ("4111 1111 1111 1111"). */
        private val groupedInFours: Boolean
            get() = groupSizes.size >= 3 && groupSizes.all { it == GROUP }

        /**
         * Printed the way cards print their number: in one piece, in groups of four (19 digits end
         * with three), or in American Express's and Diners Club's 4-6-5 and 4-6-4.
         */
        private val printedLikeACard: Boolean
            get() {
                val last = groupSizes.lastOrNull() ?: return false
                if (groupSizes.size == 1 || groupSizes == AMEX || groupSizes == DINERS) return true
                return groupSizes.dropLast(1).all { it == GROUP } && last in GROUP - 1..GROUP
            }

        /**
         * A card number by the "anywhere" rule. A whole run printed in groups of four counts even
         * when its check digit was misread; a part of a longer run must pass the check and be
         * printed like a card, since inside a long number printed in fours every part is.
         */
        val isCardNumber: Boolean
            get() {
                val brand = brand(digits)
                if (digits.length !in cardLengths || brand == null || digits.length !in brand.lengths) return false
                if (!isWhole) return printedLikeACard && passesLuhn(digits)
                return passesLuhn(digits) || (groupedInFours && digits.length == SIXTEEN)
            }

        val masked: String
            get() = if (digits.length >= ANYWHERE_LEAST) {
                "${PaymentCardNumbers.MASK} ${digits.takeLast(GROUP)}"
            } else {
                PaymentCardNumbers.MASK
            }

        private companion object {
            val AMEX = listOf(4, 6, 5)
            val DINERS = listOf(4, 6, 4)
        }
    }

    /**
     * Runs of digits with at most one space or dash between them, not part of a longer run:
     * twelve digits or more, or ([strict]) eight or more.
     */
    fun runs(text: String, strict: Boolean): List<Run> {
        val least = if (strict) STRICT_LEAST else ANYWHERE_LEAST
        val pattern = """(?<!\d[ -]?)\d(?:[ -]?\d){${least - 1},}(?![ -]?\d)"""
        return TextPattern.matches(pattern, text, caseInsensitive = false).map { match ->
            Run(text, groups(text, match.range), isWhole = true)
        }
    }

    /**
     * The card numbers in the text by the "anywhere" rule, in order: a whole run of digits that is
     * one, else the parts of a longer run that are ([parts]), looked for only in what of the run
     * isn't a code ([pieces]).
     */
    fun cardNumbers(text: String): List<Run> {
        val characters = Characters(text)
        val ibans = if (hasLetter(text)) IBAN.ranges(text) else emptyList()
        return runs(text, strict = false).flatMap { run ->
            pieces(run, text, characters, ibans).flatMap { piece ->
                if (piece.isCardNumber) listOf(piece) else parts(piece, text)
            }
        }
    }

    /** Whether any code point is a letter: a quicker form of Swift's check, which finds the same IBANs. */
    private fun hasLetter(text: String): Boolean = text.codePoints().anyMatch(Character::isAlphabetic)

    /**
     * What of a run can be a card number, once the digits that belong to a code are left out: the
     * groups inside an IBAN that passes its check ([ibans]); a group glued to a letter before or
     * after it, with nothing between; and, with no IBAN that passes its check there, groups that
     * carry on an IBAN printed in groups ([continuesAnIBAN]). Anything left out of a run makes what
     * remains a part of it, which must pass the Luhn check and be printed like a card.
     */
    private fun pieces(run: Run, text: String, characters: Characters, ibans: List<IntRange>): List<Run> {
        val overlapsIBAN = { group: IntRange -> ibans.any { it.first <= group.last && group.first <= it.last } }
        val hasIBAN = run.groups.any(overlapsIBAN)
        val stretches = mutableListOf<List<IntRange>>()
        var current = mutableListOf<IntRange>()
        for (group in run.groups) {
            if (overlapsIBAN(group)) {
                if (current.isNotEmpty()) stretches.add(current)
                current = mutableListOf()
            } else {
                current.add(group)
            }
        }
        if (current.isNotEmpty()) stretches.add(current)
        return stretches.mapNotNull { stretch ->
            var groups: List<IntRange> = stretch
            if (characters.before(groups.first().first)?.let(TextRules::isLetter) == true) groups = groups.drop(1)
            if (groups.isNotEmpty() && characters.at(groups.last().last + 1)?.let(TextRules::isLetter) == true) {
                groups = groups.dropLast(1)
            }
            if (groups.isEmpty()) return@mapNotNull null
            val piece = if (groups.size == run.groups.size) run else Run(text, groups, isWhole = false)
            piece.takeUnless { !hasIBAN && continuesAnIBAN(piece, characters) }
        }
    }

    /**
     * Whether the run carries on an IBAN printed in groups, its check passing or not: a country
     * that issues IBANs in capitals and two check digits, maybe groups of four letters or digits,
     * then the run, one space or dash apart ("RO49 AAAA 1234 5678 9012 3456").
     */
    private fun continuesAnIBAN(run: Run, characters: Characters): Boolean {
        val last = characters.before(run.range.first)
        if (last != " " && last != "-") return false
        val before = characters.suffix(run.range.first, IBAN_HEAD_REACH)
        val head = """(?<![\p{L}\p{N}])([A-Z]{2})\d{2}(?:[ -][A-Z0-9]{4})*[ -]$"""
        val country = TextPattern.first(head, before, caseInsensitive = false)?.get(1) ?: return false
        return IBAN.lengths[country] != null
    }

    /**
     * The card numbers inside a run that isn't one as a whole: a card number printed next to other
     * digits ("12 4111 1111 1111 1111", "4111-1111-1111-1111-27"). Only parts that begin and end
     * where the run's groups do are tried, from the left and the longest first at each place; a
     * part is taken when it is a card number. Digits with nothing between them stay one number. In
     * a run printed all in groups of four, a part is tried only at its start or right after a card
     * found there: never the middle or the end of a long number (a 20-digit health card number).
     */
    private fun parts(run: Run, text: String): List<Run> {
        val sizes = run.groupSizes
        if (sizes.size < 2) return emptyList()
        val startOnly = sizes.all { it == GROUP }
        val found = mutableListOf<Run>()
        var start = 0
        while (start < sizes.size) {
            val part = ends(sizes, start).asReversed().asSequence()
                .map { end -> Run(text, run.groups.subList(start, end + 1), isWhole = false) }
                .firstOrNull { it.isCardNumber }
            if (part != null) {
                found.add(part)
                start += part.groups.size
            } else if (startOnly) {
                // Printed all in fours: a card starts the run or follows one found before it.
                break
            } else {
                start += 1
            }
        }
        return found
    }

    /** The ends of the parts from [start] that give a card's length, shortest first; nothing longer is ever built. */
    private fun ends(sizes: List<Int>, start: Int): List<Int> {
        var length = 0
        val ends = mutableListOf<Int>()
        for (end in start until sizes.size) {
            length += sizes[end]
            if (length > cardLengths.last) break
            val isWhole = start == 0 && end == sizes.size - 1
            if (length in cardLengths && !isWhole) ends.add(end)
        }
        return ends
    }

    /** The groups of digits in [range]: the pieces between its spaces and dashes. */
    private fun groups(text: String, range: IntRange): List<IntRange> {
        val groups = mutableListOf<IntRange>()
        var groupStart: Int? = null
        for (index in range) {
            val separates = text[index] == ' ' || text[index] == '-'
            if (separates) {
                groupStart?.let { groups.add(it until index) }
                groupStart = null
            } else if (groupStart == null) {
                groupStart = index
            }
        }
        groupStart?.let { groups.add(it..range.last) }
        return groups
    }

    // Brands

    class Brand(val network: String, val lengths: IntRange)

    /** Numbers whose first [digits] digits are between [low] and [high] belong to [brand]. */
    private class IssuerRange(val low: Int, val high: Int, val digits: Int, val brand: Brand) {
        fun covers(number: String): Boolean {
            if (TextRules.characters(number).size < digits) return false
            val prefix = TextRules.swiftInt(TextRules.prefix(number, digits)) ?: return false
            return prefix in low..high
        }
    }

    // The networks' published issuer ranges and lengths are data, tried in this order.
    @Suppress("MagicNumber")
    private val issuers: List<IssuerRange> = run {
        val amex = Brand(PaymentCardNetwork.AMEX, 15..15)
        val visa = Brand(PaymentCardNetwork.VISA, 16..19)
        val mastercard = Brand(PaymentCardNetwork.MASTERCARD, 16..16)
        val maestro = Brand(PaymentCardNetwork.MAESTRO, 14..19)
        // Diners Club, JCB and Discover. An IMEI (15 digits, often starting 35) is none of them.
        val diners = Brand(PaymentCardNetwork.OTHER, 14..19)
        val others = Brand(PaymentCardNetwork.OTHER, 16..19)
        listOf(
            IssuerRange(34, 34, 2, amex), IssuerRange(37, 37, 2, amex),
            IssuerRange(4, 4, 1, visa),
            IssuerRange(51, 55, 2, mastercard), IssuerRange(2221, 2720, 4, mastercard),
            IssuerRange(50, 50, 2, maestro), IssuerRange(56, 69, 2, maestro),
            IssuerRange(300, 305, 3, diners), IssuerRange(36, 36, 2, diners),
            IssuerRange(3528, 3589, 4, others), IssuerRange(38, 39, 2, others),
        )
    }

    /**
     * The network a number belongs to by its first digits (the issuer ranges every network
     * publishes), with the lengths it uses.
     */
    fun brand(digits: String): Brand? = issuers.firstOrNull { it.covers(digits) }?.brand

    /** The Luhn check every card number carries in its last digit; twelve ASCII digits or more. */
    fun passesLuhn(digits: String): Boolean {
        if (digits.length < ANYWHERE_LEAST || digits.any { it !in '0'..'9' }) return false
        var sum = 0
        for ((offset, character) in digits.reversed().withIndex()) {
            val digit = character - '0'
            val doubled = if (offset % 2 == 0) digit else digit * 2
            sum += if (doubled > LARGEST_DIGIT) doubled - LARGEST_DIGIT else doubled
        }
        return sum % DECIMAL == 0
    }
}
