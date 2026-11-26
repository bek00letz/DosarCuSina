package com.ar.dosarcusina.store

import androidx.room3.withWriteTransaction
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.BinderDatabase
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.HistoryEntryProviders
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ProviderAssets
import com.ar.dosarcusina.store.schema.ServiceItem
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.util.UUID

/**
 * No link deletes what it points at, and a record goes with what it holds only through
 * [RecordContents]; what is left without what held it goes back to a copy of it by its id
 * ([ParentLinks.rehome]).
 */
class RecordContentsTest {
    private val database: BinderDatabase = scratchStore().database

    /** A car with a deadline, a reading, a visit with a part, a firm and a document with a page; and another car. */
    private class Household(
        val car: Asset,
        val other: Asset,
        val deadline: Obligation,
        val reading: MeasurementLog,
        val visit: HistoryEntry,
        val part: ServiceItem,
        val document: Attachment,
        val page: AttachmentPage,
        val firm: Provider,
    )

    private suspend fun household(): Household {
        val car = Asset(name = "VW Golf 2018", templateKey = "vehicle")
            .run { copy(pk = database.assets().insert(this)) }
        val other = Asset(name = "Dacia Logan 2015", templateKey = "vehicle")
            .run { copy(pk = database.assets().insert(this)) }
        val firm = Provider(name = "Service Auto S.R.L.").let { it.copy(pk = database.providers().insert(it)) }
        val deadline = Obligation(title = "ITP", asset = car.pk, assetID = car.id)
            .run { copy(pk = database.obligations().insert(this)) }
        val reading = MeasurementLog(name = "Kilometraj", asset = car.pk, assetID = car.id)
            .let { it.copy(pk = database.readings().insert(it)) }
        val visit = HistoryEntry(title = "Revizie", asset = car.pk, assetID = car.id, obligation = deadline.pk)
            .let { it.copy(pk = database.history().insert(it)) }
        val part = ServiceItem(name = "Filtru ulei", entry = visit.pk, entryID = visit.id, supplier = firm.pk)
            .let { it.copy(pk = database.items().insert(it)) }
        val document = Attachment(fileName = "factura.pdf", asset = car.pk, assetID = car.id, historyEntry = visit.pk)
            .let { it.copy(pk = database.attachments().insert(it)) }
        val page = AttachmentPage(attachment = document.pk, attachmentID = document.id)
            .let { it.copy(pk = database.pages().insert(it)) }
        database.providerAssets().insert(ProviderAssets(provider = firm.pk, asset = car.pk))
        database.entryProviders().insert(HistoryEntryProviders(historyEntry = visit.pk, provider = firm.pk))
        return Household(car, other, deadline, reading, visit, part, document, page, firm)
    }

    @Test
    fun deletingASectionTakesWhatItHoldsAndNothingElse() = runBlocking {
        val home = database.withWriteTransaction { household() }
        database.withWriteTransaction { RecordContents.delete(database, home.car) }
        assertEquals(listOf(home.other.pk), database.assets().all().map { it.pk })
        assertEquals(emptyList<Obligation>(), database.obligations().all())
        assertEquals(emptyList<MeasurementLog>(), database.readings().all())
        assertEquals(emptyList<HistoryEntry>(), database.history().all())
        assertEquals(emptyList<ServiceItem>(), database.items().all())
        assertEquals(emptyList<Attachment>(), database.attachments().all())
        assertEquals(emptyList<AttachmentPage>(), database.pages().all())
        assertEquals(listOf(home.firm.pk), database.providers().all().map { it.pk }, "The firm is the household's")
        assertEquals(emptyList<ProviderAssets>(), database.providerAssets().all())
        assertEquals(emptyList<HistoryEntryProviders>(), database.entryProviders().all())
    }

    @Test
    fun aRowDeletedAloneLetsGoOfItsLinksAndTakesNothing() = runBlocking {
        val home = database.withWriteTransaction { household() }
        database.withWriteTransaction { RecordContents.deleteRow(database, home.car) }
        val deadline = database.obligations().all().single()
        assertNull(deadline.asset, "The link let go")
        assertEquals(home.car.id, deadline.assetID, "The id of what held it stays")
        assertEquals(1, database.history().all().size)
        assertEquals(1, database.attachments().all().size)
        database.withWriteTransaction { RecordContents.deleteRow(database, home.firm) }
        assertNull(database.items().all().single().supplier)
        assertEquals(emptyList<HistoryEntryProviders>(), database.entryProviders().all())
    }

    @Test
    fun theDatabaseRefusesALinkToManyLeftPointingAtNothing() = runBlocking {
        val home = database.withWriteTransaction { household() }
        assertThrows<Exception> {
            runBlocking { database.withWriteTransaction { database.providers().delete(home.firm) } }
        }
        assertEquals(1, database.providers().all().size, "Nothing of the refused step stays")
    }

    @Test
    fun aRecordLeftWithoutWhatHeldItGoesBackToACopyWithItsId() = runBlocking {
        val home = database.withWriteTransaction { household() }
        database.withWriteTransaction { RecordContents.deleteRow(database, home.car) }
        // Another copy of the same car, as two copies joined on another device would leave it.
        val copy = Asset(id = home.car.id, name = "VW Golf 2018", templateKey = "vehicle")
            .run { copy(pk = database.assets().insert(this)) }
        val held = ParentLinks.Held(
            obligations = database.obligations().all(),
            attachments = database.attachments().all(),
            history = database.history().all(),
            readings = database.readings().all(),
            items = database.items().all(),
            pages = database.pages().all(),
        )
        val assets = database.assets().all()
        val back = ParentLinks.rehome(
            held,
            assets = { id -> assets.firstOrNull { it.id == id }?.pk },
            entries = { null },
            attachments = { null },
        )
        assertEquals(listOf(copy.pk), back.obligations.map { it.asset })
        assertEquals(listOf(copy.pk), back.readings.map { it.asset })
        assertEquals(listOf(copy.pk), back.history.map { it.asset })
        assertEquals(listOf(copy.pk), back.attachments.map { it.asset })
        assertTrue(back.items.isEmpty() && back.pages.isEmpty(), "What still has its holder isn't loose")
        val nothingHere = ParentLinks.rehome(held, assets = { null }, entries = { null }, attachments = { null })
        assertTrue(nothingHere.isEmpty, "Without a copy here, it waits for the repair list")
    }

    @Test
    fun stampingFollowsTheLink() {
        val section = UUID.fromString("00000000-0000-4000-8000-0000000000a1")
        val ids = ParentLinks.IdOfRow { row -> if (row == 7L) section else null }
        assertEquals(section, ParentLinks.stamp(Obligation(asset = 7), ids).assetID)
        assertNull(ParentLinks.stamp(Obligation(asset = null, assetID = section), ids).assetID, "No link: no holder")
        val same = Obligation(asset = 7, assetID = section)
        assertTrue(ParentLinks.stamp(same, ids) === same, "Nothing changes when the id already follows the link")
        assertEquals(section, ParentLinks.stamp(ServiceItem(entry = 7), ids).entryID)
        assertEquals(section, ParentLinks.stamp(AttachmentPage(attachment = 7), ids).attachmentID)
    }
}
