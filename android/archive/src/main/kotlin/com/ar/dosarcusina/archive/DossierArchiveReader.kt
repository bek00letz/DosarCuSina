package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.v2.DossierV2Converter
import com.ar.dosarcusina.archive.v3.ArchiveFile
import com.ar.dosarcusina.archive.v3.ArchiveFiles
import com.ar.dosarcusina.archive.v3.AssetRecord
import com.ar.dosarcusina.archive.v3.AttachmentRecord
import com.ar.dosarcusina.archive.v3.DataFiles
import com.ar.dosarcusina.archive.v3.Digests
import com.ar.dosarcusina.archive.v3.DossierPackage
import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.archive.v3.HistoryEntryRecord
import com.ar.dosarcusina.archive.v3.IssuerLessonRecord
import com.ar.dosarcusina.archive.v3.JsonRecord
import com.ar.dosarcusina.archive.v3.Manifest
import com.ar.dosarcusina.archive.v3.MeasurementRecord
import com.ar.dosarcusina.archive.v3.ObligationRecord
import com.ar.dosarcusina.archive.v3.ProviderRecord
import com.ar.dosarcusina.archive.v3.ServiceItemRecord
import com.ar.dosarcusina.archive.v3.TemplateRecord
import com.ar.dosarcusina.archive.v3.UnreadableRecord
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.time.Instant

/** What an archive says it holds, read before the person chooses to bring it in. */
data class ArchiveSummary(
    val schemaVersion: Int,
    val platform: String,
    val exportedAt: Instant,
    val counts: Manifest.Counts,
) {
    constructor(manifest: Manifest) : this(
        manifest.schemaVersion,
        manifest.platform,
        manifest.exportedAt,
        manifest.counts,
    )
}

/**
 * Reads, checks and decodes an archive, a piece at a time, as the iOS app's
 * `DossierArchiveReader` (ios/DosarCuSina/Services/Archive/DossierArchiveService.swift): the
 * directory, then each file once, its checksum worked out as it streams by, within the one set
 * of limits both ways ([DosarZipEngine.Limits.standard]). Memory doesn't grow with the archive.
 *
 * - [summary] keeps none of the files, only the manifest: enough to say what the archive holds.
 * - [read] writes each file to a folder of its own, then decodes the data files one at a time
 *   (only one is ever held whole), and leaves the documents' files there for the importer.
 *
 * A protected archive is opened with its password ([ArchiveOpening]). A schema version higher
 * than this build knows is refused ([ArchiveError.UnsupportedVersion]); version 2 is read
 * through [DossierV2Converter].
 */
object DossierArchiveReader {
    /** What becomes of the archive's files as they are checked. */
    private sealed interface Keeping {
        /** Checked against their checksums, then let go. */
        data object CheckOnly : Keeping

        /** Written, one file each, to this folder (made if needed), for the importer to read. */
        data class Extract(val directory: File) : Keeping
    }

    /** What an archive holds, once every file in it is checked. None of its files is kept. */
    fun summary(
        source: ArchiveByteSource,
        builtIns: BuiltIns,
        password: String? = null,
        limits: DosarZipEngine.Limits = DosarZipEngine.Limits.standard,
    ): ArchiveSummary = ArchiveOpening.opened(source, password) { plain ->
        when (val reading = readPlain(plain, limits, Keeping.CheckOnly, builtIns)) {
            is Reading.Summary -> reading.summary
            is Reading.Package -> ArchiveSummary(reading.pack.manifest)
        }
    }

    /**
     * The archive, checked and decoded, its documents' files written to [directory] for the
     * importer to read one at a time. The caller removes [directory] once the package is in.
     * A version 2 archive's line items are matched to the parts of [builtIns]' categories.
     */
    fun read(
        source: ArchiveByteSource,
        builtIns: BuiltIns,
        password: String? = null,
        directory: File,
        limits: DosarZipEngine.Limits = DosarZipEngine.Limits.standard,
    ): DossierPackage = ArchiveOpening.opened(source, password) { plain ->
        when (val reading = readPlain(plain, limits, Keeping.Extract(directory), builtIns)) {
            is Reading.Package -> reading.pack
            is Reading.Summary -> throw ArchiveError.NotADossier
        }
    }

    private sealed interface Reading {
        data class Summary(val summary: ArchiveSummary) : Reading

        data class Package(val pack: DossierPackage) : Reading
    }

    private fun readPlain(
        source: ArchiveByteSource,
        limits: DosarZipEngine.Limits,
        keeping: Keeping,
        builtIns: BuiltIns,
    ): Reading {
        val zip = DosarZipEngine.Reader(source, limits)
        val manifestItem = zip.item(DossierV3.Path.MANIFEST) ?: throw ArchiveError.NotADossier
        val manifestBytes = zip.data(manifestItem)
        val version = schemaVersion(manifestBytes)

        return when (version) {
            DossierV2Converter.SCHEMA_VERSION -> {
                // The first format's files are converted together, so they are held while it is read.
                val checked = check(
                    zip, DossierV2Converter.checksums(manifestBytes), DossierV2Converter.DATA_FILES,
                    refusingUnlisted = false, keeping = keeping, holdingData = true,
                )
                Reading.Package(DossierV2Converter.pack(manifestBytes, checked.data, checked.vault, builtIns))
            }
            DossierV3.SCHEMA_VERSION -> readV3(zip, manifestBytes, keeping)
            else -> throw ArchiveError.UnsupportedVersion(version)
        }
    }

    /** The manifest's schema version, read as the iOS app's version probe reads it; not a dossier when it can't be. */
    private fun schemaVersion(manifestBytes: ByteArray): Int {
        val probe = MachineText.parseOrNull(manifestBytes.decodeToString()) as? JsonObject
        val format = probe?.get("format")
        val formatIsOurs = format == null
            || (format is JsonPrimitive && format.isString && format.content == DossierV3.FORMAT)
        val version = probe?.get("schemaVersion")?.let(::wholeNumber)
        if (version == null || !formatIsOurs) throw ArchiveError.NotADossier
        return version
    }

    private fun readV3(zip: DosarZipEngine.Reader, manifestBytes: ByteArray, keeping: Keeping): Reading {
        val manifest = try {
            Manifest.read(MachineText.parseOrNull(manifestBytes.decodeToString()) ?: throw UnreadableRecord())
        } catch (_: UnreadableRecord) {
            throw ArchiveError.UnreadableFile(DossierV3.Path.MANIFEST)
        }
        val checked = check(
            zip, manifest.checksums, DossierV3.Path.DATA_FILES.toSet(),
            refusingUnlisted = true, keeping = keeping, holdingData = false,
        )
        if (keeping !is Keeping.Extract) return Reading.Summary(ArchiveSummary(manifest))

        /** Each file read from where it was written, decoded, and let go before the next. */
        fun <T> decode(path: String, record: (JsonElement) -> T): List<T> {
            val file = checked.written[path] ?: return emptyList()
            try {
                val json = MachineText.parseOrNull(file.readText()) ?: throw UnreadableRecord()
                return DataFiles.read(json, record)
            } catch (_: UnreadableRecord) {
                throw ArchiveError.UnreadableFile(path)
            } finally {
                file.delete()
            }
        }
        val pack = DossierPackage(
            manifest = manifest,
            templates = decode(DossierV3.Path.TEMPLATES, TemplateRecord::read),
            assets = decode(DossierV3.Path.ASSETS, AssetRecord::read),
            obligations = decode(DossierV3.Path.OBLIGATIONS, ObligationRecord::read),
            historyEntries = decode(DossierV3.Path.HISTORY, HistoryEntryRecord::read),
            serviceItems = decode(DossierV3.Path.SERVICE_ITEMS, ServiceItemRecord::read),
            providers = decode(DossierV3.Path.PROVIDERS, ProviderRecord::read),
            measurements = decode(DossierV3.Path.MEASUREMENTS, MeasurementRecord::read),
            attachments = decode(DossierV3.Path.ATTACHMENTS, AttachmentRecord::read),
            issuerLessons = decode(DossierV3.Path.ISSUER_LESSONS, IssuerLessonRecord::read),
            files = checked.vault,
        )
        validateReferences(pack)
        return Reading.Package(pack)
    }

    private fun check(
        zip: DosarZipEngine.Reader,
        checksums: Map<String, String>,
        dataFiles: Set<String>,
        refusingUnlisted: Boolean,
        keeping: Keeping,
        holdingData: Boolean,
    ): ArchiveCheck = ArchiveCheck(zip, dataFiles, (keeping as? Keeping.Extract)?.directory, holdingData)
        .apply { run(checksums, refusingUnlisted) }

    /** Every path a document or a section refers to must be in the archive. */
    internal fun validateReferences(pack: DossierPackage) {
        for (attachment in pack.attachments) {
            for (path in attachment.allPaths) if (path !in pack.files) throw ArchiveError.MissingFile(path)
        }
        for (asset in pack.assets) {
            val photo = asset.photoPath ?: continue
            if (photo !in pack.files) throw ArchiveError.MissingFile(photo)
        }
    }

    /** A manifest's version as Swift's `Int` decoding reads it, or null when it isn't one. */
    private fun wholeNumber(element: JsonElement): Int? = try {
        JsonRecord.int(element)
    } catch (_: UnreadableRecord) {
        null
    }
}

/**
 * Every listed file must exist and match its SHA-256; with `refusingUnlisted`, every other
 * file (but the manifest) must be listed. Each file is read once, a piece at a time: only
 * checked, or written to a file of its own in [folder] (named by its place, never by the
 * archive's own path); a data file is held whole only with [holdingData]. What it kept: the
 * data files held ([data]) or written out ([written]), and the documents' files ([vault]).
 */
private class ArchiveCheck(
    private val zip: DosarZipEngine.Reader,
    private val dataFiles: Set<String>,
    private val folder: File?,
    private val holdingData: Boolean,
) {
    val data = LinkedHashMap<String, ByteArray>()
    val written = LinkedHashMap<String, File>()
    private val files = ArchiveFiles.Builder()
    val vault: ArchiveFiles get() = files.build()

    fun run(checksums: Map<String, String>, refusingUnlisted: Boolean) {
        checkListing(checksums, refusingUnlisted)
        folder?.mkdirs()
        for (item in zip.items.filter { it.path != DossierV3.Path.MANIFEST }) {
            val digest = take(item)
            val expected = checksums[item.path] ?: continue
            if (digest != expected.lowercase()) throw ArchiveError.ChecksumMismatch(item.path)
        }
    }

    /** Every listed file is there; with [refusingUnlisted], every file but the manifest is listed. */
    private fun checkListing(checksums: Map<String, String>, refusingUnlisted: Boolean) {
        for (path in checksums.keys.sorted()) if (zip.item(path) == null) throw ArchiveError.MissingFile(path)
        if (!refusingUnlisted) return
        for (item in zip.items) {
            val listed = item.path == DossierV3.Path.MANIFEST || item.path in checksums
            if (!listed) throw ArchiveError.UnlistedFile(item.path)
        }
    }

    /** Reads [item] once, keeps it as the check says, and gives its SHA-256. */
    private fun take(item: DosarZipEngine.Reader.Item): String {
        val isData = item.path in dataFiles
        val isVault = item.path.startsWith(DossierV3.Path.VAULT_PREFIX)
        return when {
            isData && holdingData -> zip.data(item).let { bytes ->
                data[item.path] = bytes
                MachineText.hex(Digests.hasher().digest(bytes))
            }
            folder != null && (isData || isVault) -> {
                // Named by its place, never by the archive's own path.
                val file = File(folder, if (isData) "data-${written.size}" else "${files.count}")
                val digest = extracted(item, file)
                if (isData) {
                    written[item.path] = file
                } else {
                    files.keep(item.path, ArchiveFile(item.path, file, digest, item.size))
                }
                digest
            }
            else -> streamed(item).also { if (isVault) files.checked(item.path) }
        }
    }

    /** [item] written to [file] a piece at a time; its SHA-256. */
    private fun extracted(item: DosarZipEngine.Reader.Item, file: File): String {
        val hasher = Digests.hasher()
        ArchiveFileSink(file).use { sink ->
            zip.stream(item) { piece ->
                hasher.update(piece)
                sink.write(piece)
            }
        }
        return MachineText.hex(hasher.digest())
    }

    /** [item] read a piece at a time and let go; its SHA-256. */
    private fun streamed(item: DosarZipEngine.Reader.Item): String {
        val hasher = Digests.hasher()
        zip.stream(item) { hasher.update(it) }
        return MachineText.hex(hasher.digest())
    }
}
