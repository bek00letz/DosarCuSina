package com.ar.dosarcusina.store.schema

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

/**
 * One reading over time: a meter index, a lab value, a weight, an odometer, as the iOS app's
 * `MeasurementLog` (ios/DosarCuSina/Models/Schema/RecordModels.swift).
 */
@Entity(
    tableName = "MeasurementLog",
    foreignKeys = [
        ForeignKey(Asset::class, ["pk"], ["asset"], onDelete = ForeignKey.SET_NULL, deferred = true),
    ],
    indices = [Index("id"), Index("asset"), Index("assetID")],
)
data class MeasurementLog(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = "'custom'") val kindRaw: String = "custom",
    @ColumnInfo(defaultValue = Defaults.EMPTY) val name: String = "",
    @ColumnInfo(defaultValue = Defaults.ZERO) val value: Double = 0.0,
    val secondaryValue: Double? = null,
    /** A unit key (`MeasurementUnit`), or "" for none. */
    @ColumnInfo(defaultValue = Defaults.EMPTY) val unit: String = "",
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val recordedAt: Instant = StoredMoment.now(),
    val unitPriceAmount: BigDecimal? = null,
    val unitPriceCurrency: String? = null,
    @ColumnInfo(defaultValue = Defaults.TRUE) val isSelfRead: Boolean = true,
    val referenceMin: Double? = null,
    val referenceMax: Double? = null,
    val source: String? = null,
    val notes: String? = null,
    @ColumnInfo(defaultValue = Defaults.FALSE) val isExample: Boolean = false,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
    /** Whether a new counter starts here (a replaced meter, one that went round). */
    @ColumnInfo(defaultValue = Defaults.FALSE) val startsCounter: Boolean = false,
    /** Whether it was read off the counter or estimated (`ReadingBasis`); none when not said. */
    val basisRaw: String? = null,
    /** The section it is in. */
    val asset: Long? = null,
    /** The id of the section it is in, stamped from [asset] by every save. */
    val assetID: UUID? = null,
)

/**
 * A document: a file, its scanned pages, what was read from it, as the iOS app's `Attachment`.
 * The original and the thumbnail are kept beside the database, by digest ([fileData],
 * [thumbnailData]); its pages are [AttachmentPage]s.
 */
@Entity(
    tableName = "Attachment",
    foreignKeys = [
        ForeignKey(Attachment::class, ["pk"], ["supersededBy"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(Asset::class, ["pk"], ["asset"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(Obligation::class, ["pk"], ["obligation"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(HistoryEntry::class, ["pk"], ["historyEntry"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(ServiceItem::class, ["pk"], ["serviceItem"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(MeasurementLog::class, ["pk"], ["measurement"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(Provider::class, ["pk"], ["provider"], onDelete = ForeignKey.SET_NULL, deferred = true),
    ],
    indices = [
        Index("id"), Index("supersededBy"), Index("asset"), Index("assetID"), Index("obligation"),
        Index("historyEntry"), Index("serviceItem"), Index("measurement"), Index("provider"), Index("sha256"),
    ],
)
data class Attachment(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    val title: String? = null,
    @ColumnInfo(defaultValue = Defaults.EMPTY) val fileName: String = "",
    @ColumnInfo(defaultValue = "'other'") val kindRaw: String = "other",
    /** Uniform type identifier of the original file, such as `com.adobe.pdf`. */
    @ColumnInfo(defaultValue = "'public.data'") val contentType: String = "public.data",
    /** The digest of the original file, kept beside the database. */
    val fileData: String? = null,
    /** The digest of the small preview image, kept beside the database. */
    val thumbnailData: String? = null,
    @ColumnInfo(defaultValue = Defaults.ZERO) val byteCount: Long = 0,
    /** Lowercase hex SHA-256 of the original, or of the pages in order when there is none. */
    val sha256: String? = null,
    val extractedText: String? = null,
    /** The day printed on the document, as an ISO day. */
    val documentDayISO: String? = null,
    /** The last day the document itself is valid, as an ISO day. */
    val validUntilISO: String? = null,
    /** The source document in capture's store on this phone; never in a backup. */
    val documentID: String? = null,
    @ColumnInfo(defaultValue = Defaults.FALSE) val isArchived: Boolean = false,
    /** When this phone made its pages smaller; never in a backup. */
    val compactedAt: Instant? = null,
    /** JSON `DocumentFraming`, read and written through `keptFraming`. */
    val framingData: String? = null,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val createdAt: Instant = StoredMoment.now(),
    @ColumnInfo(defaultValue = Defaults.FALSE) val isExample: Boolean = false,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
    /** The document that replaced this one. */
    val supersededBy: Long? = null,
    /** The section it is in. */
    val asset: Long? = null,
    /** The id of the section it is in, stamped from [asset] by every save. */
    val assetID: UUID? = null,
    val obligation: Long? = null,
    val historyEntry: Long? = null,
    val serviceItem: Long? = null,
    val measurement: Long? = null,
    val provider: Long? = null,
)

/** One scanned page of a document, as the iOS app's `AttachmentPage`; its picture kept beside the database. */
@Entity(
    tableName = "AttachmentPage",
    foreignKeys = [
        ForeignKey(Attachment::class, ["pk"], ["attachment"], onDelete = ForeignKey.SET_NULL, deferred = true),
    ],
    indices = [Index("id"), Index("attachment"), Index("attachmentID")],
)
data class AttachmentPage(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    /** Zero-based position in the document. */
    @ColumnInfo(defaultValue = Defaults.ZERO) val index: Int = 0,
    /** The digest of the page's picture, kept beside the database. */
    val imageData: String? = null,
    /** The document it is a page of. */
    val attachment: Long? = null,
    /** The id of the document it is in, stamped from [attachment] by every save. */
    val attachmentID: UUID? = null,
)
