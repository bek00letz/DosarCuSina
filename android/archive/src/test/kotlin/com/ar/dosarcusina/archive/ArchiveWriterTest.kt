package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.archive.v3.MemoryFile
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Clock
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * The Android writer, as the iOS `ArchiveTests`, `ArchivePicturesTests` and `BackupsThatRestoreTests` pin the iOS one.
 */
class ArchiveWriterTest {
    @TempDir
    lateinit var staging: File

    private val bucharest: ZoneId = ZoneId.of("Europe/Bucharest")
    private val clock: Clock = Clock.fixed(moment("2026-11-26T10:00:00Z"), ZoneOffset.UTC)

    private fun household(): InMemoryBinder = InMemoryBinder().also {
        DossierArchiveService(it, clock = clock, zone = { bucharest })
            .importArchive(
                MemoryByteSource(fixtureArchive("dosar-v3/household")),
                mode = ArchiveImportMode.REPLACE,
                staging = staging,
            )
    }

    @Test
    fun exportedFilesFollowTheContract() {
        val sink = MemoryByteSink()
        DossierArchiveWriter("1.0", moment("2026-11-02T10:00:00Z"), bucharest).write(household().binder, sink)
        val entries = unpackArchive(sink.data).associate { it.path to it.data }
        val manifest = entries.getValue(DossierV3.Path.MANIFEST).decodeToString()
        assertTrue(manifest.contains("\"schemaVersion\" : 3"))
        assertTrue(manifest.contains("\"exportedAt\" : \"2026-11-02T10:00:00Z\""))
        assertTrue(manifest.contains("\"platform\" : \"Android\""))
        val obligations = entries.getValue(DossierV3.Path.OBLIGATIONS).decodeToString()
        assertTrue(
            Regex("\"dueDate\" : \"\\d{4}-\\d{2}-\\d{2}\"").containsMatchIn(obligations),
            "Due dates are calendar days",
        )
        assertTrue(Regex("\"id\" : \"[0-9a-f-]{36}\"").containsMatchIn(obligations), "Identifiers are lowercase")
        assertTrue(Regex("\"amount\" : \"\\d+(\\.\\d+)?\"").containsMatchIn(obligations), "Money is a decimal string")
        for (path in DossierV3.Path.DATA_FILES) assertTrue(path in entries, "$path is always written")
        // Pages and thumbnails are named by their bytes; the fixture's are neither JPEG nor named otherwise.
        assertTrue(entries.keys.any { it.endsWith("/page-1.heic") })
        // Every file but the manifest is listed with its SHA-256.
        val checksums =
            (com.ar.dosarcusina.core.values.MachineText.parse(manifest) as kotlinx.serialization.json.JsonObject)
            .getValue("checksums") as kotlinx.serialization.json.JsonObject
        assertEquals(entries.keys - DossierV3.Path.MANIFEST, checksums.keys)
    }

    @Test
    fun anExportComesBackAsItWasAndOpensOnlyWithItsPassword() {
        val source = household()
        val service = DossierArchiveService(source, clock = clock, zone = { bucharest })
        val file = File(staging, "copie.dosar")
        service.export(file, password = "parola-de-test-dosar", appVersion = "1.0")
        val bytes = file.readBytes()
        assertTrue(ArchiveEncryption.isEncrypted(MemoryByteSource(bytes)))
        assertEquals(ArchiveError.NeedsPassword, assertThrows<ArchiveError> {
            service.inspect(MemoryByteSource(bytes))
        })
        assertEquals(ArchiveError.WrongPassword, assertThrows<ArchiveError> {
            service.inspect(MemoryByteSource(bytes), "altă-parolă")
        })

        val target = InMemoryBinder()
        DossierArchiveService(target, clock = clock, zone = { bucharest })
            .importArchive(
                MemoryByteSource(bytes),
                "parola-de-test-dosar",
                ArchiveImportMode.REPLACE,
                File(staging, "in"),
            )
        val before = GoldenContents.of(ArchiveRecords.of(source.binder, bucharest))
        val after = GoldenContents.of(ArchiveRecords.of(target.binder, bucharest))
        assertTrue(
            GoldenContents.differences(before, after).isEmpty(),
            GoldenContents.differences(before, after).joinToString("\n"),
        )
    }

    @Test
    fun aPictureIsNamedByWhatItIs() {
        val home = household().binder
        val jpeg = MemoryFile(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 1, 2, 3))
        val withJpeg = home.copy(attachments = home.attachments.map {
            if (it.pages.isEmpty()) it else it.copy(pages = listOf(jpeg), thumbnail = jpeg)
        })
        val paths = ArchiveRecords.of(withJpeg, bucharest).attachments.flatMap {
            it.pagePaths + listOfNotNull(it.thumbnailPath)
        }
        assertTrue(paths.isNotEmpty() && paths.all { it.endsWith(".jpg") }, "$paths")
    }

    @Test
    fun aDocumentTooBigForABackupIsNamedAndNoFileIsLeft() {
        val home = household().binder
        val big = MemoryFile(ByteArray(2_000))
        val withBig = home.copy(attachments = home.attachments.map {
            if (it.title == "Poliță RCA 2026") it.copy(file = big) else it
        })
        val limits = DosarZipEngine.Limits(maxEntries = 100, maxEntryBytes = 1_000)
        val file = File(staging, "prea-mare.dosar")
        val error = assertThrows<ArchiveError.DocumentTooLarge> {
            DossierArchiveWriter("1.0", clock.instant(), bucharest, limits).write(withBig, file)
        }
        assertEquals("Poliță RCA 2026", error.title)
        assertFalse(file.exists())
        assertTrue(staging.listFiles().orEmpty().none { it.name.endsWith(".partial") }, "No half-written file is left")
    }
}
