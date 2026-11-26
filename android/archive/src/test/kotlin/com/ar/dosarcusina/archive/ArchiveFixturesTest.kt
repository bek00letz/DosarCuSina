package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.math.BigDecimal
import java.time.Clock
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * The hand-written fixtures every implementation imports (shared/fixtures/dosar-v3, dosar-v2), as the iOS
 * `ArchiveTests` and `ArchiveV2Tests`.
 */
class ArchiveFixturesTest {
    @TempDir
    lateinit var staging: File

    private val bucharest: ZoneId = ZoneId.of("Europe/Bucharest")
    private val clock: Clock = Clock.fixed(moment("2026-11-26T10:00:00Z"), ZoneOffset.UTC)

    private fun service(binder: TestBinder) =
        DossierArchiveService(binder, Catalog.builtIn, clock = clock, zone = { bucharest })

    private fun import(
        binder: TestBinder,
        archive: ByteArray,
        mode: ArchiveImportMode = ArchiveImportMode.REPLACE,
    ) =
        service(binder).importArchive(MemoryByteSource(archive), mode = mode, staging = staging)

    @Test
    fun theV3FixtureImportsCompletely() {
        val archive = fixtureArchive("dosar-v3/household")
        val binder = testBinder()
        val summary = service(binder).inspect(MemoryByteSource(archive))
        assertEquals(3, summary.schemaVersion)
        assertEquals(2, summary.counts.assets)

        import(binder, archive)
        val home = binder.binder
        assertEquals(listOf("Barca de pe lac", "VW Golf"), home.assets.map { it.name }.sorted())
        val car = home.assets.first { it.name == "VW Golf" }
        assertEquals(FieldValue.Text("B-123-ABC"), car.values.value["vehicle.plate"])

        val itp = home.obligations.first { it.title == "ITP" && it.assetId == car.id }
        assertEquals(RecurrenceRule.Legal("vehicleITP"), itp.recurrence.value)
        assertEquals(CalendarDay(2028, 3, 1), itp.dueDay)
        val inspection = home.historyEntries.first { it.obligationId == itp.id }
        assertEquals(Money(BigDecimal("175.5")), inspection.totalCost)
        val report = home.attachments.first { it.historyEntryId == inspection.id }
        assertTrue(report.file!!.open().use { it.readAllBytes() }.decodeToString().startsWith("Inspecție"))
        assertEquals(1, report.pages.size)
        assertNotNull(report.thumbnail)
        assertEquals(62, report.byteCount)

        val brakes = home.historyEntries.first { it.kind == "repair" }
        assertEquals(ChangeTime.UNKNOWN, brakes.updatedAt, "An entry the archive carries no time for has none")
        val pads = home.serviceItems.first { it.entryId == brakes.id }
        assertEquals("brakes.padsFront", pads.componentKey)
        assertEquals("Magazin piese exemplu", home.providers.first { it.id == pads.supplierId }.name)

        val firms = home.providers.sortedBy { it.name }
        assertEquals(listOf("autoParts"), firms[0].trades, "Trades this version doesn't know are kept")
        assertEquals(listOf(car.id), firms[1].assetIds)
        assertEquals("12345678", firms[1].taxID)

        val rca = home.obligations.first { it.title == "RCA" }
        assertEquals(480, rca.reminderMinuteOfDay)
        assertEquals("POL-000001", rca.reference)
        assertTrue(rca.reminders.value.followUpAfterLapse, "The follow-up flag travels with the archive")
        val policies = home.attachments.filter { it.obligationId == rca.id }.sortedBy { it.createdAt }
        assertEquals(listOf("Poliță RCA 2025", "Poliță RCA 2026"), policies.map { it.title })
        assertTrue(policies[0].isArchived)
        assertEquals(policies[1].id, policies[0].supersededById)
        assertEquals(CalendarDay(2026, 12, 14), policies[0].validUntil, "Last year's policy keeps last year's end")

        val boats = home.templates.first { it.key == "custom.0b6c6f43-6c1e-4d1a-9c55-7d3b4f1f2a10" }
        assertFalse(boats.isBuiltIn)
        assertEquals(2, boats.sections.items.first().fields.size)
        val vehicle = home.templates.first { it.key == "vehicle" }
        assertTrue(vehicle.isBuiltIn)
        assertFalse(vehicle.isOnHome, "Household preferences travel with the archive")
    }

    @Test
    fun aMergeKeepsTheNewerEditAndWhatIsOnlyHere() {
        val binder = testBinder()
        import(binder, fixtureArchive("dosar-v3/household"))
        val car = binder.binder.assets.first { it.name == "VW Golf" }
        val edited = car.copy(name = "VW Golf editat", updatedAt = moment("2026-10-01T12:00:00Z"))
        val local = car.copy(id = java.util.UUID.randomUUID(), name = "Doar aici", parentId = null)
        val before = binder.binder
        val withEdits =
            testBinder(before.copy(assets = before.assets.map { if (it.id == car.id) edited else it } + local))

        val result = import(withEdits, fixtureArchive("dosar-v3/household"), ArchiveImportMode.MERGE)
        assertTrue(result.skipped > 0)
        assertEquals(0, result.inserted)
        assertEquals(setOf("VW Golf editat", "Barca de pe lac", "Doar aici"), withEdits.binder.assets.map {
            it.name
        }.toSet())
    }

    @Test
    fun aBackupWithoutChangeTimesNeverOverwritesAChangeHere() {
        val binder = testBinder()
        import(binder, fixtureArchive("dosar-v3/household"))
        val now = binder.binder
        val noted = now.copy(
            historyEntries = now.historyEntries.map {
                if (it.updatedAt == ChangeTime.UNKNOWN) it.copy(
                    note = "Plăcuțe originale.",
                    updatedAt = moment("2026-11-01T00:00:00Z"),
                ) else it
            },
        )
        val here = testBinder(noted)
        val result = import(here, fixtureArchive("dosar-v3/household"), ArchiveImportMode.MERGE)
        assertEquals(0, result.updated)
        assertTrue(here.binder.historyEntries.any { it.note == "Plăcuțe originale." })
    }

    @Test
    fun aFailedImportLeavesEverythingAsItWas() {
        val binder = testBinder()
        import(binder, fixtureArchive("dosar-v3/household"))
        val before = binder.binder
        val broken = fixtureArchive("dosar-v3/household") { files ->
            files["data/assets.json"] = files.getValue("data/assets.json").decodeToString()
                .replace("8a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c52", "not-an-id").encodeToByteArray()
            files.rechecksum("data/assets.json")
        }
        val error = assertThrows<ArchiveError.BrokenReference> { import(binder, broken) }
        assertEquals("data/assets.json", error.path)
        assertEquals(before, binder.binder)

        binder.failsNextWrite = true
        assertThrows<IllegalStateException> { import(binder, fixtureArchive("dosar-v3/household")) }
        assertEquals(before, binder.binder, "A store that fails half way keeps nothing of the import")
        assertTrue(staging.listFiles().orEmpty().isEmpty(), "The staging folder goes, whatever happens")
    }

    @Test
    fun checksumsAreEnforced() {
        val binder = testBinder()
        val tampered = fixtureArchive("dosar-v3/household") { files ->
            files["data/obligations.json"] = files.getValue("data/obligations.json").decodeToString()
                .replace("\"180\"", "\"18\"").encodeToByteArray()
        }
        assertEquals(
            ArchiveError.ChecksumMismatch("data/obligations.json"),
            assertThrows<ArchiveError> { service(binder).inspect(MemoryByteSource(tampered)) },
        )
        val extra = fixtureArchive("dosar-v3/household") { it["vault/extra.bin"] = byteArrayOf(1, 2, 3) }
        assertEquals(ArchiveError.UnlistedFile("vault/extra.bin"), assertThrows<ArchiveError> {
            service(binder).inspect(MemoryByteSource(extra))
        })
        val missing =
            fixtureArchive("dosar-v3/household") { it.remove("vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8.txt") }
        assertEquals(
            ArchiveError.MissingFile("vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8.txt"),
            assertThrows<ArchiveError> { service(binder).inspect(MemoryByteSource(missing)) },
        )
    }

    @Test
    fun newerSchemaVersionsAreRefusedWithTheirOwnReason() {
        val future = createArchive(listOf(Entry(
            "manifest.json",
            """{"format":"com.ar.dosarcusina.dossier","schemaVersion":9}""".encodeToByteArray(),
        )))
        assertEquals(ArchiveError.UnsupportedVersion(9), assertThrows<ArchiveError> {
            DossierArchiveReader.read(MemoryByteSource(future), Catalog.builtIn, directory = staging)
        })
        val other = createArchive(listOf(Entry("readme.txt", "hi".encodeToByteArray())))
        assertEquals(ArchiveError.NotADossier, assertThrows<ArchiveError> {
            DossierArchiveReader.read(MemoryByteSource(other), Catalog.builtIn, directory = staging)
        })
        val foreign = createArchive(listOf(Entry(
            "manifest.json",
            """{"format":"com.example","schemaVersion":3}""".encodeToByteArray(),
        )))
        assertEquals(ArchiveError.NotADossier, assertThrows<ArchiveError> {
            DossierArchiveReader.summary(MemoryByteSource(foreign), Catalog.builtIn)
        })
    }

    @Test
    fun aSummaryStreamsEveryFileAndKeepsNone() {
        val archive = fixtureArchive("dosar-v3/household")
        DossierArchiveReader.summary(MemoryByteSource(archive), Catalog.builtIn)
        assertTrue(staging.listFiles().orEmpty().isEmpty())
        // Reading it takes each file out once and decodes the data files from where they were written, removing each.
        val folder = File(staging, "read")
        val pack = DossierArchiveReader.read(MemoryByteSource(archive), Catalog.builtIn, directory = folder)
        assertEquals(5, folder.listFiles().orEmpty().size, "Only the vault's five files stay, for the importer")
        assertEquals(5, pack.files.paths.size)
    }

    @Test
    fun firstGenerationBackupsStillImport() {
        val binder = testBinder()
        import(binder, fixtureArchive("dosar-v2/ios-export"))
        val home = binder.binder
        val assets = home.assets.sortedBy { it.name }
        assertEquals(listOf("Dacia Logan", "Mașina de spălat"), assets.map { it.name })
        val car = assets[0]
        assertEquals("vehicle", car.templateKey)
        assertEquals(FieldValue.Text("CJ-12-XYZ"), car.values.value["vehicle.plate"])
        assertEquals(FieldValue.Number(110.0), car.values.value["vehicle.powerHp"])
        assertTrue(car.notes!!.contains("Hotel roți: Service exemplu"), "Custom fields are kept in the notes")
        assertTrue(car.notes.orEmpty().contains("Subtitlu: Mașina de oraș"))

        val rca = home.obligations.first { it.title == "RCA" }
        assertEquals("insurance", rca.kind)
        assertEquals(RecurrenceRule.Interval(1, "year", "dueDate"), rca.recurrence.value)
        assertEquals(listOf(30, 7, 1), rca.reminders.value.leadDays)
        val itp = home.obligations.first { it.title == "ITP" }
        assertEquals("done", itp.status)
        val completion = home.historyEntries.first { it.obligationId == itp.id }
        assertEquals("inspection", completion.kind)
        assertEquals(Money(BigDecimal(160)), completion.totalCost)
        assertEquals(1, home.attachments.count { it.obligationId == itp.id && it.historyEntryId == completion.id })
        val service = home.historyEntries.first { it.kind == "maintenance" }
        // Found among the vehicle's parts in the catalog, as the iOS app finds it.
        assertEquals("engine.oil", home.serviceItems.first { it.entryId == service.id }.componentKey)

        val washer = assets[1]
        assertEquals("purchase", washer.templateKey)
        assertEquals(FieldValue.Day(CalendarDay(2027, 6, 15)), washer.values.value["purchase.warrantyUntil"])
        assertEquals(FieldValue.Number(24.0), washer.values.value["purchase.warrantyMonths"])
        assertEquals("odometer", home.measurements.single().kind)
        assertNull(home.measurements.single().unitPriceAmount)
    }
}
