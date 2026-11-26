package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.values.CalendarDay
import java.time.Instant
import java.util.UUID

/** What a search result points at, as the iOS app's `SearchResultKind`, by its raw value. */
enum class SearchResultKind(val raw: String) {
    ASSET("asset"),
    OBLIGATION("obligation"),
    HISTORY_ENTRY("historyEntry"),
    COMPONENT("component"),
    PROVIDER("provider"),
    DOCUMENT("document"),
    ;

    companion object {
        fun of(raw: String): SearchResultKind? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Where a result opens: the part of the iOS app's `AppRoute` search uses, which the app's routes
 * take on (Phase 4). A part done on a section opens the record of history it was last done in.
 */
sealed interface SearchRoute {
    val id: UUID

    data class Section(override val id: UUID) : SearchRoute

    data class Deadline(override val id: UUID) : SearchRoute

    data class HistoryEntry(override val id: UUID) : SearchRoute

    data class Provider(override val id: UUID) : SearchRoute

    data class Document(override val id: UUID) : SearchRoute
}

/**
 * One piece of the line under a result's title ("VW Golf · 3 martie 2027"): what the records say,
 * and the fixed words as kinds, never as text, so the app says them in its own words ([SearchWording]).
 */
sealed interface SearchDetail {
    /** Words of the binder's: a section's name, its category's, the values its row shows. */
    data class Text(val text: String) : SearchDetail

    /** A day: a deadline's, or the one a record of history happened on. */
    data class Day(val day: CalendarDay) : SearchDetail

    /** A firm's trades, by key (`ProviderTrade`), said as one list. */
    data class Trades(val keys: List<String>) : SearchDetail

    /** The document is archived (the iOS app's „arhivat”). */
    data object Archived : SearchDetail
}

/**
 * The app's words for what a result shows: the seam to the wording (Phase 4), the iOS app's
 * `DosarFormat.day`, `ProviderTrade.title`, its list format and „arhivat”. The index reads it to
 * know what a row already says ([SearchIndex]); the row draws with it, so both read the same words.
 */
interface SearchWording {
    /** The line under a result's title, as the row shows it: [details] in order, "VW Golf · 3 martie 2027". */
    fun line(details: List<SearchDetail>): String

    /** A firm's trade by its key, as the app names it ("Mecanic"); a key the app doesn't know, as written. */
    fun trade(key: String): String
}

/** A piece of searchable text and how much a match in it counts, as the iOS app's `SearchField`. */
data class SearchField(val text: String, val weight: Int) {
    companion object {
        /** A field of [text], or of no words when there is none, as the iOS app's `SearchField(nil, …)`. */
        fun of(text: String?, weight: Int): SearchField = SearchField(text.orEmpty(), weight)
    }

    /** The weights, as the iOS app's `SearchField.Weight`. */
    object Weight {
        const val TITLE = 10

        /** Identifiers, document numbers, key facts, policy numbers. */
        const val IDENTIFIER = 8
        const val LABEL = 6
        const val VALUE = 4
        const val NOTE = 3

        /** Text read from scanned documents. */
        const val EXTRACTED = 1
    }
}

/**
 * One thing that can be found, as the iOS app's `SearchDocument`: its title, the line under it
 * ([subtitle], empty for none), where it opens, what it is found by, and whether it is in a
 * category locked on this phone ([isSensitive]): Caută then shows its title only, and opening it
 * asks for the lock ([SearchRows]).
 */
data class SearchDocument(
    val id: String,
    val kind: SearchResultKind,
    val title: String,
    val subtitle: List<SearchDetail>,
    val route: SearchRoute,
    val fields: List<SearchField>,
    /** Newer things rank slightly higher among equal matches. */
    val date: Instant? = null,
    val isSensitive: Boolean = false,
)

/** A document found, with its score and the text that matched best, for a one-line preview. */
data class SearchResult(val document: SearchDocument, val score: Int, val snippet: String?) {
    val id: String get() = document.id
}
