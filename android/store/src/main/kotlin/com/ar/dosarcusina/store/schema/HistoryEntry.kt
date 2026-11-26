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
 * Something that happened to a section: a visit, a repair, a purchase, a deadline closed, as the
 * iOS app's `HistoryEntry` (ios/DosarCuSina/Models/Schema/HistoryModel.swift). Who did the work
 * is a link kept on this side ([HistoryEntryProviders]).
 */
@Entity(
    tableName = "HistoryEntry",
    foreignKeys = [
        ForeignKey(Asset::class, ["pk"], ["asset"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(Obligation::class, ["pk"], ["obligation"], onDelete = ForeignKey.SET_NULL, deferred = true),
    ],
    indices = [Index("id"), Index("asset"), Index("assetID"), Index("obligation")],
)
data class HistoryEntry(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = "'note'") val kindRaw: String = "note",
    @ColumnInfo(defaultValue = Defaults.EMPTY) val title: String = "",
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val occurredAt: Instant = StoredMoment.now(),
    val metricReading: Double? = null,
    val totalCostAmount: BigDecimal? = null,
    val totalCostCurrency: String? = null,
    val note: String? = null,
    /** The number of the paper it records, as printed. */
    val reference: String? = null,
    val rating: Int? = null,
    @ColumnInfo(defaultValue = Defaults.FALSE) val isExample: Boolean = false,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
    /** The due day of the cycle it closed, as an ISO day. */
    val cycleDueDayISO: String? = null,
    /** The due day the deadline moved to, as an ISO day. */
    val nextDueDayISO: String? = null,
    val previousStatusRaw: String? = null,
    val previousDueMetric: Double? = null,
    /** The section it is in. */
    val asset: Long? = null,
    /** The id of the section it is in, stamped from [asset] by every save. */
    val assetID: UUID? = null,
    /** The deadline it closed. */
    val obligation: Long? = null,
)

/**
 * A part or a job of a record of history, as the iOS app's `ServiceItem`
 * (ios/DosarCuSina/Models/Schema/RecordModels.swift). Its three amounts share one currency.
 */
@Entity(
    tableName = "ServiceItem",
    foreignKeys = [
        ForeignKey(Provider::class, ["pk"], ["supplier"], onDelete = ForeignKey.SET_NULL, deferred = true),
        ForeignKey(HistoryEntry::class, ["pk"], ["entry"], onDelete = ForeignKey.SET_NULL, deferred = true),
    ],
    indices = [Index("id"), Index("supplier"), Index("entry"), Index("entryID")],
)
data class ServiceItem(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = Defaults.EMPTY) val name: String = "",
    val componentKey: String? = null,
    val group: String? = null,
    val partBrandOrCode: String? = null,
    val partSerialNumber: String? = null,
    val costAmount: BigDecimal? = null,
    val laborCostAmount: BigDecimal? = null,
    val partsCostAmount: BigDecimal? = null,
    @ColumnInfo(defaultValue = Defaults.CURRENCY) val currency: String = "RON",
    /** Who supplied the part, when different from who fitted it. */
    val supplier: Long? = null,
    val batchOrTicket: String? = null,
    val locationDetail: String? = null,
    val daysInService: Int? = null,
    val warrantyMonths: Int? = null,
    val notes: String? = null,
    @ColumnInfo(defaultValue = Defaults.FALSE) val isExample: Boolean = false,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
    /** The record of history it is in. */
    val entry: Long? = null,
    /** The id of the record of history it is in, stamped from [entry] by every save. */
    val entryID: UUID? = null,
)
