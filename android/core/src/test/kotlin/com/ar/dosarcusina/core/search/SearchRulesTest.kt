package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.text.PaymentCardNumbers.KeptWhole
import com.ar.dosarcusina.core.text.StandardOrder
import com.ar.dosarcusina.core.values.CalendarDay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** The rules of Caută that have no answer of the iPhone's to compare with: what a row shows, and the parts read. */
class SearchRulesTest {
    private val zone = ZoneId.of("Europe/Bucharest")
    private val entries = SearchEntries(PlainWording, zone)
    private val passport = UUID(0, 3)

    private fun deadline(isLocked: Boolean) = SearchDeadline(
        id = UUID(0, 23), title = "Reînnoire pașaport", reference = null, provider = null, notes = "la ghișeu",
        dueDay = CalendarDay(2028, 5, 5), sectionName = null, isLocked = isLocked, keptWhole = KeptWhole.NOTHING,
    )

    private fun found(isLocked: Boolean): SearchResult =
        SearchIndex(listOf(entries.deadline(deadline(isLocked))), PlainWording).search("ghiseu").single()

    @Test
    fun `a locked section's result shows its title and that it is locked, and nothing else`() {
        val result = found(isLocked = true)
        assertEquals("la ghișeu", result.snippet, "The index keeps what matched; the row decides what it shows")
        val row = SearchRows.row(result, sessionIsOpen = false)
        assertEquals("Reînnoire pașaport", row.title)
        assertTrue(row.line.isEmpty())
        assertNull(row.preview)
        assertEquals(SearchRowNote.UNLOCK_TO_SEE_MORE, row.note)
        assertTrue(row.opensBehindTheLock)
    }

    @Test
    fun `with the unlock session open, a locked section's result shows everything`() {
        val row = SearchRows.row(found(isLocked = true), sessionIsOpen = true)
        assertEquals("la ghișeu", row.preview)
        assertNull(row.note)
        assertFalse(row.opensBehindTheLock)
    }

    @Test
    fun `an open result shows its line and its preview`() {
        val row = SearchRows.row(found(isLocked = false), sessionIsOpen = false)
        assertEquals(listOf(SearchDetail.Day(CalendarDay(2028, 5, 5))), row.line)
        assertEquals("la ghișeu", row.preview)
        assertFalse(row.opensBehindTheLock)
    }

    @Test
    fun `a search that found something locked is never remembered`() {
        val found = SearchIndex(listOf(entries.deadline(deadline(isLocked = true))), PlainWording).search("pasaport")
        assertNull(RecentSearches.afterSearching("pasaport", found, listOf("golf")))
        assertEquals(listOf("golf"), RecentSearches.remembered(listOf("golf", "4111 1111 1111 1111", "1800101990006")))
    }

    @Test
    fun `each part followed gives one result, at its newest occurrence`() {
        fun part(key: String?, day: String, brand: String) = SearchPart(
            componentKey = key, name = "Plăcuțe", entryId = UUID(1, day.hashCode().toLong()),
            occurredAt = Instant.parse("${day}T10:00:00Z"), partBrandOrCode = brand, supplierName = null,
            providerNames = emptyList(),
        )
        val parts = listOf(
            part("brakes", "2025-10-10", "ATE"),
            part("brakes", "2026-03-03", "Bosch"),
            part(null, "2026-05-05", "—"),
        )
        val last = SearchEntries.lastOccurrences(parts)
        assertEquals(listOf("Bosch"), last.map { it.partBrandOrCode })
    }

    @Test
    fun `a section's records are searched with its name and its lock`() {
        val section = SearchSection(
            id = passport, name = "Pașaport Ana", categoryName = "Acte",
            values = listOf(
                SearchValue(
                    "Număr", "text", "documentNumber", isSensitive = true, text = "RX 123456", shown = "RX 123456",
                ),
            ),
            facts = emptyList(), notes = null, updatedAt = null, isLocked = true, keptWhole = KeptWhole.NOTHING,
        )
        val document = entries.section(section).single()
        assertTrue(document.isSensitive)
        assertFalse(document.fields.any { "123456" in it.text }, "A document number is never searched")
        assertEquals(listOf("RX 123456"), SearchPrivacy.withheldValues(section).distinct())
        val withheld = SearchPrivacy.withheldValues(section)
        assertEquals("Pașaport", SearchPrivacy.outsideText("Pașaport – RX 123456", withheld))
    }

    @Test
    fun `names are ordered as a person expects`() {
        val names = listOf(
            "Factura 10", "factura 2", "Factura 1b", "Factura Beta", "factura alfa", "Șofer", "Sofa", "Tabără",
        )
        assertEquals(
            listOf(
                "Factura 1b", "factura 2", "Factura 10", "factura alfa", "Factura Beta", "Sofa", "Șofer", "Tabără",
            ),
            names.sortedWith(StandardOrder),
        )
        assertTrue(StandardOrder.compare("golf", "Golf") != 0, "Names that differ only in case still have one order")
    }
}
