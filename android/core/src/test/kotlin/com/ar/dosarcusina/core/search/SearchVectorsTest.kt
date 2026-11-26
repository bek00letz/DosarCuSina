package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.text.Built
import com.ar.dosarcusina.core.text.PaymentCardNumbers
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.isNullOrMissing
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.time.Instant
import java.util.UUID

/**
 * Search's answers, in shared/test-vectors/search/, written by ios/DosarCuSinaTests/SearchVectorsTests.swift.
 * `search-records` is read by `:store`'s `SearchRecordsVectorsTest`, which fills the index from a Room binder.
 */
object SearchVectors : VectorFolder(
    folderName = "search",
    files = setOf("search-matching", "search-outside", "search-records", "search-redacting", "search-remember"),
    writtenBy = "the iOS SearchVectorsTests with TEST_RUNNER_SEARCH_VECTORS_WRITE=1",
)

/** The words of these tests: the matching cases' subtitles are plain text, as the row shows it. */
object PlainWording : SearchWording {
    override fun line(details: List<SearchDetail>): String = details.joinToString(" · ") {
        when (it) {
            is SearchDetail.Text -> it.text
            is SearchDetail.Day -> it.day.isoString
            is SearchDetail.Trades -> it.keys.joinToString(", ")
            SearchDetail.Archived -> "arhivat"
        }
    }

    override fun trade(key: String): String = key
}

class SearchVectorsTest {
    @Test
    fun `every file of answers is read by a test`() {
        val files = SearchVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
        assertEquals(SearchVectors.files, files.map { it.nameWithoutExtension }.toSet())
    }

    @TestFactory
    fun `the index matches and ranks as on the iPhone`(): List<DynamicTest> =
        SearchVectors.cases("search-matching").flatMap { group ->
            val index = SearchIndex(group.getValue("documents").jsonArray.map { document(it.jsonObject) }, PlainWording)
            group.getValue("queries").jsonArray.map { it.jsonObject }.map { query ->
                val name = "${group.text("name")}: “${query.text("query")}”"
                DynamicTest.dynamicTest(name) { checkQuery(index, query) }
            }
        }

    private fun checkQuery(index: SearchIndex, query: JsonObject) {
        val text = query.text("query")
        assertEquals(query.texts("tokens"), SearchText.tokens(text), "tokens")
        val kinds = query["kinds"].takeUnless { it.isNullOrMissing() }?.jsonArray
            ?.map { requireNotNull(SearchResultKind.of(it.jsonPrimitive.content)) }?.toSet()
        val limit = if (query["limit"].isNullOrMissing()) SearchIndex.DEFAULT_LIMIT else query.int("limit")
        val expected = query.getValue("results").jsonArray.map { it.jsonObject }.map {
            Triple(it.text("id"), it.int("score"), it.textOrNull("snippet"))
        }
        val actual = index.search(text, limit, kinds).map { Triple(it.id, it.score, it.snippet) }
        assertEquals(expected, actual)
    }

    @TestFactory
    fun `what search keeps is as on the iPhone`(): List<DynamicTest> =
        SearchVectors.tests("search-redacting", { label(it, "text") }) { case ->
            val text = Built.expand(case.text("text"))
            assertEquals(Built.expand(case.text("redacted")), SearchPrivacy.redacting(text, kept(case)), "redacted")
            assertEquals(case.bool("mayRemember"), SearchPrivacy.mayRemember(text), "mayRemember")
        }

    @TestFactory
    fun `what may be shown outside the app is as on the iPhone`(): List<DynamicTest> =
        SearchVectors.tests("search-outside", { label(it, "text", "isLocked", "appLockEnabled") }) { case ->
            when {
                "outside" in case -> {
                    val text = case.textOrNull("text")?.let(Built::expand)
                    val outside = SearchPrivacy.outsideText(text, case.texts("withheld"), kept(case))
                    assertEquals(case.textOrNull("outside")?.let(Built::expand), outside)
                }
                "mayShowOutside" in case -> assertEquals(
                    case.bool("mayShowOutside"),
                    SearchPrivacy.mayShowOutside(case.bool("isLocked"), case.bool("isExample")),
                )
                else -> assertEquals(
                    case.bool("outsideListsAnything"),
                    SearchPrivacy.outsideListsAnything(case.bool("appLockEnabled")),
                )
            }
        }

    @TestFactory
    fun `what is remembered is as on the iPhone`(): List<DynamicTest> =
        SearchVectors.tests("search-remember", { label(it, "query", "adding") }) { case ->
            if ("query" in case) {
                val results = case.getValue("foundLocked").jsonArray.mapIndexed { index, locked ->
                    val document = SearchDocument(
                        "r$index", SearchResultKind.DOCUMENT, "Rezultat", emptyList(), SearchRoute.Document(UUID(0, 0)),
                        emptyList(), isSensitive = locked.jsonPrimitive.content.toBooleanStrict(),
                    )
                    SearchResult(document, 1, null)
                }
                assertEquals(case.bool("mayRemember"), SearchPrivacy.mayRemember(case.text("query"), results))
            } else {
                val recent = RecentSearches.adding(case.text("adding"), case.texts("to"), case.int("limit"))
                assertEquals(case.texts("recent"), recent)
            }
        }

    private fun kept(case: JsonObject): PaymentCardNumbers.KeptWhole = PaymentCardNumbers.KeptWhole.typed(
        case.getValue("kept").jsonArray.map { it.jsonObject }.map {
            PaymentCardNumbers.TypedText(Built.expand(it.text("text")), it.text("type"))
        },
    )

    private fun document(json: JsonObject) = SearchDocument(
        id = json.text("id"),
        kind = requireNotNull(SearchResultKind.of(json.text("kind"))),
        title = json.text("title"),
        subtitle = listOfNotNull(json.textOrNull("subtitle")?.let(SearchDetail::Text)),
        route = SearchRoute.Document(UUID(0, 0)),
        fields = json.getValue("fields").jsonArray.map { it.jsonObject }.map {
            SearchField(it.text("text"), it.int("weight"))
        },
        date = json.textOrNull("date")?.let(Instant::parse),
        isSensitive = json.bool("isSensitive"),
    )
}
