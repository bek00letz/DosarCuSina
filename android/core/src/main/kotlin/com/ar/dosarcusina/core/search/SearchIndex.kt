package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.text.StandardOrder

/**
 * An index over the whole binder, kept in memory, as the iOS app's `SearchIndex`
 * (ios/DosarCuSina/Services/Search/SearchEngine.swift), pinned by its answers in
 * shared/test-vectors/search/search-matching.json.
 *
 * Matching ignores case and diacritics ("polita" finds "poliță") and takes each query word as the
 * start of a word, so Romanian endings still match ("placut" finds "plăcuțe"); never the middle of
 * one ("achitat" doesn't find "neachitat"). Every query word must match. A word matched whole counts
 * three times its field's weight, one it starts twice; each query word counts its best field.
 * Results rank by score, then newer first, then by title as a person orders names ([StandardOrder]).
 *
 * [wording] says what a row already shows ([SearchWording.line]), so its preview never repeats it.
 */
class SearchIndex private constructor(private val wording: SearchWording, private val entries: List<Entry>) {
    private class Entry(
        val document: SearchDocument,
        /** Per field: its folded words. */
        val words: List<List<String>>,
        /** The folded words of the title and of the line under it, as the row shows them. */
        val shown: List<List<String>>,
    )

    constructor(documents: List<SearchDocument>, wording: SearchWording) :
        this(wording, documents.map { entry(it, wording) })

    /** How many documents it holds. */
    val count: Int get() = entries.size

    /** Every document in the index. */
    val documents: List<SearchDocument> get() = entries.map { it.document }

    /**
     * The same index with the documents of [removing] taken out, and [adding] put in (each replacing
     * any of the same id); only the new ones are prepared again.
     */
    fun updating(removing: Set<String>, adding: List<SearchDocument>): SearchIndex {
        val replaced = removing + adding.map { it.id }
        val kept = entries.filter { it.document.id !in replaced }
        return SearchIndex(wording, kept + adding.map { entry(it, wording) })
    }

    /** The documents [query] finds, best first, at most [limit], only of [kinds] when given. */
    fun search(query: String, limit: Int = DEFAULT_LIMIT, kinds: Set<SearchResultKind>? = null): List<SearchResult> {
        val tokens = SearchText.tokens(query)
        if (tokens.isEmpty()) return emptyList()
        val results = entries
            .filter { kinds == null || it.document.kind in kinds }
            .mapNotNull { score(it, tokens) }
        return results.sortedWith(ranking).take(limit)
    }

    private fun score(entry: Entry, tokens: List<String>): SearchResult? {
        val fieldPoints = IntArray(entry.words.size)
        var score = 0
        for (token in tokens) {
            var best = 0
            for ((index, words) in entry.words.withIndex()) {
                val points = points(token, words, entry.document.fields[index].weight)
                fieldPoints[index] = maxOf(fieldPoints[index], points)
                best = maxOf(best, points)
            }
            if (best == 0) return null
            score += best
        }
        return SearchResult(entry.document, score, snippet(entry, fieldPoints))
    }

    companion object {
        /** How many results a search gives when it doesn't say. */
        const val DEFAULT_LIMIT = 50

        private const val WHOLE_WORD = 3
        private const val START_OF_WORD = 2

        private fun entry(document: SearchDocument, wording: SearchWording) = Entry(
            document = document,
            words = document.fields.map { SearchText.tokens(it.text) },
            shown = listOf(document.title, wording.line(document.subtitle)).map(SearchText::tokens),
        )

        /** A query word's points in one field: three times its weight for a whole word, twice for one it starts. */
        private fun points(token: String, words: List<String>, weight: Int): Int {
            var points = 0
            for (word in words) {
                if (word == token) return weight * WHOLE_WORD
                if (SearchText.startsWith(word, token)) points = weight * START_OF_WORD
            }
            return points
        }

        private val ranking: Comparator<SearchResult> = compareByDescending<SearchResult> { it.score }
            .thenByDescending { it.document.date }
            .thenComparing({ it.document.title }, StandardOrder)

        /**
         * A result's preview line: the field that matched best among those that add something, for
         * every kind of result alike; on equal points, the one listed first. A field the row already
         * says, in its title or the line under it, is no preview, so nothing reads twice; when every
         * matching field is already said, there is none.
         */
        private fun snippet(entry: Entry, points: IntArray): String? {
            val candidates = points.indices.filter { points[it] > 0 }
                .sortedWith(compareByDescending<Int> { points[it] }.thenBy { it })
            return candidates.firstOrNull { index ->
                val words = entry.words[index]
                words.isNotEmpty() && entry.shown.none { says(it, words) }
            }?.let { entry.document.fields[it].text }
        }

        /** Whether [words] appear in [line] one after another, each whole. */
        private fun says(line: List<String>, words: List<String>): Boolean =
            words.size <= line.size && (0..line.size - words.size).any { start ->
                line.subList(start, start + words.size) == words
            }
    }
}
