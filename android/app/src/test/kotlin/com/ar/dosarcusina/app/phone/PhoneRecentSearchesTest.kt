package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.app.graph.PhoneLog
import com.ar.dosarcusina.core.search.SearchDocument
import com.ar.dosarcusina.core.search.SearchResult
import com.ar.dosarcusina.core.search.SearchResultKind
import com.ar.dosarcusina.core.search.SearchRoute
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.UUID

/** The recent searches on this phone remember only what search may keep, when added and when read back. */
class PhoneRecentSearchesTest {
    @TempDir
    lateinit var root: File

    private val file by lazy { File(root, "preferences.json") }

    private fun searches() = PhoneRecentSearches(PhonePreferences(file, { it.run() }, PhoneLog {}))

    private fun found(isSensitive: Boolean) = SearchResult(
        SearchDocument(
            id = "asset:1",
            kind = SearchResultKind.ASSET,
            title = "VW Golf 2018",
            subtitle = emptyList(),
            route = SearchRoute.Section(UUID.fromString("0a6f2f0e-6f39-4a39-9b0a-6c1b1f3a0001")),
            fields = emptyList(),
            isSensitive = isSensitive,
        ),
        score = 1,
        snippet = null,
    )

    @Test
    fun `the newest search comes first, kept once, and is there the next time`() {
        val searches = searches()
        searches.add("golf", listOf(found(false)))
        searches.add("ITP", emptyList())
        searches.add("Golf ", emptyList())
        assertEquals(listOf("Golf", "ITP"), searches().items)
    }

    @Test
    fun `a search that found something locked, or holds a CNP, is never kept`() {
        val searches = searches()
        searches.add("pașaport", listOf(found(true)))
        searches.add("1800101990006", emptyList())
        assertEquals(emptyList<String>(), searches().items)
        assertFalse(file.exists() && file.readText().contains("1800101990006"))
    }

    @Test
    fun `one kept that search may not keep goes as the list is read`() {
        file.writeText("""{"search.recent":["ITP","4111 1111 1111 1111"]}""")
        assertEquals(listOf("ITP"), searches().items)
        assertFalse(file.readText().contains("4111"))
    }

    @Test
    fun `a search can be forgotten, and all of them`() {
        val searches = searches()
        searches.add("ITP", emptyList())
        searches.add("RCA", emptyList())
        searches.remove("ITP")
        assertEquals(listOf("RCA"), searches().items)
        searches.clear()
        assertEquals(emptyList<String>(), searches().items)
    }
}
