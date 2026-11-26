package com.ar.dosarcusina.archive.v3

import com.ar.dosarcusina.archive.ArchiveError
import com.ar.dosarcusina.archive.DosarArchiveFormat
import com.ar.dosarcusina.core.values.MachineText
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.time.Instant

/** The `.dosar` v3 format's names (shared/schemas/dosar-v3.md), as the iOS app's `DossierV3`. */
object DossierV3 {
    const val FORMAT: String = "com.ar.dosarcusina.dossier"
    const val SCHEMA_VERSION: Int = DosarArchiveFormat.SCHEMA_VERSION

    object Path {
        const val MANIFEST = "manifest.json"
        const val TEMPLATES = "data/templates.json"
        const val ASSETS = "data/assets.json"
        const val OBLIGATIONS = "data/obligations.json"
        const val HISTORY = "data/history.json"
        const val SERVICE_ITEMS = "data/service_items.json"
        const val PROVIDERS = "data/providers.json"
        const val MEASUREMENTS = "data/measurements.json"
        const val ATTACHMENTS = "data/attachments.json"

        /** What capture learned of each issuer's papers; missing in archives from before database version 16. */
        const val ISSUER_LESSONS = "data/issuer_lessons.json"
        const val VAULT_PREFIX = "vault/"
        const val PHOTOS_PREFIX = "vault/photos/"
        const val OPIS = "opis.pdf"

        /** Every data file, in the order the writer writes them; a writer writes all of them, even empty. */
        val DATA_FILES: List<String> = listOf(
            TEMPLATES, ASSETS, OBLIGATIONS, HISTORY, SERVICE_ITEMS, PROVIDERS, MEASUREMENTS, ATTACHMENTS,
            ISSUER_LESSONS,
        )

        private val JPEG_START = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())

        /**
         * The extension a scanned page or a thumbnail is written under, by what its first bytes
         * are: `jpg` for a JPEG, `heic` for anything else, as every page was named before. A
         * reader never goes by it: it knows a picture by its bytes.
         */
        fun pictureExtension(header: ByteArray): String =
            if (header.size >= JPEG_START.size && JPEG_START.indices.all {
                header[it] == JPEG_START[it]
            }) "jpg" else "heic"

        /** How many first bytes [pictureExtension] reads. */
        const val PICTURE_HEADER_BYTES: Int = 3
    }

    /**
     * Stored properties a backup never carries, by record type, each for a reason (the iOS
     * app's `DossierV3.stayOnThePhone`): which copy a record is (`copyID`), since when this
     * phone counts a deadline's cycle, when a category was last locked anywhere, where capture
     * keeps a document, when this phone made its pages smaller, the card in this phone's
     * contacts, a page's own id, and the id of what holds a record (the link travels instead).
     * The Android store (Phase 2) keeps these and writes none of them out.
     */
    val STAY_ON_THE_PHONE: Map<String, Set<String>> = mapOf(
        "Asset" to setOf("copyID"),
        "Obligation" to setOf("cycleKnownAt", "copyID", "assetID"),
        "HistoryEntry" to setOf("copyID", "assetID"),
        "ServiceItem" to setOf("copyID", "entryID"),
        "MeasurementLog" to setOf("copyID", "assetID"),
        "Attachment" to setOf("documentID", "compactedAt", "copyID", "assetID"),
        "Provider" to setOf("contactIdentifier", "copyID"),
        "AttachmentPage" to setOf("id", "copyID", "attachmentID"),
        "CategoryTemplate" to setOf("copyID", "lockedEverywhereAt"),
        "IssuerLesson" to setOf("copyID"),
    )
}

/**
 * When a record last changed, when it isn't known: older than any change, and the same for every
 * reader (the iOS app's `ChangeTime.unknown`, written `0001-01-01T00:00:00Z` where a record
 * always carries one, and left out where it may not).
 */
object ChangeTime {
    val UNKNOWN: Instant = requireNotNull(MachineText.moment("0001-01-01T00:00:00Z"))

    /** [time] as an archive writes it where it may leave it out: none when it isn't known. */
    fun written(time: Instant): Instant? = time.takeUnless { it == UNKNOWN }
}

/**
 * A file's bytes, wherever they are kept: a document's original, a page, a thumbnail, a
 * section's photo. Read a piece at a time ([open]); its SHA-256 is known without reading it.
 */
interface StoredFile {
    /** Lowercase hex SHA-256 of its bytes. */
    val sha256: String

    /** How many bytes it holds. */
    val size: Long

    /** Its bytes, from the start. The caller closes the stream. */
    fun open(): InputStream

    /** Its first [count] bytes, or fewer when it is shorter. */
    fun header(count: Int): ByteArray = open().use { it.readNBytes(count) }
}

/** A file kept in memory: small ones made by hand, in tests and the in-memory binder. */
class MemoryFile(private val bytes: ByteArray) : StoredFile {
    override val sha256: String = Digests.sha256(bytes)
    override val size: Long = bytes.size.toLong()

    override fun open(): InputStream = ByteArrayInputStream(bytes)

    fun bytes(): ByteArray = bytes.copyOf()
}

/** One of an archive's files, taken out to a file of its own by the reader, checked against its checksum. */
class ArchiveFile internal constructor(
    val path: String,
    private val file: File,
    override val sha256: String,
    override val size: Long,
) : StoredFile {
    override fun open(): InputStream = file.inputStream()
}

/**
 * An archive's files by path (`vault/…`), kept where the reader put them, so a package holds
 * none of them in memory, as the iOS app's `DossierV3.ArchiveFiles`. The importer hands each to
 * the binder as it writes the record it belongs to.
 */
class ArchiveFiles private constructor(private val contents: Map<String, Content>) {
    private sealed interface Content {
        /** Taken out of the archive into a file of its own, or made by hand. */
        data class Kept(val file: StoredFile) : Content

        /** Checked against its checksum, not kept: what a summary leaves. */
        data object Checked : Content
    }

    /** Every path, sorted. */
    val paths: List<String> get() = contents.keys.sorted()

    val isEmpty: Boolean get() = contents.isEmpty()

    operator fun contains(path: String): Boolean = contents.containsKey(path)

    /** The file at [path], or null when the archive has none; one only checked can't be read. */
    fun file(path: String): StoredFile? = when (val content = contents[path]) {
        is Content.Kept -> content.file
        Content.Checked -> throw ArchiveError.MissingFile(path)
        null -> null
    }

    /** Collects an archive's files as the reader checks them. */
    class Builder {
        private val contents = LinkedHashMap<String, Content>()

        fun keep(path: String, file: StoredFile) {
            contents[path] = Content.Kept(file)
        }

        fun checked(path: String) {
            contents[path] = Content.Checked
        }

        val count: Int get() = contents.size

        fun build(): ArchiveFiles = ArchiveFiles(contents.toMap())
    }

    companion object {
        val EMPTY: ArchiveFiles = ArchiveFiles(emptyMap())

        /** Files made by hand, kept in memory (tests). */
        fun of(files: Map<String, ByteArray>): ArchiveFiles =
            ArchiveFiles(files.mapValues { Content.Kept(MemoryFile(it.value)) })
    }
}

/** Everything an archive holds, decoded and checked, as the iOS app's `DossierV3.Package`. */
data class DossierPackage(
    val manifest: Manifest,
    val templates: List<TemplateRecord>,
    val assets: List<AssetRecord>,
    val obligations: List<ObligationRecord>,
    val historyEntries: List<HistoryEntryRecord>,
    val serviceItems: List<ServiceItemRecord>,
    val providers: List<ProviderRecord>,
    val measurements: List<MeasurementRecord>,
    val attachments: List<AttachmentRecord>,
    /** None in archives from before database version 16. */
    val issuerLessons: List<IssuerLessonRecord> = emptyList(),
    /** The documents' and photos' files by archive path. */
    val files: ArchiveFiles,
)

/** SHA-256 as the archive writes it: lowercase hex. */
object Digests {
    fun sha256(bytes: ByteArray): String = MachineText.hex(MessageDigest.getInstance("SHA-256").digest(bytes))

    /** A digest that reads a file a piece at a time. */
    fun hasher(): MessageDigest = MessageDigest.getInstance("SHA-256")
}
