package com.ar.dosarcusina.store.schema

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey
import java.time.Instant
import java.util.UUID

/**
 * A person or firm who looks after something, as the iOS app's `Provider`
 * (ios/DosarCuSina/Models/Schema/ProviderModel.swift). The sections it looks after are a link
 * kept on this side ([ProviderAssets]).
 */
@Entity(tableName = "Provider", indices = [Index("id"), Index("taxID")])
data class Provider(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = Defaults.EMPTY) val name: String = "",
    /** `ProviderTrade` keys. */
    @ColumnInfo(defaultValue = Defaults.NO_WORDS) val trades: List<String> = emptyList(),
    val phone: String? = null,
    val email: String? = null,
    val address: String? = null,
    val notes: String? = null,
    val manualRating: Int? = null,
    val wouldCallAgain: Boolean? = null,
    /** The card in this phone's contacts; never in a backup. */
    val contactIdentifier: String? = null,
    val taxID: String? = null,
    @ColumnInfo(defaultValue = Defaults.FALSE) val isExample: Boolean = false,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val createdAt: Instant = StoredMoment.now(),
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
)

/**
 * What capture learned of an issuer's papers: the label it prints a value under, as the iOS
 * app's `IssuerLesson` (ios/DosarCuSina/Models/Schema/IssuerLessonModel.swift).
 */
@Entity(tableName = "IssuerLesson", indices = [Index("id"), Index("issuerKey")])
data class IssuerLesson(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = Defaults.EMPTY) val issuerKey: String = "",
    @ColumnInfo(defaultValue = Defaults.EMPTY) val issuerName: String = "",
    @ColumnInfo(defaultValue = Defaults.EMPTY) val kindRaw: String = "",
    @ColumnInfo(defaultValue = Defaults.EMPTY) val fieldKey: String = "",
    @ColumnInfo(defaultValue = Defaults.EMPTY) val label: String = "",
    /** The category of the section its paper was filed in; none when not known. */
    val categoryKey: String? = null,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val createdAt: Instant = StoredMoment.now(),
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
)

/**
 * The sections a firm looks after: `Provider.assets` on iOS, the side of the link the firm keeps
 * (a change to it is the firm's). One row per link; each lets its row go only through the store's
 * one way of deleting ([com.ar.dosarcusina.store.RecordContents]), which the deferred check enforces.
 */
@Entity(
    tableName = "Provider_assets",
    foreignKeys = [
        ForeignKey(Provider::class, ["pk"], ["provider"], deferred = true),
        ForeignKey(Asset::class, ["pk"], ["asset"], deferred = true),
    ],
    indices = [Index("provider"), Index("asset")],
)
data class ProviderAssets(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val provider: Long? = null,
    val asset: Long? = null,
)

/** Who did the work of a record of history: `HistoryEntry.providers` on iOS, the side the record keeps. */
@Entity(
    tableName = "HistoryEntry_providers",
    foreignKeys = [
        ForeignKey(HistoryEntry::class, ["pk"], ["historyEntry"], deferred = true),
        ForeignKey(Provider::class, ["pk"], ["provider"], deferred = true),
    ],
    indices = [Index("historyEntry"), Index("provider")],
)
data class HistoryEntryProviders(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val historyEntry: Long? = null,
    val provider: Long? = null,
)
