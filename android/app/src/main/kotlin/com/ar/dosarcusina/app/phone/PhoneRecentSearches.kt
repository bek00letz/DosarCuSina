package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.core.search.RecentSearches
import com.ar.dosarcusina.core.search.SearchPrivacy
import com.ar.dosarcusina.core.search.SearchResult
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.JsonElement

/**
 * The last few searches on this phone, newest first, under the iOS app's key: the list's rules are
 * core's ([RecentSearches]), and they remember only what search may keep ([SearchPrivacy.mayRemember]),
 * checked when a search is added and again when the list is read back, so one kept that search may
 * not keep goes, from the list and from the file.
 */
class PhoneRecentSearches(private val preferences: PhonePreferences) {
    /** The list as it may be shown. */
    val items: List<String> get() = shown(preferences[KEY])

    /** The list as it changes: what Caută observes. */
    val changes: Flow<List<String>> get() = preferences.values.map { shown(it[KEY]) }.distinctUntilChanged()

    /** Remembers [query] at the top, unless what it found must not be remembered. */
    fun add(query: String, results: List<SearchResult>) {
        RecentSearches.afterSearching(query, results, items)?.let(::keep)
    }

    /** Forgets one search. */
    fun remove(query: String) = keep(items.filter { it != query })

    /** Forgets every search. */
    fun clear() {
        preferences[KEY] = null
    }

    private fun keep(items: List<String>) {
        preferences[KEY] = PhoneJson.list(items)
    }

    /** What is kept that may be shown; what may not is forgotten as it is read. */
    private fun shown(kept: JsonElement?): List<String> {
        val stored = PhoneJson.strings(kept)
        val remembered = RecentSearches.remembered(stored)
        if (remembered != stored) keep(remembered)
        return remembered
    }

    companion object {
        /** The iOS app's key. */
        const val KEY = "search.recent"
    }
}
