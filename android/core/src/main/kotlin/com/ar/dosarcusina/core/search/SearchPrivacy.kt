package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.text.PaymentCardNumbers
import com.ar.dosarcusina.core.text.PaymentCardNumbers.KeptWhole
import com.ar.dosarcusina.core.text.SealedText
import com.ar.dosarcusina.core.text.TextPattern
import com.ar.dosarcusina.core.values.TextRules
import java.util.regex.Pattern

/**
 * What search may keep, decided once for the index and for the words this phone remembers, as the
 * iOS app's `SearchPrivacy` (ios/DosarCuSina/Services/Search/SearchPrivacy.swift), pinned by its
 * answers in shared/test-vectors/search/:
 * - a number shaped like a CNP (thirteen digits on their own) is never indexed or remembered,
 *   wherever it was typed or read, valid or misread;
 * - a card number ([PaymentCardNumbers]) is never indexed or remembered, even masked; what a
 *   section's own typed values keep whole (a pet's microchip) is searched as it is stored
 *   ([KeptWhole]), by the same rule the save uses;
 * - sealed text (a secret) is never indexed or remembered;
 * - the line a result shows under its title holds none of them either, while what is already masked
 *   shows as the record's page shows it ([shown]);
 * - words kept on this phone outside the binder (recent searches, a trip's plan) are kept only when
 *   [mayRemember] allows them, checked again when they are read back;
 * - a query that found anything in a locked section is never remembered;
 * - outside the app, nothing from a locked category or the examples, and only titles, without those
 *   numbers or the values a category keeps out of search ([mayShowOutside], [outsideText]).
 */
// Each rule of the iOS app's SearchPrivacy, and the few text helpers they share, side by side.
@Suppress("TooManyFunctions")
object SearchPrivacy {
    private const val CNP_DIGITS = 13
    private const val WITHHELD_SHORTEST = 4
    private const val WITHHELD_LONGEST = 64

    /** What a removed value leaves behind at either end: "Pașaport – " reads "Pașaport". */
    private const val DANGLING = "–—-·,:;/|#"

    /** What joins the parts of a result's line ("VW Golf · 3 martie"). */
    private const val MIDDLE_DOT = "·"

    /**
     * [text] with every CNP-shaped number, every card number and every sealed value taken out: what
     * can be matched. A card number is never searched, even by its last four digits, so a masked one
     * ("•••• 4821") goes too, and so does any mask. What the record's section keeps whole ([keeping])
     * stays, as it stays where it is stored. The same rule as [shown], with what is masked taken out
     * as well.
     */
    fun redacting(text: String, keeping: KeptWhole = KeptWhole.NOTHING): String {
        val characters = TextRules.characters(text)
        val worthLooking = characters.any(TextRules::isNumber) ||
            text.contains(SealedText.PREFIX) || text.contains(PaymentCardNumbers.MASK)
        if (!worthLooking) return text
        return takingOut(characters, keeping, masked = true)
    }

    /**
     * A line a result shows (the one under its title, for every kind of result), as it may be shown:
     * every CNP-shaped number and sealed value taken out and a card number masked, by the same rule
     * as [redacting], while what is already masked stays as the record's page shows it (a secret's
     * "••••", a card's "•••• 4821"): the line is shown, never matched. A line with nothing taken out is
     * left exactly as it was; one with something taken out loses the spaces and the dots ("·") it
     * leaves behind.
     */
    fun shown(text: String, keeping: KeptWhole = KeptWhole.NOTHING): String {
        val characters = TextRules.characters(text)
        if (characters.none(TextRules::isNumber) && !text.contains(SealedText.PREFIX)) return text
        val result = takingOut(characters, keeping, masked = false)
        if (result == text) return text
        return TextRules.trimming(words(result).joinToString(" ")) {
            TextRules.isWhitespace(it) || Character.toString(it) == MIDDLE_DOT
        }
    }

    /**
     * The one rule behind [redacting] and [shown]: CNP-shaped numbers out, card numbers masked
     * ([PaymentCardNumbers], keeping what the section keeps whole), sealed values out, and with
     * [masked], what is masked out too.
     */
    private fun takingOut(characters: List<String>, keeping: KeptWhole, masked: Boolean): String {
        var result = PaymentCardNumbers.redact(withoutCnpShaped(characters), keeping = keeping)
        if (masked) result = removing(PaymentCardNumbers.MASKED_PATTERN, result)
        if (result.contains(SealedText.PREFIX)) {
            result = piecesKeepingEmpty(result).filterNot(SealedText::isSealed).joinToString(" ")
        }
        return result
    }

    /**
     * Whether words the person typed may be kept on this phone outside the binder (the recent
     * searches, a trip's plan): only when they hold nothing search never keeps. The one rule for
     * what is remembered, used when it is kept and again when it is read back, so what an earlier
     * version kept goes too.
     */
    fun mayRemember(text: String): Boolean = redacting(text) == text

    /** Whether a search may be kept among the recent ones: its words may be remembered, and it found nothing locked. */
    fun mayRemember(query: String, results: List<SearchResult>): Boolean =
        mayRemember(query) && results.none { it.document.isSensitive }

    // Outside the app

    /**
     * Whether anything of the binder may be listed outside the app at all: nothing while the whole
     * app is locked.
     */
    fun outsideListsAnything(appLockEnabled: Boolean): Boolean = !appLockEnabled

    /**
     * Whether a record may be shown outside the app. Stricter than Caută, where a locked section still
     * shows its title: outside the app a locked category shows nothing at all, whether or not it is
     * open now, and examples never leave the app.
     */
    fun mayShowOutside(isLocked: Boolean, isExample: Boolean): Boolean = !isLocked && !isExample

    /**
     * A title or a short line as it may be shown outside the app: without any CNP-shaped number, any
     * sealed value, or any of [withholding] (the values its category keeps out of search, such as a
     * document number), written with or without separators; what its section keeps whole
     * ([keeping]) stays, as in the app. Null when nothing worth showing is left.
     */
    fun outsideText(
        text: String?,
        withholding: List<String> = emptyList(),
        keeping: KeptWhole = KeptWhole.NOTHING,
    ): String? {
        if (text == null) return null
        var result = redacting(text, keeping)
        for (value in withholding) {
            val pattern = withheldPattern(value) ?: continue
            result = replacing(pattern, result, " ", caseInsensitive = true)
        }
        result = words(result).joinToString(" ")
        result = TextRules.trimming(result) { TextRules.isWhitespace(it) || DANGLING.contains(Character.toString(it)) }
        val worthShowing = TextRules.characters(result).any { TextRules.isLetter(it) || TextRules.isNumber(it) }
        return result.takeIf { worthShowing }
    }

    /**
     * The values a section's category keeps out of search (document numbers, CNPs, medical notes,
     * codes: a field that is sensitive or secret) and its sensitive or secret rows, as stored and as
     * shown: what [outsideText] withholds from its titles.
     */
    fun withheldValues(section: SearchSection): List<String> =
        section.values.filterNot { it.isIndexable }.flatMap { listOfNotNull(it.text, it.shown) } +
            section.facts.filter { it.isSensitive || it.isSecret }.map { it.value }

    /**
     * The value's letters and digits in order, with anything but a letter or a digit allowed between
     * them, so "RX 123456", "RX-123456" and "rx123456" are one value. Null for a value too short to
     * stand for anything or too long to sit in a title.
     */
    private fun withheldPattern(value: String): String? {
        val characters = TextRules.characters(value).filter { TextRules.isLetter(it) || TextRules.isNumber(it) }
        if (characters.size !in WITHHELD_SHORTEST..WITHHELD_LONGEST) return null
        return characters.joinToString("""[^\p{L}\p{N}]*""") { Pattern.quote(it) }
    }

    /** [characters] without the runs of exactly thirteen ASCII digits that aren't part of a longer number. */
    private fun withoutCnpShaped(characters: List<String>): String {
        val kept = StringBuilder()
        val run = StringBuilder()
        var count = 0
        fun endRun() {
            if (count != CNP_DIGITS) kept.append(run)
            run.clear()
            count = 0
        }
        for (character in characters) {
            if (character.length == 1 && character[0] in '0'..'9') {
                run.append(character)
                count += 1
            } else {
                endRun()
                kept.append(character)
            }
        }
        endRun()
        return kept.toString()
    }

    /** [text] split at every space, empty pieces kept (Swift's `split(separator:omittingEmptySubsequences: false)`). */
    private fun piecesKeepingEmpty(text: String): List<String> {
        val pieces = mutableListOf<String>()
        val current = StringBuilder()
        for (character in TextRules.characters(text)) {
            if (character == " ") {
                pieces.add(current.toString())
                current.clear()
            } else {
                current.append(character)
            }
        }
        pieces.add(current.toString())
        return pieces
    }

    /** The pieces of [text] between whitespace (Swift's `split(whereSeparator: \.isWhitespace)`). */
    private fun words(text: String): List<String> {
        val pieces = mutableListOf<String>()
        val current = StringBuilder()
        for (character in TextRules.characters(text)) {
            if (TextRules.isWhitespaceOrNewline(character.codePointAt(0))) {
                if (current.isNotEmpty()) pieces.add(current.toString())
                current.clear()
            } else {
                current.append(character)
            }
        }
        if (current.isNotEmpty()) pieces.add(current.toString())
        return pieces
    }

    private fun removing(pattern: String, text: String): String = replacing(pattern, text, "", caseInsensitive = false)

    /** [text] with every match of [pattern] replaced by [with], as Foundation's `replacingOccurrences`. */
    private fun replacing(pattern: String, text: String, with: String, caseInsensitive: Boolean): String {
        val matches = TextPattern.matches(pattern, text, caseInsensitive)
        if (matches.isEmpty()) return text
        val result = StringBuilder()
        var rest = 0
        for (match in matches) {
            result.append(text, rest, match.range.first).append(with)
            rest = match.range.last + 1
        }
        return result.append(text, rest, text.length).toString()
    }
}
