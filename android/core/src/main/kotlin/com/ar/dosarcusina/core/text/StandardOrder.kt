package com.ar.dosarcusina.core.text

import java.text.Collator
import java.util.Locale

/**
 * The order a person expects names in, as Finder and the iOS app sort them
 * (`String.localizedStandardCompare`): without case, numbers by their value ("Factura 2" before
 * "Factura 10"), spaces and punctuation before digits and digits before letters ("Factura și…"
 * before "Facturare"), letters as Romanian orders them (ă after a, ș after s, and ş with a cedilla
 * as ș, as the app folds it), and only when nothing else tells two apart, their case and then their
 * code points, so the order is always the same.
 *
 * In the app's locale, Romanian (`Locale.dosarDefault`), where iOS uses the phone's: two names
 * whose first difference is a letter with a mark ("ăb" and "ac") may sort the other way on an
 * iPhone set to another language.
 */
object StandardOrder : Comparator<String> {
    private val romanian: Locale = Locale.forLanguageTag("ro")

    private val withoutCase = ThreadLocal.withInitial { collator(Collator.SECONDARY) }
    private val withCase = ThreadLocal.withInitial { collator(Collator.TERTIARY) }

    private fun collator(strength: Int): Collator = Collator.getInstance(romanian).apply {
        this.strength = strength
        decomposition = Collator.CANONICAL_DECOMPOSITION
    }

    /** What a run of a name is, in the order the kinds sort in. */
    private enum class Kind { OTHER, DIGITS, LETTERS }

    private class Part(val kind: Kind, val text: String)

    override fun compare(a: String, b: String): Int {
        val left = commas(a)
        val right = commas(b)
        val byParts = compareParts(parts(left), parts(right))
        if (byParts != 0) return byParts
        val byCase = withCase.get().compare(left, right)
        return if (byCase != 0) byCase else a.compareTo(b)
    }

    private fun compareParts(left: List<Part>, right: List<Part>): Int {
        for (index in 0 until minOf(left.size, right.size)) {
            val order = compare(left[index], right[index])
            if (order != 0) return order
        }
        return left.size.compareTo(right.size)
    }

    private fun compare(a: Part, b: Part): Int = when {
        a.kind != b.kind -> a.kind.compareTo(b.kind)
        a.kind == Kind.DIGITS -> compareNumbers(a.text, b.text)
        a.kind == Kind.LETTERS -> withoutCase.get().compare(a.text, b.text)
        else -> a.text.compareTo(b.text)
    }

    /** Numbers by their value: leading zeros don't count, so "007" and "7" are equal here. */
    private fun compareNumbers(a: String, b: String): Int {
        val left = a.trimStart('0')
        val right = b.trimStart('0')
        return if (left.length != right.length) left.length.compareTo(right.length) else left.compareTo(right)
    }

    /** ş and ţ with a cedilla as the letters with a comma below, as the app's fold reads them. */
    private fun commas(text: String): String =
        text.replace('ş', 'ș').replace('ţ', 'ț').replace('Ş', 'Ș').replace('Ţ', 'Ț')

    /** Runs of letters (with their marks) and runs of ASCII digits, and every other character on its own. */
    private fun parts(text: String): List<Part> {
        val parts = mutableListOf<Part>()
        val current = StringBuilder()
        var kind: Kind? = null
        var at = 0
        while (at < text.length) {
            val codePoint = text.codePointAt(at)
            at += Character.charCount(codePoint)
            val next = kindOf(codePoint, kind)
            if (current.isNotEmpty() && (next != kind || next == Kind.OTHER)) {
                parts.add(Part(requireNotNull(kind), current.toString()))
                current.clear()
            }
            kind = next
            current.appendCodePoint(codePoint)
        }
        if (current.isNotEmpty()) parts.add(Part(requireNotNull(kind), current.toString()))
        return parts
    }

    private fun kindOf(codePoint: Int, previous: Kind?): Kind = when {
        codePoint in '0'.code..'9'.code -> Kind.DIGITS
        Character.isLetter(codePoint) -> Kind.LETTERS
        isMark(codePoint) && previous == Kind.LETTERS -> Kind.LETTERS
        else -> Kind.OTHER
    }

    private fun isMark(codePoint: Int): Boolean = when (Character.getType(codePoint)) {
        Character.NON_SPACING_MARK.toInt(), Character.COMBINING_SPACING_MARK.toInt() -> true
        else -> false
    }
}
