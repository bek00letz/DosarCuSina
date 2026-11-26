package com.ar.dosarcusina.core.text

import java.util.concurrent.ConcurrentHashMap
import java.util.regex.Pattern

/**
 * The regular expressions the text rules are written in, as the iOS app's `TextPattern`
 * (ios/Shared/TextPattern.swift) runs them through `NSRegularExpression`, which is ICU's: `\d`,
 * `\w`, `\s` and `\b` are Unicode's (a digit of any script is a digit), and a case-insensitive
 * pattern folds case by Unicode's rules. Java's patterns read the same with
 * [Pattern.UNICODE_CHARACTER_CLASS], which every pattern here is compiled with, so a rule ported
 * from Swift keeps its pattern as written. Ranges are in UTF-16 code units, as `NSRange`'s.
 */
object TextPattern {
    /** One match: its groups (the whole match first, null for a group that took no part) and where it is. */
    class Match internal constructor(val groups: List<String?>, val range: IntRange) {
        operator fun get(index: Int): String? = groups.getOrNull(index)
    }

    private val compiled = ConcurrentHashMap<Pair<String, Boolean>, Pattern>()

    /** Every match of [pattern] in [text], in order. A pattern that doesn't compile is a mistake in code: it throws. */
    fun matches(pattern: String, text: String, caseInsensitive: Boolean = true): List<Match> {
        val matcher = compile(pattern, caseInsensitive).matcher(text)
        val found = mutableListOf<Match>()
        while (matcher.find()) {
            val groups = (0..matcher.groupCount()).map { matcher.group(it) }
            found.add(Match(groups, matcher.start() until matcher.end()))
        }
        return found
    }

    fun first(pattern: String, text: String, caseInsensitive: Boolean = true): Match? =
        matches(pattern, text, caseInsensitive).firstOrNull()

    private fun compile(pattern: String, caseInsensitive: Boolean): Pattern =
        compiled.getOrPut(pattern to caseInsensitive) {
            val flags = Pattern.UNICODE_CHARACTER_CLASS or (if (caseInsensitive) Pattern.CASE_INSENSITIVE else 0)
            Pattern.compile(pattern, flags)
        }
}
