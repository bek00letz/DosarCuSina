package com.ar.dosarcusina.store.search

import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.search.SearchDetail
import com.ar.dosarcusina.store.RecordRef
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Caută's index is read in full once, then a save reads again only what it touched, as on the iPhone. */
class SearchIndexerTest {
    private object Words : BinderSearchWording {
        override fun shown(value: FieldValue, field: FieldDefinition): String = value.textValue ?: value.toString()

        override fun trade(key: String): String = key

        override fun line(details: List<SearchDetail>): String = details.joinToString(" · ") {
            when (it) {
                is SearchDetail.Text -> it.text
                is SearchDetail.Day -> it.day.isoString
                is SearchDetail.Trades -> it.keys.joinToString(", ")
                SearchDetail.Archived -> "arhivat"
            }
        }
    }

    private val binder = TestBinderStore()
    private val indexer = SearchIndexer(binder.store, binder.locks, Words, zone = { bucharest })

    private fun <R : Any> insert(record: R): R = binder.unit.perform { it.insert(record) }

    private fun line(index: com.ar.dosarcusina.core.search.SearchIndex, query: String): String =
        Words.line(index.search(query).first().document.subtitle)

    @Test
    fun `a save reads only what it touched`() = runBlocking {
        insert(CategoryTemplate(key = "search.car", name = "Mașini"))
        val car = insert(Asset(name = "VW Golf", templateKey = "search.car"))
        val other = insert(Asset(name = "Dacia Logan", templateKey = "search.car"))
        insert(Obligation(title = "Rovinietă", dueDayISO = "2027-01-10", asset = other.pk))

        val first = indexer.rebuild()
        val everything = indexer.lastRecordsRead
        assertTrue(first.search("golf").any { it.document.title == "VW Golf" })

        // A new deadline: only it is read.
        val itp = insert(Obligation(title = "Inspecția tehnică", dueDayISO = "2027-03-01", asset = car.pk))
        var index = indexer.apply(SearchChanges(changed = setOf(RecordRef.of(itp))))
        assertEquals(1, indexer.lastRecordsRead)
        assertEquals("VW Golf · 2027-03-01", line(index, "inspectia"))

        // A rename: the car and what shows its name, never the other car's records.
        binder.unit.perform { it.update(binder.stored(car).copy(name = "Golf de familie")) }
        index = indexer.apply(SearchChanges(changed = setOf(RecordRef.of(car))))
        assertTrue(indexer.lastRecordsRead < everything)
        assertEquals("Golf de familie · 2027-03-01", line(index, "inspectia"))
        assertEquals("Dacia Logan · 2027-01-10", line(index, "rovinieta"))

        // A deletion takes its documents out, and the index matches a full read.
        val ref = RecordRef.of(itp)
        binder.unit.perform { it.delete(binder.stored(itp)) }
        index = indexer.apply(SearchChanges(deleted = setOf(ref)))
        assertTrue(index.search("inspectia").isEmpty())
        assertEquals(SearchIndexer(binder.store, binder.locks, Words).rebuild().count, index.count)
    }

    @Test
    fun `a lock chosen on this phone is read again by every entry`() = runBlocking {
        insert(CategoryTemplate(key = "search.papers", name = "Acte"))
        insert(Asset(name = "Pașaport", templateKey = "search.papers"))
        assertFalse(indexer.current().search("pasaport").single().document.isSensitive)
        binder.store.locks.set(true, "search.papers", binder.now)
        assertTrue(indexer.apply(SearchChanges(everything = true)).search("pasaport").single().document.isSensitive)
    }

    @Test
    fun `a section whose category hasn't arrived is locked, and so are its records`() = runBlocking {
        val stray = insert(Asset(name = "Secțiune", templateKey = "search.absent"))
        insert(Obligation(title = "Termen", dueDayISO = "2027-02-02", asset = stray.pk))
        val index = indexer.current()
        assertTrue(index.search("sectiune").single { it.document.title == "Secțiune" }.document.isSensitive)
        assertTrue(index.search("termen").single().document.isSensitive)
    }
}
