package com.ar.dosarcusina.core.text

import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.TextRules
import kotlinx.serialization.json.JsonElement

/**
 * A bank card's full number never stays in the binder: not in what a document's text keeps,
 * not in a field, a row under Date importante, a note or any other words a record keeps, not in
 * search, backups, logs or the share inbox. Only the last four digits are kept. One set of rules,
 * the iOS app's `PaymentCardNumbers` (ios/Shared/CardNumberRule.swift, the text rule, and
 * ios/DosarCuSina/Services/Security/PaymentCardNumbers.swift, what a field's type says about its
 * values), pinned by its answers in shared/test-vectors/text/.
 *
 * Two rules, by how sure the app is that the text is a card:
 * - **Anywhere:** a run of 14 to 19 digits (spaces or dashes between groups allowed) that starts
 *   like a card number and passes the Luhn check, or is printed in groups of four. Thirteen
 *   digits are never taken, so a CNP stays as it is. A card number printed next to other digits,
 *   with only a space or a dash between them, is found inside the longer run: a part of it that
 *   begins and ends where its groups do, is printed like a card and passes the Luhn check. Digits
 *   with nothing between them are one number and are only ever taken whole. Never a card: digits
 *   glued to a letter, groups that carry on an IBAN printed in groups, any part of an IBAN that
 *   passes its own check ([IBAN.ranges]), a field's value whose type names what it is and whose
 *   own check it passes ([keepsWhole]), and, in the words a section keeps, the same digits as one
 *   of its own values kept that way ([KeptWhole]).
 * - **On a bank card** (`strict`): any run of eight digits or more, whatever it starts with or
 *   whether its check digit passes. Nothing is kept whole there.
 *
 * A number taken out is written as its last four digits after a mask: "•••• 4821".
 */
object PaymentCardNumbers {
    /** What stands for the digits taken out. */
    const val MASK = "••••"

    /** A masked number with its last four digits ("•••• 4821"), for taking it out whole. */
    const val MASKED_PATTERN = """(?:••••[ -]?)+\d{0,4}"""

    /** The field of a bank card's last four digits, the one that keeps only them (`DocumentFields.cardLastFour`). */
    const val CARD_LAST_FOUR_KEY = "document.cardLastFour"

    /** The field types whose own check tells their value apart from a card number, as `FieldType`'s raw values. */
    val typesKeptWhole: Set<String> = setOf(FieldTypes.IBAN, FieldTypes.MICROCHIP)

    private const val LAST = 4
    private const val STRICT_LAST_FOUR_LEAST = 12
    private const val MICROCHIP_DIGITS = 15
    private const val MASKED_LAST_FOUR = """[•*xX]{4}[ -]?(?:[•*xX]{4}[ -]?){0,3}(\d{4})(?!\d)"""

    /** The field types this rule names, as stored. */
    object FieldTypes {
        const val IBAN = "iban"
        const val MICROCHIP = "microchip"
    }

    /**
     * The digits of a section's own values that its field types tell apart from a card number (a
     * pet's microchip in its microchip field, passing that field's check), which stay whole
     * wherever the same section's words hold them: its notes, its rows, its visits, the text read
     * off its documents. Made only from a value and its field's type ([typed], [of]), never from
     * the digits alone: a 15-digit chip starting 642 and a 15-digit Maestro card can be the same
     * digits, and only the field says which it is.
     */
    class KeptWhole private constructor(private val digits: Set<String>) {
        val isEmpty: Boolean get() = digits.isEmpty()

        /** Whether a run found in the text is one of these values, whole. */
        internal fun keeps(run: CardNumberRuns.Run): Boolean = run.digits in digits

        override fun equals(other: Any?): Boolean = other is KeptWhole && other.digits == digits

        override fun hashCode(): Int = digits.hashCode()

        companion object {
            /** Nothing kept whole: every card-shaped run is masked. */
            val NOTHING = KeptWhole(emptySet())

            /** What values with their fields' types keep whole: each its type keeps whole, digits alone. */
            fun typed(values: List<TypedText>): KeptWhole = KeptWhole(
                values.mapNotNullTo(mutableSetOf()) { value ->
                    val separatorsOnly = TextRules.characters(value.text).all { it in DIGITS_AND_SEPARATORS }
                    if (!keepsWhole(value.text, value.type) || !separatorsOnly) return@mapNotNullTo null
                    value.text.filter { it in '0'..'9' }.ifEmpty { null }
                },
            )

            /**
             * What a section keeps whole: its text values by key (all of them, sealed ones too),
             * through its category's fields (key and type, in order). Nothing without them.
             */
            fun of(texts: Map<String, String>, fields: List<TypedField>): KeptWhole =
                typed(fields.mapNotNull { field -> texts[field.key]?.let { TypedText(it, field.type) } })

            private val DIGITS_AND_SEPARATORS = ('0'..'9').map(Char::toString).toSet() + setOf(" ", "-")
        }
    }

    /** A value with its field's type, as `FieldType`'s raw value. */
    data class TypedText(val text: String, val type: String)

    /** A field's key and its type, as `FieldType`'s raw value. */
    data class TypedField(val key: String, val type: String)

    /**
     * The text with every card number in it masked, keeping only the last four digits. A run that
     * is one of [keeping] (a section's own typed values) stays whole, except on a bank card ([strict]).
     */
    fun redact(text: String, strict: Boolean = false, keeping: KeptWhole = KeptWhole.NOTHING): String {
        if (!hasNumber(text)) return text
        val found = if (strict) {
            CardNumberRuns.runs(text, strict = true)
        } else {
            CardNumberRuns.cardNumbers(text).filter { !keeping.keeps(it) }
        }
        val result = StringBuilder(text)
        for (run in found.asReversed()) result.replace(run.range.first, run.range.last + 1, run.masked)
        return result.toString()
    }

    /**
     * Whether the text holds something shaped like a card number (the "anywhere" rule), leaving out
     * a run that is one of [keeping].
     */
    fun containsCardNumber(text: String, keeping: KeptWhole = KeptWhole.NOTHING): Boolean =
        hasNumber(text) && CardNumberRuns.cardNumbers(text).any { !keeping.keeps(it) }

    /**
     * The last four digits of the card number in the text: a full number by the "anywhere" rule
     * (or, [strict], any run of twelve digits or more), else one already masked ("•••• 4821").
     */
    fun lastFour(text: String, strict: Boolean = false): String? {
        val run = CardNumberRuns.cardNumbers(text).firstOrNull()
            ?: if (strict) {
                CardNumberRuns.runs(text, strict = true).firstOrNull { it.digits.length >= STRICT_LAST_FOUR_LEAST }
            } else {
                null
            }
        if (run != null) return run.digits.takeLast(LAST)
        return TextPattern.first(MASKED_LAST_FOUR, text, caseInsensitive = false)?.get(1)
    }

    /**
     * Only the last four digits of what was typed or read: "4821" from "4821", from "•••• 4821" or
     * from a whole number pasted by mistake. Null when it has fewer.
     */
    fun lastFourOf(value: String): String? {
        // ASCII digits each standing alone as a character: a digit with a mark on it is another character.
        val digits = TextRules.characters(value).filter { it.length == 1 && it[0] in '0'..'9' }.joinToString("")
        return if (digits.length >= LAST) digits.takeLast(LAST) else null
    }

    /** The network a card number's first digits name, as a [PaymentCardNetwork] key. */
    fun network(digits: String): String? = CardNumberRuns.brand(digits)?.network

    /**
     * Whether a field's value is kept whole, never masked: its type names what it is
     * ([typesKeptWhole]) and it passes that type's own check (the field rules' check for an IBAN
     * and a microchip, `FieldFormatter.validate` on iOS).
     */
    fun keepsWhole(text: String, type: String?): Boolean {
        if (type == null || type !in typesKeptWhole) return false
        val trimmed = TextRules.trimming(text, TextRules::isWhitespaceOrNewline)
        if (trimmed.isEmpty()) return false
        return when (type) {
            FieldTypes.MICROCHIP -> TextRules.characters(trimmed).count(TextRules::isNumber) == MICROCHIP_DIGITS
            else -> IBAN.isValid(RomanianText.compact(trimmed))
        }
    }

    /**
     * The rule `sanitizing` lays on a section's text values (the iOS app's
     * `PaymentCardNumbers.sanitizing(_:fields:)`): every text masked by the anywhere rule, a bank
     * card's last digits ([CARD_LAST_FOUR_KEY]) cut to four, a sealed secret left alone, a value
     * whose field's type keeps it whole ([keepsWhole]) as typed, and so the same digits in another
     * of the values ([KeptWhole]): a note that repeats the microchip. [fields] (key and type, in
     * the category's order) is read only when something would be masked. Returns what changes:
     * each key's new text, or null where the value goes. The values that aren't text, and what a
     * newer build wrote (masked with [redacting]), are the caller's: it holds the stored form.
     */
    fun sanitizing(
        texts: Map<String, String>,
        fields: () -> List<TypedField>,
        isSealed: (String) -> Boolean,
    ): Map<String, String?> {
        val read by lazy {
            val all = fields()
            all.reversed().associate { it.key to it.type } to KeptWhole.of(texts, all)
        }
        val changes = mutableMapOf<String, String?>()
        for ((key, text) in texts.filterValues { !isSealed(it) }) {
            when {
                key == CARD_LAST_FOUR_KEY -> lastFourOf(text).let { if (it != text) changes[key] = it }
                redact(text) == text -> Unit
                else -> {
                    val (types, kept) = read
                    val masked = redact(text, keeping = kept)
                    if (!keepsWhole(text, types[key]) && masked != text) changes[key] = masked
                }
            }
        }
        return changes
    }

    /** Raw JSON a newer build wrote, with any card number in its strings masked; sealed codes ([isSealed]) stay. */
    fun redacting(raw: JsonElement, isSealed: (String) -> Boolean): JsonElement =
        JsonTrees.mappingStrings(raw) { if (isSealed(it)) it else redact(it) }

    /** Whether any character is a number, as Swift's `contains(where: \.isNumber)`. */
    private fun hasNumber(text: String): Boolean =
        text.codePoints().anyMatch(::isNumberCodePoint) && TextRules.characters(text).any(TextRules::isNumber)

    private fun isNumberCodePoint(codePoint: Int): Boolean = when (Character.getType(codePoint)) {
        Character.DECIMAL_DIGIT_NUMBER.toInt(), Character.LETTER_NUMBER.toInt(), Character.OTHER_NUMBER.toInt() -> true
        else -> false
    }
}

/** The card networks a bank card can be on, kept as stable keys (`document.cardNetwork`). */
object PaymentCardNetwork {
    const val VISA = "cardNetwork.visa"
    const val MASTERCARD = "cardNetwork.mastercard"
    const val MAESTRO = "cardNetwork.maestro"
    const val AMEX = "cardNetwork.amex"
    const val OTHER = "cardNetwork.other"

    val all: List<String> = listOf(VISA, MASTERCARD, MAESTRO, AMEX, OTHER)
}
