package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.v3.Digests
import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.archive.v3.Manifest
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * Writes the binder to a `.dosar` archive a piece at a time, as the iOS app's
 * `DossierArchiveWriter` (ios/DosarCuSina/Services/Archive/DossierArchiveWriter.swift): the
 * sections' photos and the documents' files first, one file at a time, then the data files,
 * then the manifest with every file's SHA-256. With a password the archive is sealed chunk by
 * chunk on its way out ([ArchiveEncryption.EncryptingSink]).
 *
 * Records are written as the archive's v3 records ([ArchiveRecords]): JSON as [MachineText]
 * writes it for an archive (indented, keys sorted, moments in UTC to the second), pages and
 * thumbnails named `.heic` or `.jpg` by their bytes, no secret and nothing that stays on the
 * phone. Every file is checked against the limits its reader reads before it is written, so a
 * backup this writes is one the app can put back; one that isn't leaves no file behind and says
 * which part was too much.
 */
class DossierArchiveWriter(
    private val appVersion: String,
    private val exportedAt: Instant,
    /**
     * The time zone days are counted in: a snooze's day is written as its start there, and the entries' dates in it.
     */
    private val zone: ZoneId = DosarCalendar.zone(),
    private val limits: DosarZipEngine.Limits = DosarZipEngine.Limits.standard,
) {
    /**
     * Writes [binder] to [file], which must not exist yet, sealed with [password] when there is
     * one. On any failure nothing is left at [file].
     */
    fun write(binder: Binder, file: File, password: String? = null) {
        val partial = File(file.parentFile, ".${UUID.randomUUID()}.partial")
        try {
            ArchiveFileSink(partial).use { sink ->
                if (password == null) {
                    write(binder, sink)
                } else {
                    val sealed = ArchiveEncryption.EncryptingSink(sink, password)
                    write(binder, sealed)
                    sealed.finish()
                }
            }
            if (!partial.renameTo(file)) error("The finished backup couldn't be put in its place.")
        } finally {
            partial.delete()
        }
    }

    /** The plain archive, file by file, into [sink]. */
    fun write(binder: Binder, sink: ArchiveByteSink) {
        refuseWhatIsTooLarge(binder)
        val contents = ArchiveRecords.of(binder, zone)
        val zip = DosarZipEngine.Writer(sink, limits, zone)
        val checksums = LinkedHashMap<String, String>()
        fun add(path: String, data: ByteArray) {
            zip.add(path, data, exportedAt)
            checksums[path] = Digests.sha256(data)
        }

        // The documents' and photos' files, each read when it is written and let go after.
        for ((path, stored) in contents.files) add(path, stored.open().use { it.readBytes() })

        fun data(path: String, records: List<JsonObject>) =
            add(path, MachineText.json(JsonArray(records), MachineText.JsonLayout.READABLE).encodeToByteArray())
        data(DossierV3.Path.TEMPLATES, contents.templates.map { it.toJson() })
        data(DossierV3.Path.ASSETS, contents.assets.map { it.toJson() })
        data(DossierV3.Path.OBLIGATIONS, contents.obligations.map { it.toJson() })
        data(DossierV3.Path.HISTORY, contents.historyEntries.map { it.toJson() })
        data(DossierV3.Path.SERVICE_ITEMS, contents.serviceItems.map { it.toJson() })
        data(DossierV3.Path.PROVIDERS, contents.providers.map { it.toJson() })
        data(DossierV3.Path.MEASUREMENTS, contents.measurements.map { it.toJson() })
        data(DossierV3.Path.ATTACHMENTS, contents.attachments.map { it.toJson() })
        data(DossierV3.Path.ISSUER_LESSONS, contents.issuerLessons.map { it.toJson() })

        val manifest = Manifest(
            format = DossierV3.FORMAT,
            schemaVersion = DossierV3.SCHEMA_VERSION,
            appVersion = appVersion,
            platform = PLATFORM,
            exportedAt = exportedAt,
            counts = Manifest.Counts(
                templates = contents.templates.size, assets = contents.assets.size,
                obligations = contents.obligations.size, historyEntries = contents.historyEntries.size,
                serviceItems = contents.serviceItems.size, providers = contents.providers.size,
                measurements = contents.measurements.size, attachments = contents.attachments.size,
                issuerLessons = contents.issuerLessons.size,
            ),
            checksums = checksums,
        )
        val manifestText = MachineText.json(manifest.toJson(), MachineText.JsonLayout.READABLE)
        zip.add(DossierV3.Path.MANIFEST, manifestText.encodeToByteArray(), exportedAt)
        zip.finish()
    }

    /**
     * A section's photo or a document's file bigger than one file of a backup may be, named, before anything is
     * written.
     */
    private fun refuseWhatIsTooLarge(binder: Binder) {
        fun tooLarge(file: StoredFile?) = file != null && file.size > limits.maxEntryBytes
        binder.assets.firstOrNull { tooLarge(it.photo) }?.let { throw ArchiveError.PhotoTooLarge(it.name) }
        binder.attachments.firstOrNull { document ->
            (listOf(document.file, document.thumbnail) + document.pages).any(::tooLarge)
        }
            ?.let { throw ArchiveError.DocumentTooLarge(it.title ?: it.fileName) }
    }

    companion object {
        /** What the manifest says made the archive. */
        const val PLATFORM = "Android"
    }
}
