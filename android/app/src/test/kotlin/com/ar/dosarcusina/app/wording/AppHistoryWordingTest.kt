package com.ar.dosarcusina.app.wording

import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.wording.RomanianWords
import com.ar.dosarcusina.core.wording.WordBook
import com.ar.dosarcusina.store.history.EntryTitle
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** A record's title in Istoric says what the iOS app says (shared/test-vectors/history/titles.json). */
class AppHistoryWordingTest {
    /** The iOS app's words, as its HistoryVectorsTests wrote them. */
    private val ios: JsonObject by lazy {
        val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
        val cases = MachineText.parse(File(shared, "test-vectors/history/titles.json").readText())
            .jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
        cases.single { "words" in it }.getValue("words").jsonObject
    }

    @Test
    fun `every kind's title is the iOS app's`() {
        val named = mapOf(
            VisitKind.SERVICE to "service",
            VisitKind.JOB to "job",
            VisitKind.REPAIR to "repair",
            VisitKind.UPKEEP to "upkeep",
            VisitKind.DOCTOR to "doctor",
            VisitKind.VET to "vet",
        )
        for ((kind, key) in named) {
            assertEquals(ios.getValue(key).jsonPrimitive.content, AppHistoryWording.entryTitle(kind), key)
        }
        assertEquals(ios.getValue("visit").jsonPrimitive.content, AppHistoryWording.entryTitle(null))
    }

    @Test
    fun `a service of many jobs is counted as the iOS app counts it`() {
        for ((count, title) in ios.getValue("manyJobs").jsonObject) {
            assertEquals(title.jsonPrimitive.content, AppHistoryWording.manyJobs(count.toInt()))
        }
        assertEquals("Revizie: 20 de lucrări", AppHistoryWording.title(EntryTitle.ManyJobs(20)))
    }

    @Test
    fun `every title's key is in the iOS catalog`() {
        for (kind in VisitKind.entries) {
            assertTrue(RomanianWords.has(WordBook.APP, AppHistoryWording.key(kind)), kind.raw)
        }
        assertTrue(RomanianWords.has(WordBook.APP, AppHistoryWording.MANY_JOBS))
    }

    @Test
    fun `names done are the title, joined`() {
        val title = EntryTitle.Names(listOf("Ulei și filtru", "Plăcuțe frână față"))
        assertEquals("Ulei și filtru, Plăcuțe frână față", AppHistoryWording.title(title))
    }
}
