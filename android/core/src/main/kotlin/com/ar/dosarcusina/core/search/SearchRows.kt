package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.values.TextRules

/** A fixed word a row of Caută says, as a kind: the app says it in its own words (Phase 4). */
enum class SearchRowNote {
    /** Under a result in a locked section: „Deblochează secțiunea ca să vezi mai mult.”, with a lock. */
    UNLOCK_TO_SEE_MORE,
}

/**
 * What one row of Caută shows of a result, as the iOS app's `SearchResultRow`
 * (ios/DosarCuSina/Views/Search/SearchScreen.swift).
 */
data class SearchRow(
    /** Always the title: Caută is the one place a locked section's records keep it. */
    val title: String,
    /** The line under it; empty for none, and always for a locked result. */
    val line: List<SearchDetail>,
    /** The text that matched best, when it adds something; never for a locked result. */
    val preview: String?,
    /** What it says in place of the line and the preview. */
    val note: SearchRowNote?,
    /** Whether opening it asks for the lock first. */
    val opensBehindTheLock: Boolean,
)

/** How Caută shows a result, by the one rule for a locked section's records. */
object SearchRows {
    /**
     * The row for [result]: a result in a locked category, while this phone's unlock session isn't
     * open ([sessionIsOpen]), shows its title and that it is locked, and nothing else; opening it
     * asks for the lock. Any other result shows its title, its line and its preview.
     */
    fun row(result: SearchResult, sessionIsOpen: Boolean): SearchRow {
        val locked = result.document.isSensitive && !sessionIsOpen
        return if (locked) {
            val note = SearchRowNote.UNLOCK_TO_SEE_MORE
            SearchRow(result.document.title, emptyList(), null, note, opensBehindTheLock = true)
        } else {
            SearchRow(result.document.title, result.document.subtitle, result.snippet, null, opensBehindTheLock = false)
        }
    }
}

/**
 * The last few searches, kept on this phone only, newest first, as the iOS app's `RecentSearches`
 * (ios/DosarCuSina/Views/Search/SearchSupport.swift): only what search may keep
 * ([SearchPrivacy.mayRemember]), checked when a search is added and when the list is read back.
 * Where the list is stored is the app's (Phase 4).
 */
object RecentSearches {
    /** How many are kept. */
    const val LIMIT = 8

    /** The list as read back: what an earlier version kept that search may not keep goes. */
    fun remembered(stored: List<String>): List<String> = stored.filter(SearchPrivacy::mayRemember)

    /**
     * The list after a search, unless what it found must not be remembered ([SearchPrivacy.mayRemember]):
     * null when it isn't kept.
     */
    fun afterSearching(query: String, results: List<SearchResult>, items: List<String>): List<String>? =
        if (SearchPrivacy.mayRemember(query, results)) adding(query, items) else null

    /**
     * The list after adding [query] at the top, trimmed; the same search in another case or without
     * diacritics counts as the one already there, which moves up. Nothing changes for an empty one.
     */
    fun adding(query: String, to: List<String>, limit: Int = LIMIT): List<String> {
        val trimmed = TextRules.trimming(query, TextRules::isWhitespaceOrNewline)
        if (trimmed.isEmpty()) return to
        val key = SearchText.normalize(trimmed)
        return (listOf(trimmed) + to.filter { SearchText.normalize(it) != key }).take(limit)
    }
}
