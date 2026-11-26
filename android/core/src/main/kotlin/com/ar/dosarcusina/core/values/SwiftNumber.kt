package com.ar.dosarcusina.core.values

/** How Swift writes a number where the iOS app builds text from one. */
object SwiftNumber {
    /**
     * A Double as Swift's `description` writes it, which the iOS app puts in ids it builds from a value
     * (a repair finding's `…:457.0`): as [MachineText.number] writes it, with `.0` after a whole number.
     */
    fun description(value: Double): String {
        if (value.isNaN()) return "nan"
        if (value.isInfinite()) return if (value > 0) "inf" else "-inf"
        val text = DoubleText.write(value)
        return if ('.' in text || 'e' in text) text else "$text.0"
    }
}
