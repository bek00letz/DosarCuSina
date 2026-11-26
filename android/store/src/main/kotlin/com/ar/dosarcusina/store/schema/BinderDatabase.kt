package com.ar.dosarcusina.store.schema

import androidx.room3.ColumnTypeConverters
import androidx.room3.Dao
import androidx.room3.Database
import androidx.room3.Delete
import androidx.room3.Insert
import androidx.room3.Query
import androidx.room3.RoomDatabase
import androidx.room3.Update

/**
 * The household database, in the shape of the iOS app's models at their database version 19
 * (ios/DosarCuSina/Models/Schema/DosarSchema.swift): one table per model, under the model's name,
 * one column per stored property, under the property's name (`StoreShapeTest` pins it), and a
 * table for each link to many a model keeps itself.
 *
 * Its versions are its own, from 1, the shape of iOS version 19. A change to what is stored is a
 * new version: Room's schema of it committed in `store/schemas/` beside every earlier one, a
 * migration from the one before, and a test that opens a database of each earlier version
 * (`StoreVersionsTest`). As on iOS, every column is optional or defaulted, nothing is unique and no
 * link deletes what it points at (`ON DELETE SET NULL`, never `CASCADE`).
 *
 * Nothing but the unit of work writes through its DAOs ([com.ar.dosarcusina.store.UnitOfWork]):
 * every step, an import's included, saves through it, once, in one transaction.
 */
@Database(
    entities = [
        CategoryTemplate::class,
        Asset::class,
        Obligation::class,
        HistoryEntry::class,
        ServiceItem::class,
        MeasurementLog::class,
        Attachment::class,
        AttachmentPage::class,
        Provider::class,
        IssuerLesson::class,
        ProviderAssets::class,
        HistoryEntryProviders::class,
    ],
    version = BinderDatabase.VERSION,
    exportSchema = true,
)
@ColumnTypeConverters(StoredForms::class)
// One DAO per table.
@Suppress("TooManyFunctions")
abstract class BinderDatabase : RoomDatabase() {
    abstract fun templates(): TemplateRows

    abstract fun assets(): AssetRows

    abstract fun obligations(): ObligationRows

    abstract fun history(): HistoryRows

    abstract fun items(): ServiceItemRows

    abstract fun readings(): MeasurementRows

    abstract fun attachments(): AttachmentRows

    abstract fun pages(): PageRows

    abstract fun providers(): ProviderRows

    abstract fun lessons(): LessonRows

    abstract fun providerAssets(): ProviderAssetRows

    abstract fun entryProviders(): EntryProviderRows

    abstract fun files(): FileDigests

    companion object {
        /** The database's version now: the shape of the iOS app's version 19. */
        const val VERSION = 1
    }
}

/** Writing one table's rows. */
interface Rows<T> {
    @Insert
    suspend fun insert(row: T): Long

    @Update
    suspend fun update(row: T)

    @Delete
    suspend fun delete(row: T)
}

@Dao
interface TemplateRows : Rows<CategoryTemplate> {
    @Query("SELECT * FROM CategoryTemplate ORDER BY pk")
    suspend fun all(): List<CategoryTemplate>
}

@Dao
interface AssetRows : Rows<Asset> {
    @Query("SELECT * FROM Asset ORDER BY pk")
    suspend fun all(): List<Asset>

    /** The category every section names: what the binder's locks are asked for (`BinderLocks`). */
    @Query("SELECT templateKey FROM Asset")
    suspend fun templateKeys(): List<String>
}

@Dao
interface ObligationRows : Rows<Obligation> {
    @Query("SELECT * FROM Obligation ORDER BY pk")
    suspend fun all(): List<Obligation>

    @Query("SELECT * FROM Obligation WHERE asset = :asset ORDER BY pk")
    suspend fun ofAsset(asset: Long): List<Obligation>
}

@Dao
interface HistoryRows : Rows<HistoryEntry> {
    @Query("SELECT * FROM HistoryEntry ORDER BY pk")
    suspend fun all(): List<HistoryEntry>

    @Query("SELECT * FROM HistoryEntry WHERE asset = :asset ORDER BY pk")
    suspend fun ofAsset(asset: Long): List<HistoryEntry>
}

@Dao
interface ServiceItemRows : Rows<ServiceItem> {
    @Query("SELECT * FROM ServiceItem ORDER BY pk")
    suspend fun all(): List<ServiceItem>

    @Query("SELECT * FROM ServiceItem WHERE entry = :entry ORDER BY pk")
    suspend fun ofEntry(entry: Long): List<ServiceItem>
}

@Dao
interface MeasurementRows : Rows<MeasurementLog> {
    @Query("SELECT * FROM MeasurementLog ORDER BY pk")
    suspend fun all(): List<MeasurementLog>

    @Query("SELECT * FROM MeasurementLog WHERE asset = :asset ORDER BY pk")
    suspend fun ofAsset(asset: Long): List<MeasurementLog>
}

@Dao
interface AttachmentRows : Rows<Attachment> {
    @Query("SELECT * FROM Attachment ORDER BY pk")
    suspend fun all(): List<Attachment>

    @Query("SELECT * FROM Attachment WHERE asset = :asset ORDER BY pk")
    suspend fun ofAsset(asset: Long): List<Attachment>
}

@Dao
interface PageRows : Rows<AttachmentPage> {
    @Query("SELECT * FROM AttachmentPage ORDER BY attachment, `index`, pk")
    suspend fun all(): List<AttachmentPage>

    @Query("SELECT * FROM AttachmentPage WHERE attachment = :attachment ORDER BY `index`, pk")
    suspend fun ofAttachment(attachment: Long): List<AttachmentPage>
}

@Dao
interface ProviderRows : Rows<Provider> {
    @Query("SELECT * FROM Provider ORDER BY pk")
    suspend fun all(): List<Provider>
}

@Dao
interface LessonRows : Rows<IssuerLesson> {
    @Query("SELECT * FROM IssuerLesson ORDER BY pk")
    suspend fun all(): List<IssuerLesson>
}

@Dao
interface ProviderAssetRows {
    @Insert
    suspend fun insert(row: ProviderAssets): Long

    @Query("SELECT * FROM Provider_assets ORDER BY pk")
    suspend fun all(): List<ProviderAssets>

    @Query("DELETE FROM Provider_assets WHERE provider = :provider")
    suspend fun deleteOfProvider(provider: Long)

    @Query("DELETE FROM Provider_assets WHERE asset = :asset")
    suspend fun deleteOfAsset(asset: Long)
}

@Dao
interface EntryProviderRows {
    @Insert
    suspend fun insert(row: HistoryEntryProviders): Long

    @Query("SELECT * FROM HistoryEntry_providers ORDER BY pk")
    suspend fun all(): List<HistoryEntryProviders>

    @Query("DELETE FROM HistoryEntry_providers WHERE historyEntry = :entry")
    suspend fun deleteOfEntry(entry: Long)

    @Query("DELETE FROM HistoryEntry_providers WHERE provider = :provider")
    suspend fun deleteOfProvider(provider: Long)
}

/** The files the database names, by digest: what the files beside it must keep. */
@Dao
interface FileDigests {
    @Query(
        "SELECT photoData FROM Asset WHERE photoData IS NOT NULL " +
            "UNION SELECT fileData FROM Attachment WHERE fileData IS NOT NULL " +
            "UNION SELECT thumbnailData FROM Attachment WHERE thumbnailData IS NOT NULL " +
            "UNION SELECT imageData FROM AttachmentPage WHERE imageData IS NOT NULL",
    )
    suspend fun named(): List<String>
}
