package com.ar.dosarcusina.core.text

import com.ar.dosarcusina.core.text.DigitGroups.DATE_GROUPS
import com.ar.dosarcusina.core.text.DigitGroups.Gap
import com.ar.dosarcusina.core.text.DigitGroups.overlaps
import com.ar.dosarcusina.core.values.TextRules

/**
 * How [PaymentCardNumbers] finds card numbers in text, as the iOS app's rule does
 * (ios/Shared/CardNumberRule.swift, "Runs of digits" and "Brands"): runs of digits of any script
 * with at most one space or dash between them, the parts of a longer run that are printed like a
 * card, groups apart by anything else (a dot, a slash, several spaces) printed like a card with
 * one kind of gap, what of a run belongs to an IBAN or a code, the networks' issuer ranges and the
 * Luhn check.
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

    /** A run of digits found in a text, or a part of one: its groups, the pieces between its gaps. */
    class Run(private val text: String, val groups: List<IntRange>, val isWhole: Boolean) {
        val range: IntRange = groups.first().first..groups.last().last
        private val pieces = groups.map { group ->
            buildString {
                text.substring(group).codePoints().forEach { codePoint -> DigitGroups.digit(codePoint)?.let(::append) }
            }
        }

        /** The run's digits as ASCII digits, whatever script they are written in. */
        val digits: String = pieces.joinToString("")
        val groupSizes: List<Int> = pieces.map { it.length }

        /** What stands between each group and the next. */
        val gaps: List<Gap> = groups.zipWithNext { left, right -> Gap(text.substring(left.last + 1, right.first)) }

        /** Some of its groups are apart by something else than one space or one dash. */
        val isApartByOthers: Boolean
            get() = gaps.any { !it.isNarrow }

        /**
         * Its stretches of groups apart by one space or one dash only, in order, each taken as a
         * whole run: the run itself when nothing else stands between its groups. A date in it
         * ([isDate]) is a stretch of its own, so its year never starts a card printed after it.
         */
        fun stretches(): List<Run> {
            val dates = (0..groups.size - DATE_GROUPS).filter(::isDate)
            val insideDates = dates.flatMap { listOf(it, it + 1) }.toSet()
            val dateEdges = dates.flatMap { listOf(it - 1, it + DATE_GROUPS - 1) }.filter { it in gaps.indices }
            val ends = (gaps.indices.filter { !gaps[it].isNarrow && it !in insideDates } + dateEdges).toSortedSet()
            if (ends.isEmpty()) return listOf(this)
            val stretches = mutableListOf<Run>()
            var start = 0
            for (index in ends) {
                stretches.add(Run(text, groups.subList(start, index + 1), isWhole = true))
                start = index + 1
            }
            stretches.add(Run(text, groups.subList(start, groups.size), isWhole = true))
            return stretches
        }

        /**
         * Whether the three groups from [start] are a date: a day, a month and a year of four digits
         * ("01.02.2026", "2/1/2026", "2026-02-01"), apart twice by the same dot, slash or dash. A
         * card never prints groups that short, so a date is never part of one.
         */
        private fun isDate(start: Int): Boolean {
            val kind = gaps[start].kind
            if (kind != gaps[start + 1].kind || kind == Gap.Kind.SPACE) return false
            val values = pieces.subList(start, start + DATE_GROUPS).map { it.toIntOrNull() ?: 0 }
            return DigitGroups.isDate(groupSizes.subList(start, start + DATE_GROUPS), values)
        }

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
         * printed like a card, since inside a long number printed in fours every part is. Groups
         * apart by anything else (dots, slashes, several spaces, which dates, amounts and a table's
         * columns give too) count only with one kind of gap throughout, printed like a card and
         * passing the check.
         */
        val isCardNumber: Boolean
            get() {
                val brand = brand(digits)
                if (digits.length !in cardLengths || brand == null || digits.length !in brand.lengths) return false
                if (isApartByOthers) {
                    return gaps.all { it.kind == gaps.first().kind } && printedLikeACard && passesLuhn(digits)
                }
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
     * Runs of digits, of any script, whose groups are apart by what [DigitGroups.GAP] allows, not part of a
     * longer run, with [least] digits or more.
     */
    private fun spans(text: String, least: Int): List<Run> {
        val pattern = """\d(?:${DigitGroups.GAP}?\d){${least - 1},}(?!${DigitGroups.GAP}?\d)"""
        return TextPattern.matches(pattern, text, caseInsensitive = false).map { match ->
            Run(text, DigitGroups.groups(text, match.range), isWhole = true)
        }
    }

    /**
     * Runs of digits with at most one space or dash between them, not part of a longer run:
     * twelve digits or more, or ([strict]) eight or more. On a bank card ([strict]), where a longer
     * run's groups are apart by anything else (dots, slashes, several spaces), the card numbers the
     * "anywhere" rule finds in it are runs, and so is what is left of it beside them, with eight
     * digits or more.
     */
    fun runs(text: String, strict: Boolean): List<Run> {
        val least = if (strict) STRICT_LEAST else ANYWHERE_LEAST
        val characters by lazy { Characters(text) }
        val ibans by lazy { if (hasLetter(text)) IBAN.ranges(text) else emptyList() }
        return spans(text, least).flatMap { span ->
            val stretches = span.stretches()
            if (!strict || !span.isApartByOthers) return@flatMap stretches.filter { it.digits.length >= least }
            val cards = cardNumbers(span, text, characters, ibans)
            val found = cards.toMutableList()
            val rest = mutableListOf<IntRange>()
            fun keepRest() {
                if (rest.isNotEmpty()) {
                    val run = Run(text, rest.toList(), isWhole = true)
                    if (run.digits.length >= least) found.add(run)
                }
                rest.clear()
            }
            val inACard = { group: IntRange -> cards.any { overlaps(it.range, group) } }
            for (stretch in stretches) {
                if (stretch.digits.length >= least && stretch.groups.none(inACard)) {
                    keepRest()
                    found.add(stretch)
                    continue
                }
                for (group in stretch.groups) if (inACard(group)) keepRest() else rest.add(group)
            }
            keepRest()
            found.sortedBy { it.range.first }
        }
    }

    /** The card numbers in the text by the "anywhere" rule, in order (the [cardNumbers] of each run). */
    fun cardNumbers(text: String): List<Run> {
        val characters = Characters(text)
        val ibans = if (hasLetter(text)) IBAN.ranges(text) else emptyList()
        return spans(text, ANYWHERE_LEAST).flatMap { cardNumbers(it, text, characters, ibans) }
    }

    /**
     * The card numbers in one run of the text ([spans]) by the "anywhere" rule, in order: in each of
     * its stretches apart by one space or dash, a whole stretch that is one, else the parts of a
     * longer one that are ([parts]), looked for only in what of it isn't a code ([pieces]); then,
     * where something else stands between groups (dots, slashes, several spaces), the card numbers
     * printed that way.
     */
    private fun cardNumbers(span: Run, text: String, characters: Characters, ibans: List<IntRange>): List<Run> {
        fun cards(run: Run, accepts: (Run) -> Boolean): List<Run> =
            pieces(run, text, characters, ibans).flatMap { piece ->
                if (accepts(piece)) listOf(piece) else parts(piece, text, accepts)
            }
        val found = span.stretches()
            .filter { it.digits.length >= ANYWHERE_LEAST }
            .flatMap { cards(it, Run::isCardNumber) }
        if (!span.isApartByOthers) return found
        val apart = cards(span) { it.isApartByOthers && it.isCardNumber }
            .filter { card -> found.none { overlaps(it.range, card.range) } }
        return (found + apart).sortedBy { it.range.first }
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
     * then the run, each apart by spaces or by one dash, dot or slash ("RO49 AAAA 1234 5678 9012
     * 3456", "RO49.AAAA.1234.5678…").
     */
    private fun continuesAnIBAN(run: Run, characters: Characters): Boolean {
        val last = characters.before(run.range.first)
        if (last == null || last.length != 1 || !DigitGroups.isGapCharacter(last[0])) return false
        val before = characters.suffix(run.range.first, IBAN_HEAD_REACH)
        val apart = """(?:[-./]|[\t\p{Zs}]++)"""
        val head = """(?<![\p{L}\p{N}])([A-Z]{2})\d{2}(?:$apart[A-Z0-9]{4})*$apart$"""
        val country = TextPattern.first(head, before, caseInsensitive = false)?.get(1) ?: return false
        return IBAN.lengths[country] != null
    }

    /**
     * The card numbers inside a run that isn't one as a whole: a card number printed next to other
     * digits ("12 4111 1111 1111 1111", "4111-1111-1111-1111-27"). Only parts that begin and end
     * where the run's groups do are tried, from the left and the longest first at each place; a
     * part is taken when [accepts] takes it (a card number). Digits with nothing between them stay
     * one number. In a run printed all in groups of four, a part is tried only at its start or
     * right after a card found there: never the middle or the end of a long number (a 20-digit
     * health card number).
     */
    private fun parts(run: Run, text: String, accepts: (Run) -> Boolean): List<Run> {
        val sizes = run.groupSizes
        if (sizes.size < 2) return emptyList()
        val startOnly = sizes.all { it == GROUP }
        val found = mutableListOf<Run>()
        var start = 0
        while (start < sizes.size) {
            val part = ends(sizes, start).asReversed().asSequence()
                .map { end -> Run(text, run.groups.subList(start, end + 1), isWhole = false) }
                .firstOrNull(accepts)
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
