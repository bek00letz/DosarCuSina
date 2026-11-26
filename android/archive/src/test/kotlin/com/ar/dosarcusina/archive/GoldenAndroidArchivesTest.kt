package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.v3.Digests
import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.time.Clock
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Android's golden archives in shared/fixtures/golden/android/: `household.dosar`, its
 * password-protected twin and their contents unpacked in `expected/`, laid out as `ios/` is. The
 * iOS suite imports them (`AndroidGoldenArchiveTests`).
 *
 * The household is the iOS golden household brought into an empty Android binder and written
 * out by the Android writer: iOS → Android → iOS. They are kept fresh by contents, not bytes
 * (the password's salt changes every time, and so do the entries' dates where the time zone
 * does): the test writes them again and fails when what it writes differs from what is
 * committed. Bring them up to date with `./gradlew :archive:test -PwriteGoldenArchives`, or copy
 * what a failed run left in `build/golden-archives/` (the Android workflow keeps it as
 * `android-golden-archives`), then review the diff of `expected/` and commit it with both archives.
 */
class GoldenAndroidArchivesTest {
    @TempDir
    lateinit var staging: File

    private val bucharest: ZoneId = ZoneId.of("Europe/Bucharest")
    private val golden = File(sharedFolder, "fixtures/golden")
    private val android = File(golden, "android")

    private val regenerate =
        "shared/fixtures/golden/android/ is out of date with what the Android writer makes. Bring it up to " +
        "date with ./gradlew :archive:test -PwriteGoldenArchives (from android/), or copy household.dosar, " +
        "household-password.dosar and expected/ from the failed run's android-golden-archives artifact " +
        "over it; then review the diff of expected/ and commit it with both archives. The iOS suite imports them."

    /** The iOS golden household, brought into an empty binder. */
    private fun household(): Binder {
        val binder = InMemoryBinder()
        DossierArchiveService(binder, clock = Clock.fixed(IMPORTED_AT, ZoneOffset.UTC), zone = { bucharest })
            .importArchive(
                MemoryByteSource(File(golden, "ios/household.dosar").readBytes()),
                null,
                ArchiveImportMode.REPLACE,
                staging,
            )
        return binder.binder
    }

    /** The household written by the Android writer, plain and with the password. */
    private fun freshArchives(): Pair<ByteArray, ByteArray> {
        val binder = household()
        val writer = DossierArchiveWriter(APP_VERSION, EXPORTED_AT, bucharest)
        val plain = MemoryByteSink().also { writer.write(binder, it) }.data
        val protected = MemoryByteSink().also { sink ->
            val sealed = ArchiveEncryption.EncryptingSink(sink, GoldenContents.PASSWORD)
            writer.write(binder, sealed)
            sealed.finish()
        }.data
        return plain to protected
    }

    @Test
    fun theCommittedAndroidGoldenArchivesAreWhatTheWriterMakesToday() {
        val (plain, protected) = freshArchives()
        val unpacked = Unpacked.of(plain)
        assertEquals(
            unpacked,
            Unpacked.of(decrypt(protected, GoldenContents.PASSWORD)),
            "The twin holds the same archive",
        )
        if (System.getProperty("dosar.writeGoldenArchives") == "1") keep(plain, protected, unpacked, android)

        val committed = Unpacked.read(File(android, "expected"))
        val outOfDate = Unpacked.differences(committed, unpacked)
        if (outOfDate.isNotEmpty()) System.getProperty("dosar.goldenArchivesOut")?.let {
            keep(plain, protected, unpacked, File(it))
        }
        assertTrue(outOfDate.isEmpty(), outOfDate.joinToString("\n") + "\n" + regenerate)

        // The archives committed beside it are the ones expected/ unpacks.
        val committedPlain = File(android, "household.dosar").readBytes()
        assertFalse(ArchiveEncryption.isEncrypted(MemoryByteSource(committedPlain)))
        assertTrue(
            Unpacked.differences(committed, Unpacked.of(committedPlain)).isEmpty(),
            "household.dosar unpacks to expected/",
        )
        val committedProtected = File(android, "household-password.dosar").readBytes()
        assertTrue(ArchiveEncryption.isEncrypted(MemoryByteSource(committedProtected)))
        val opened = Unpacked.of(decrypt(committedProtected, GoldenContents.PASSWORD))
        assertTrue(Unpacked.differences(committed, opened).isEmpty(), "household-password.dosar opens to expected/")
        assertTrue(
            File(android, "README.md").readText().contains("`${GoldenContents.PASSWORD}`"),
            "The README says the password",
        )
    }

    /**
     * Both committed Android archives come back whole into an empty Android binder, and hold
     * exactly what the iOS golden household holds: iOS → Android lost nothing on the way out either.
     */
    @ParameterizedTest
    @ValueSource(strings = ["household.dosar", "household-password.dosar"])
    fun bothAndroidGoldenArchivesComeBackWhole(name: String) {
        val password = if (name.contains("password")) GoldenContents.PASSWORD else null
        val binder = InMemoryBinder()
        DossierArchiveService(binder, clock = Clock.fixed(IMPORTED_AT, ZoneOffset.UTC), zone = { bucharest })
            .importArchive(
                MemoryByteSource(File(android, name).readBytes()),
                password,
                ArchiveImportMode.REPLACE,
                staging,
            )
        val came = GoldenContents.of(ArchiveRecords.of(binder.binder, bucharest))
        val ios = GoldenContents.read(File(golden, "ios/expected"))
        val differences = GoldenContents.differences(ios, came).filterNot(Allowed::covers)
        assertTrue(differences.isEmpty(), "$name differs from the iOS household:\n" + differences.joinToString("\n"))
        val android = GoldenContents.read(File(android, "expected"))
        assertTrue(GoldenContents.differences(android, came).isEmpty(), "$name comes back as it was written")
        val manifest = android.manifest
        assertEquals(JsonPrimitive(DossierArchiveWriter.PLATFORM), manifest["platform"])
        assertTrue(
            JsonTrees.same(ios.manifest.getValue("counts"), manifest.getValue("counts")),
            "Every record of the iOS household is in it",
        )
    }

    private fun keep(plain: ByteArray, protected: ByteArray, unpacked: Unpacked, folder: File) {
        folder.mkdirs()
        File(folder, "household.dosar").writeBytes(plain)
        File(folder, "household-password.dosar").writeBytes(protected)
        unpacked.write(File(folder, "expected"))
    }

    private companion object {
        /** When the archives say they were written: the iOS golden archives' own moment. */
        val EXPORTED_AT = moment("2026-11-20T10:00:00Z")

        /** When the iOS household is brought in: after every moment it holds. */
        val IMPORTED_AT = moment("2026-11-26T10:00:00Z")

        /** The version the Android golden archives say made them. */
        const val APP_VERSION = "1.0"
    }
}

/**
 * An archive's contents as `expected/` keeps them: the manifest and the nine data files as
 * written, and every other file by path and SHA-256 in `vault.json`.
 */
data class Unpacked(val files: Map<String, String>, val vault: Map<String, String>) {
    /** Writes `expected/`: each file as the archive holds it, and the vault's listing. */
    fun write(folder: File) {
        folder.deleteRecursively()
        for ((path, text) in files) {
            val file = File(folder, path)
            file.parentFile.mkdirs()
            file.writeText(text)
        }
        val listing = JsonObject(vault.mapValues { JsonPrimitive(it.value) })
        File(folder, LISTING).writeText(MachineText.json(listing, MachineText.JsonLayout.READABLE) + "\n")
    }

    companion object {
        const val LISTING = "vault.json"
        private val KEPT = DossierV3.Path.DATA_FILES + DossierV3.Path.MANIFEST

        fun of(archive: ByteArray): Unpacked {
            val files = sortedMapOf<String, String>()
            val vault = sortedMapOf<String, String>()
            for (entry in unpackArchive(archive)) {
                if (entry.path in KEPT) files[entry.path] =
                    entry.data.decodeToString() else vault[entry.path] = Digests.sha256(entry.data)
            }
            return Unpacked(files, vault)
        }

        fun read(folder: File): Unpacked {
            val files =
                KEPT.associateWith { File(folder, it) }.filterValues(File::exists).mapValues { it.value.readText() }
            val listing = File(folder, LISTING)
            val vault = if (listing.exists()) {
                (MachineText.parse(listing.readText()) as JsonObject).mapValues { (it.value as JsonPrimitive).content }
            } else {
                emptyMap()
            }
            return Unpacked(files.toSortedMap(), vault.toSortedMap())
        }

        /**
         * Every file whose contents differ, compared as JSON (a manifest's or a data file's
         * value, whatever its bytes), and every vault file whose SHA-256 differs.
         */
        fun differences(expected: Unpacked, actual: Unpacked): List<String> {
            val found = ArrayList<String>()
            for (path in (expected.files.keys + actual.files.keys).sorted()) {
                val left = expected.files[path]?.let(MachineText::parseOrNull)
                val right = actual.files[path]?.let(MachineText::parseOrNull)
                if (left == null || right == null || !JsonTrees.same(
                    left,
                    right,
                )) found += "$path differs from what is committed"
            }
            for (path in (expected.vault.keys + actual.vault.keys).sorted()) {
                if (expected.vault[path] != actual.vault[path]) found += "vault $path differs from what is committed"
            }
            return found
        }
    }
}
