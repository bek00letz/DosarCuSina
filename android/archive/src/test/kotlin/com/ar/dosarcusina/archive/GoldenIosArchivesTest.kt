package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.time.Clock
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * The iOS golden archives (shared/fixtures/golden/ios/), brought into an empty binder on
 * Android: what came in, written out again as the archive's records, must be exactly what
 * `expected/` holds, record by record and every vault file by its SHA-256, with no secret and
 * with every key a newer version wrote still there. Any difference fails, unless it is on
 * [Allowed], each entry with why.
 */
class GoldenIosArchivesTest {
    @TempDir
    lateinit var staging: File

    /** The iOS household's calendar (`Calendar.bucharest`): a snooze's day is written as its start there. */
    private val bucharest: ZoneId = ZoneId.of("Europe/Bucharest")

    private val ios = File(sharedFolder, "fixtures/golden/ios")

    @ParameterizedTest
    @ValueSource(strings = ["household.dosar", "household-password.dosar"])
    fun bothIosGoldenArchivesComeInWithNothingLost(name: String) {
        val password = if (name.contains("password")) GoldenContents.PASSWORD else null
        val binder = InMemoryBinder()
        val service = DossierArchiveService(
            binder,
            clock = Clock.fixed(moment("2026-11-26T10:00:00Z"), ZoneOffset.UTC),
            zone = { bucharest },
        )
        service.importArchive(
            MemoryByteSource(File(ios, name).readBytes()),
            password,
            ArchiveImportMode.REPLACE,
            staging,
        )

        val expected = GoldenContents.read(File(ios, "expected"))
        val came = GoldenContents.of(ArchiveRecords.of(binder.binder, bucharest))
        val differences = GoldenContents.differences(expected, came).filterNot(Allowed::covers)
        assertTrue(differences.isEmpty(), "$name came in different:\n" + differences.joinToString("\n"))
        // The comparison sees a change of one value of one record.
        val renamed = binder.binder.copy(assets = binder.binder.assets.mapIndexed { index, asset ->
            if (index == 0) asset.copy(notes = "Altceva") else asset
        })
        assertEquals(
            1,
            GoldenContents.differences(expected, GoldenContents.of(ArchiveRecords.of(renamed, bucharest))).size,
        )

        val manifest = expected.manifest
        for ((path, count) in GoldenContents.countKeys) {
            assertEquals(manifest.getValue("counts").let {
                (it as JsonObject)[count]
            }?.toString()?.toInt(), came.records[path]?.size, "$name: every record of $path came in")
        }

        // Secrets never come in; every key a newer version wrote is still there.
        val everything = came.records.values.flatMap { it.values }.joinToString("\n") { MachineText.json(it) }
        assertFalse(everything.contains(SecretRules.SEALED_PREFIX), "Nothing sealed")
        val sections = came.records.getValue(DossierV3.Path.ASSETS).values.joinToString("\n") { MachineText.json(it) }
        assertTrue(sections.contains("document.personalNumber"))
        assertFalse(sections.contains("document.pinAuthentication"), "A PIN field's value never comes in")
        assertFalse(everything.contains("Cod alarmă"), "A secret row never comes in")
        assertTrue(
            everything.contains("•••• 1111") && !everything.contains("4111 1111 1111 1111"),
            "A card number stays masked",
        )
        for (kept in listOf(
            "geoPoint",
            "futureNote",
            "futureColour",
            "skipHolidays",
            "quietHours",
            "futureSource",
            "futureBehaviour",
            "\"stars\"",
        )) {
            assertTrue(everything.contains(kept), "$name: $kept, which a newer version wrote, is kept")
        }
        assertEquals(true, binder.binder.locks["health"], "A locked category comes in locked")
    }
}

/**
 * The differences between Android and iOS that are allowed, each with why. Empty: everything an
 * iOS golden archive holds comes in on Android as it was.
 */
object Allowed {
    /** `data/file#record.key`, and why it may differ. */
    val ENTRIES: Map<String, String> = emptyMap()

    fun covers(difference: String): Boolean = ENTRIES.keys.any { difference.startsWith(it) }
}

/**
 * An archive's contents as `expected/` keeps them: the manifest, each data file's records by id
 * (a category's by its key), and every vault file by path and SHA-256. Shared by the tests that
 * compare what came in with a golden archive.
 */
class GoldenContents(
    val manifest: JsonObject,
    val records: Map<String, Map<String, JsonObject>>,
    val vault: Map<String, String>,
) {
    companion object {
        /** The placeholder password of both apps' `household-password.dosar`, also in their READMEs. */
        const val PASSWORD = "parola-de-test-dosar"

        /** Each data file and the manifest's count of its records. */
        val countKeys: List<Pair<String, String>> = listOf(
            DossierV3.Path.TEMPLATES to "templates", DossierV3.Path.ASSETS to "assets",
            DossierV3.Path.OBLIGATIONS to "obligations",
            DossierV3.Path.HISTORY to "historyEntries", DossierV3.Path.SERVICE_ITEMS to "serviceItems",
            DossierV3.Path.PROVIDERS to "providers", DossierV3.Path.MEASUREMENTS to "measurements",
            DossierV3.Path.ATTACHMENTS to "attachments", DossierV3.Path.ISSUER_LESSONS to "issuerLessons",
        )

        fun byId(records: List<JsonElement>): Map<String, JsonObject> = records.associate { record ->
            val fields = record as JsonObject
            ((fields["id"] ?: fields["key"]) as JsonPrimitive).content.lowercase() to fields
        }

        fun read(folder: File): GoldenContents {
            val records = DossierV3.Path.DATA_FILES.associateWith { path ->
                val file = File(folder, path)
                if (file.exists()) byId(MachineText.parse(file.readText()) as JsonArray) else emptyMap()
            }
            val vault = (MachineText.parse(File(folder, "vault.json").readText()) as JsonObject).mapValues {
                (it.value as JsonPrimitive).content
            }
            return GoldenContents(
                MachineText.parse(File(folder, "manifest.json").readText()) as JsonObject,
                records,
                vault,
            )
        }

        /** What a binder writes, by the records an archive of it holds. */
        fun of(contents: ArchiveContents): GoldenContents {
            val records = mapOf(
                DossierV3.Path.TEMPLATES to byId(contents.templates.map { it.toJson() }),
                DossierV3.Path.ASSETS to byId(contents.assets.map { it.toJson() }),
                DossierV3.Path.OBLIGATIONS to byId(contents.obligations.map { it.toJson() }),
                DossierV3.Path.HISTORY to byId(contents.historyEntries.map { it.toJson() }),
                DossierV3.Path.SERVICE_ITEMS to byId(contents.serviceItems.map { it.toJson() }),
                DossierV3.Path.PROVIDERS to byId(contents.providers.map { it.toJson() }),
                DossierV3.Path.MEASUREMENTS to byId(contents.measurements.map { it.toJson() }),
                DossierV3.Path.ATTACHMENTS to byId(contents.attachments.map { it.toJson() }),
                DossierV3.Path.ISSUER_LESSONS to byId(contents.issuerLessons.map { it.toJson() }),
            )
            return GoldenContents(JsonObject(emptyMap()), records, contents.files.associate {
                (path, file) -> path to file.sha256
            })
        }

        /** Every record, key and vault file that differs, as `data/file#record.key` lines. */
        fun differences(expected: GoldenContents, actual: GoldenContents): List<String> {
            val found = ArrayList<String>()
            for (path in DossierV3.Path.DATA_FILES) {
                val left = expected.records[path].orEmpty()
                val right = actual.records[path].orEmpty()
                for (id in (left.keys + right.keys).sorted()) {
                    val a = left[id]
                    val b = right[id]
                    if (a == null || b == null) {
                        found += "$path#$id is only on one side"
                        continue
                    }
                    for (key in (a.keys + b.keys).sorted()) {
                        val x = a[key]
                        val y = b[key]
                        if (x == null || y == null || !JsonTrees.same(
                            x,
                            y,
                        )) found += "$path#$id.$key: ${x?.let(MachineText::json)} ≠ ${y?.let(MachineText::json)}"
                    }
                }
            }
            for (path in (expected.vault.keys + actual.vault.keys).sorted()) {
                val (left, right) = expected.vault[path] to actual.vault[path]
                if (left != right) found += "vault $path: $left ≠ $right"
            }
            return found
        }
    }
}
