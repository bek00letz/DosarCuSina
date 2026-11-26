package com.ar.dosarcusina.core.text

import kotlinx.serialization.json.JsonElement

/**
 * The text rule the unit of work masks a record's words with as it saves, as the iOS app's
 * `FreeTextProperty` (ios/DosarCuSina/Services/Persistence/FreeText.swift): a bank card's full
 * number is never kept in the binder, whoever wrote it and from wherever. Each function answers
 * what one kind of stored property becomes, or null when nothing in it is masked, so the record is
 * written again only when something was.
 *
 * Which properties of which records are words (`freeText`) and which never are (`machineText`) is
 * the store's, and running this on every record a save touches is the unit of work's; both come
 * with them. A section's values go through [PaymentCardNumbers.sanitizing], its rows under Date
 * importante through [PaymentCardNumbers.redact] on each row's label and value (a secret row's
 * sealed value left alone), each keeping what the section keeps whole.
 */
object FreeTextMasking {
    /**
     * Plain text, masked by the "anywhere" rule; what the record's section keeps whole
     * ([keptWhole], read only when something would be masked) stays. Null when it holds no card
     * number, or only ones its section keeps whole.
     */
    fun masked(text: String, keptWhole: () -> PaymentCardNumbers.KeptWhole): String? {
        if (PaymentCardNumbers.redact(text) == text) return null
        val masked = PaymentCardNumbers.redact(text, keeping = keptWhole())
        return masked.takeIf { it != text }
    }

    /** A list of words (a firm's trades, free text allowed), each masked as [masked]; null when none is. */
    fun masked(texts: List<String>, keptWhole: () -> PaymentCardNumbers.KeptWhole): List<String>? {
        val masked = texts.map { masked(it, keptWhole) ?: it }
        return masked.takeIf { it != texts }
    }

    /**
     * JSON with words inside (a category of one's own: its fields' names, choices and defaults,
     * its deadlines' titles): every string in it, sealed codes ([isSealed]) left alone. Null when
     * nothing was masked, so the bytes of everything else never change.
     */
    fun masked(raw: JsonElement, isSealed: (String) -> Boolean): JsonElement? {
        val masked = PaymentCardNumbers.redacting(raw, isSealed)
        return masked.takeIf { it != raw }
    }
}
