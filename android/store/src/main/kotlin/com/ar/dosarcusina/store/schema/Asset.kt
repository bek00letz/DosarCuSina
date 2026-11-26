package com.ar.dosarcusina.store.schema

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey
import java.time.Instant
import java.util.UUID

/**
 * Something the household looks after: a car, a home, a pet, a passport, as the iOS app's
 * `Asset` (ios/DosarCuSina/Models/Schema/AssetModel.swift). Its details live in [valuesData],
 * described by the category named in [templateKey].
 *
 * Every model of the store keeps the iOS model's stored properties under the same names, in their
 * stored form ([StoredForms]), and nothing else but [pk]:
 * - [pk] is the row, as the iOS store's own key: a record's [id] is not unique, since the same
 *   record may come as two copies (its [copyID] tells them apart, `RecordsMeet` joins them);
 * - a link to one record (`parent`) is that record's row, which lets go when the row goes
 *   (`ON DELETE SET NULL`, the iOS models' `.nullify`): no link deletes what it points at, and
 *   what a record holds goes with it only through [com.ar.dosarcusina.store.RecordContents];
 * - a list of the records that point at this one (its deadlines, its documents) is no column:
 *   it is their link;
 * - a link to many records kept on this side (a firm's sections) is a table of its own
 *   ([ProviderAssets], [HistoryEntryProviders]).
 */
@Entity(
    tableName = "Asset",
    foreignKeys = [
        ForeignKey(Asset::class, ["pk"], ["parent"], onDelete = ForeignKey.SET_NULL, deferred = true),
    ],
    indices = [Index("id"), Index("parent"), Index("templateKey")],
)
data class Asset(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    /** Which copy of the record this is, given by the device that made it; never in a backup. */
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = Defaults.EMPTY) val name: String = "",
    /** `CategoryTemplate.key`. */
    @ColumnInfo(defaultValue = Defaults.EMPTY) val templateKey: String = "",
    val symbolOverride: String? = null,
    val tintOverrideRaw: String? = null,
    val notes: String? = null,
    /** The digest of the section's photo, kept beside the database. */
    val photoData: String? = null,
    /** JSON `FieldValues`, read and written through `keptValues`. */
    val valuesData: String? = null,
    /** JSON `[CustomFact]`: free rows under Date importante, read and written through `keptFacts`. */
    val customFactsData: String? = null,
    @ColumnInfo(defaultValue = Defaults.FALSE) val isExample: Boolean = false,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val createdAt: Instant = StoredMoment.now(),
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
    /** The section this one is filed under: a tenancy under its property, a document under its holder. */
    val parent: Long? = null,
)
