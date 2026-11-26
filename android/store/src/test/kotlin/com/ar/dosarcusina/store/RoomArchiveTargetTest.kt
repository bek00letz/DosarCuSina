package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.ArchiveImportMode
import com.ar.dosarcusina.archive.DossierArchiveService
import com.ar.dosarcusina.archive.DossierArchiveWriter
import com.ar.dosarcusina.archive.MemoryByteSink
import com.ar.dosarcusina.archive.MemoryByteSource
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.binder.Removed
import com.ar.dosarcusina.archive.fixtureArchive
import com.ar.dosarcusina.archive.moment
import com.ar.dosarcusina.archive.sha256
import com.ar.dosarcusina.archive.unpackArchive
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.locks.confirmed
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.IOException
import java.time.Clock
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

/** What the Room store does as the archive's target, beyond what the importer's own tests check on it. */
class RoomArchiveTargetTest {
    @TempDir
    lateinit var staging: File

    private val bucharest: ZoneId = ZoneId.of("Europe/Bucharest")
    private val clock: Clock = Clock.fixed(moment("2026-11-26T10:00:00Z"), ZoneOffset.UTC)

    private fun import(binder: RoomTestBinder, mode: ArchiveImportMode = ArchiveImportMode.REPLACE) {
        DossierArchiveService(binder, Catalog.builtIn, clock = clock, zone = { bucharest })
            .importArchive(MemoryByteSource(fixtureArchive("dosar-v3/household")), mode = mode, staging = staging)
    }

    private fun household(): RoomTestBinder = RoomTestBinder(Binder()).also { import(it) }

    @Test
    fun writingOverARecordKeepsWhatABackupDoesNotCarry() {
        val binder = household()
        val database = binder.store.database
        val locked = moment("2026-11-20T08:00:00Z")
        val copy = UUID.fromString("00000000-0000-4000-8000-0000000000c1")
        val asset = runBlocking { database.assets().all().first().copy(copyID = copy) }
        val document = runBlocking { database.attachments().all().first().copy(documentID = "capture-document-1") }
        val template = runBlocking { database.templates().all().first().copy(lockedEverywhereAt = locked) }
        val page = runBlocking { database.pages().all().first() }
        runBlocking {
            database.assets().update(asset)
            database.attachments().update(document)
            database.templates().update(template)
        }
        for (mode in ArchiveImportMode.entries) {
            import(binder, mode)
            runBlocking {
                val keptAsset = database.assets().all().single { it.pk == asset.pk }
                assertEquals(asset, keptAsset, "$mode keeps the row and its copy")
                val keptDocument = database.attachments().all().single { it.pk == document.pk }
                assertEquals(document, keptDocument, "$mode keeps the capture's document")
                val kept = database.templates().all().single { it.pk == template.pk }
                assertEquals(locked, kept.lockedEverywhereAt, "$mode keeps when it was locked anywhere")
                val keptPage = database.pages().all().single { it.pk == page.pk }
                assertEquals(page, keptPage, "$mode keeps each page the page it was")
            }
        }
    }

    @Test
    fun everyHeldRecordKeepsTheIdOfWhatHoldsIt() {
        val binder = household()
        runBlocking {
            val database = binder.store.database
            val assets = database.assets().all().associate { it.pk to it.id }
            val obligations = database.obligations().all()
            assertTrue(obligations.any { it.asset != null })
            for (record in obligations) assertEquals(record.asset?.let(assets::get), record.assetID)
            for (record in database.history().all()) assertEquals(record.asset?.let(assets::get), record.assetID)
            for (record in database.attachments().all()) assertEquals(record.asset?.let(assets::get), record.assetID)
            for (record in database.readings().all()) assertEquals(record.asset?.let(assets::get), record.assetID)
            val entries = database.history().all().associate { it.pk to it.id }
            for (record in database.items().all()) assertEquals(record.entry?.let(entries::get), record.entryID)
            val documents = database.attachments().all().associate { it.pk to it.id }
            val pages = database.pages().all()
            assertTrue(pages.isNotEmpty())
            for (record in pages) assertEquals(record.attachment?.let(documents::get), record.attachmentID)
        }
    }

    @Test
    fun aBackupLeavesOutWhatStaysOnThePhone() {
        val binder = household()
        val database = binder.store.database
        val documentID = "capture-document-2"
        val contact = "contact-card-3"
        runBlocking {
            for (row in database.obligations().all()) {
                database.obligations().update(row.copy(cycleKnownAt = moment("2026-11-21T08:00:00Z")))
            }
            for (row in database.attachments().all()) {
                val compacted = moment("2026-11-22T08:00:00Z")
                database.attachments().update(row.copy(documentID = documentID, compactedAt = compacted))
            }
            for (row in database.providers().all()) database.providers().update(row.copy(contactIdentifier = contact))
            for (row in database.templates().all()) {
                database.templates().update(row.copy(lockedEverywhereAt = moment("2026-11-23T08:00:00Z")))
            }
        }
        val sink = MemoryByteSink()
        DossierArchiveWriter("1.0", moment("2026-11-26T10:00:00Z"), bucharest).write(binder.snapshot(), sink)
        val data = unpackArchive(sink.data).filter { it.path.startsWith("data/") }
            .joinToString("\n") { it.data.decodeToString() }
        // Every record's id goes into a backup but a page's, which is named only by its document.
        for (name in StayOnThePhone.properties.values.flatten().toSet() - "id") {
            assertFalse("\"$name\"" in data, "$name stays on the phone")
        }
        val pages = runBlocking { database.pages().all().map { it.id.toString() } }
        val moments = listOf("2026-11-21T08:00:00Z", "2026-11-22T08:00:00Z", "2026-11-23T08:00:00Z")
        for (value in listOf(documentID, contact) + moments + pages) {
            assertFalse(value in data, "$value stays on the phone")
        }
    }

    @Test
    fun aFailedImportLeavesNoFileAndNoLockBehind() {
        val binder = RoomTestBinder(Binder())
        binder.failsNextWrite = true
        assertThrows<IllegalStateException> { import(binder) }
        assertEquals(emptyList<String>(), binder.store.files.folder.list().orEmpty().toList(), "Its files went")
        assertEquals(emptyMap<String, Boolean>(), binder.sectionLocks.all)
        assertEquals(Binder(), binder.snapshot())
        // This phone's locks can't be written: their folder takes no new file.
        assertTrue(binder.lockFolder.setWritable(false))
        try {
            assertThrows<IOException> { import(binder) }
        } finally {
            binder.lockFolder.setWritable(true)
        }
        assertEquals(Binder(), binder.snapshot(), "Locks that can't be kept keep nothing of the import")
        assertEquals(emptyMap<String, Boolean>(), binder.sectionLocks.all)
    }

    @Test
    fun anImportLocksWhatItRaisesEverywhereAndNeverOpens() {
        val binder = household()
        val database = binder.store.database
        val vehicle = runBlocking { database.templates().all().single { it.key == "vehicle" } }
        assertEquals(false, binder.snapshot().locks["vehicle"])
        assertEquals(null, vehicle.lockedEverywhereAt)
        assertEquals(true, binder.snapshot().locks["documents"], "Locked as the catalog says")

        // A backup that locks the cars.
        val locked = binder.snapshot().let { it.copy(templates = it.templates.filter { t -> t.key == "vehicle" }) }
        binder.apply(BinderChanges(locked, Removed(), mapOf("vehicle" to true, "documents" to false)))
        val raised = runBlocking { database.templates().all().single { it.key == "vehicle" } }
        assertEquals(true, binder.snapshot().locks["vehicle"])
        assertTrue(raised.lockedEverywhereAt != null, "Raised by a backup, the lock travels as one made here")
        assertEquals(vehicle.updatedAt, raised.updatedAt, "It gives no change time")
        assertEquals(true, binder.snapshot().locks["documents"], "Never opened by an import")
        assertEquals(true, binder.sectionLocks.lockedHere("documents")?.locked, "Its choice stays as it was")
        val custom = binder.snapshot().templates.first { !it.isBuiltIn }.key
        assertEquals(false, binder.snapshot().locks[custom])
        assertEquals(null, binder.sectionLocks.lockedHere(custom), "An open category needs no choice")

        // Raised again: nothing more changes.
        binder.apply(BinderChanges(locked, Removed(), mapOf("vehicle" to true)))
        val again = runBlocking { database.templates().all().single { it.key == "vehicle" } }
        assertEquals(raised.lockedEverywhereAt, again.lockedEverywhereAt)
    }

    @Test
    fun aBackupMayLockACategoryHereButNeverOpenOne() {
        val source = household()
        val at = clock.instant()
        runBlocking {
            for (row in source.store.database.templates().all()) {
                val saved = when (row.key) {
                    "vehicle" -> source.locks.setLock(row, locked = true, lowering = null, now = at)
                    "documents" -> source.locks.setLock(row, locked = false, lowering = confirmed(), now = at)
                    else -> row
                }
                if (saved != row) source.store.database.templates().update(saved)
            }
        }
        assertEquals(false, source.snapshot().locks["documents"])
        val sink = MemoryByteSink()
        DossierArchiveWriter("1.0", clock.instant(), bucharest).write(source.snapshot(), sink)

        for (mode in ArchiveImportMode.entries) {
            val here = RoomTestBinder(Binder())
            DossierArchiveService(here, Catalog.builtIn, clock = clock, zone = { bucharest })
                .importArchive(MemoryByteSource(sink.data), mode = mode, staging = staging)
            assertEquals(true, here.snapshot().locks["vehicle"], "$mode: locked in the backup, locked here too")
            assertEquals(true, here.snapshot().locks["documents"], "$mode: open in the backup, still locked here")
        }
    }

    @Test
    fun aCategoryAnImportTakesOutKeepsThisPhonesLock() {
        val binder = household()
        val custom = runBlocking { binder.store.database.templates().all().first { !it.isBuiltIn } }
        binder.apply(BinderChanges(Binder(), Removed(), mapOf(custom.key to true)))
        binder.apply(BinderChanges(Binder(), Removed(templates = setOf(custom.key)), emptyMap()))
        assertEquals(true, binder.sectionLocks.lockedHere(custom.key)?.locked, "Locked if it ever comes back")
    }

    @Test
    fun filesAreKeptOnceAndGoWhenNothingNamesThem() {
        val binder = household()
        val named = runBlocking { binder.store.database.files().named().toSet() }
        assertTrue(named.isNotEmpty())
        assertEquals(named, binder.store.files.folder.list().orEmpty().toSet(), "Each file once, under its digest")
        for (digest in named) {
            assertEquals(digest, sha256(binder.store.files.file(digest).open().use { it.readAllBytes() }))
        }
        val everything = binder.snapshot()
        val removed = Removed(
            templates = everything.templates.map { it.key }.toSet(),
            assets = everything.assets.map { it.id }.toSet(),
            obligations = everything.obligations.map { it.id }.toSet(),
            historyEntries = everything.historyEntries.map { it.id }.toSet(),
            serviceItems = everything.serviceItems.map { it.id }.toSet(),
            providers = everything.providers.map { it.id }.toSet(),
            measurements = everything.measurements.map { it.id }.toSet(),
            attachments = everything.attachments.map { it.id }.toSet(),
            issuerLessons = everything.issuerLessons.map { it.id }.toSet(),
        )
        binder.apply(BinderChanges(Binder(), removed, emptyMap()))
        assertEquals(Binder(), binder.snapshot())
        assertEquals(emptyList<String>(), binder.store.files.folder.list().orEmpty().toList(), "No file nothing names")
    }
}
