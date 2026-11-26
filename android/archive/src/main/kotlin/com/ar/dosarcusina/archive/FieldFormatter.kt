package com.ar.dosarcusina.archive

/**
 * Typed text cleaned into its stored form, as the iOS app's `FieldFormatter.normalize(_:as:)`
 * (ios/DosarCuSina/Models/Fields/FieldFormatting.swift): the parts the store and the importer need
 * so far, a phone number and an e-mail address. The rest of the field types come with the forms
 * (Phase 4), here, never beside it.
 */
object FieldFormatter {
    /** A phone number as stored: its digits, a leading `+` kept, a leading `00` read as `+`. */
    fun normalizePhone(raw: String): String {
        val trimmed = raw.trim()
        val hasPlus = trimmed.startsWith("+")
        val digits = trimmed.filter(Char::isDigit)
        if (!hasPlus && digits.startsWith("00")) return "+" + digits.drop(2)
        return (if (hasPlus) "+" else "") + digits
    }

    /** An e-mail address as stored: trimmed, in lower case. */
    fun normalizeEmail(raw: String): String = raw.trim().lowercase()
}
