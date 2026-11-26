package com.ar.dosarcusina.core.text

/**
 * A secret as the binder keeps it: sealed on the phone (an identity card's PIN, an alarm code), and
 * known by its own form whatever its field says, as the iOS app's `SecretSealer.prefix` and
 * `isSealed` (ios/DosarCuSina/Services/Security/SecretFields.swift). The one place the form is
 * written: what an archive carries (`SecretRules`) and what search keeps both read it. Sealing
 * itself comes with the locks (Phase 6).
 */
object SealedText {
    /** Marks sealed text, with the format's version. */
    const val PREFIX = "sealed:v1:"

    /** What a secret looks like wherever it isn't opened: the iOS app's `SecretFields.mask`. */
    const val MASK = "••••"

    /** Whether [text] is a sealed value. */
    fun isSealed(text: String): Boolean = text.startsWith(PREFIX)
}
