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
 * Something that has to be done by a date, once or on a schedule, as the iOS app's `Obligation`
 * (ios/DosarCuSina/Models/Schema/ObligationModel.swift). Its reminders are kept flat, as there:
 * the columns this build reads, and [remindersData] for what a newer build wrote beside them
 * (read and written together through `keptReminders`).
 */
@Entity(
    tableName = "Obligation",
    foreignKeys = [
        ForeignKey(Asset::class, ["pk"], ["asset"], onDelete = ForeignKey.SET_NULL, deferred = true),
    ],
    indices = [Index("id"), Index("asset"), Index("assetID"), Index("dueDayISO")],
)
data class Obligation(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    val id: UUID = UUID.randomUUID(),
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = Defaults.EMPTY) val title: String = "",
    val notes: String? = null,
    val blueprintKey: String? = null,
    @ColumnInfo(defaultValue = "'routine'") val kindRaw: String = "routine",
    /** The due day as an ISO day (`StoredDay`), read and written through `dueDay`. */
    @ColumnInfo(defaultValue = Defaults.EMPTY) val dueDayISO: String = "",
    val dueMetric: Double? = null,
    @ColumnInfo(defaultValue = DEFAULT_LEADS) val reminderLeadDays: List<Int> = DefaultLeadDays,
    @ColumnInfo(defaultValue = "'comfort'") val consequenceRaw: String = "comfort",
    @ColumnInfo(defaultValue = Defaults.ZERO) val graceDays: Int = 0,
    @ColumnInfo(defaultValue = Defaults.FALSE) val followUpAfterLapse: Boolean = false,
    @ColumnInfo(defaultValue = Defaults.ZERO) val travelMarginDays: Int = 0,
    @ColumnInfo(defaultValue = Defaults.FALSE) val remindersCustomized: Boolean = false,
    val reminderMinuteOfDay: Int? = null,
    /** JSON `RecurrenceRule`, read and written through `keptRecurrence`. */
    val recurrenceData: String? = null,
    val estimatedCostAmount: BigDecimal? = null,
    val estimatedCostCurrency: String? = null,
    val provider: String? = null,
    val reference: String? = null,
    @ColumnInfo(defaultValue = "'active'") val statusRaw: String = "active",
    /** The day a snooze ends, as an ISO day. */
    val snoozedUntilISO: String? = null,
    @ColumnInfo(defaultValue = Defaults.FALSE) val isExample: Boolean = false,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val createdAt: Instant = StoredMoment.now(),
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
    /** Since when its cycle is known as it now is (`CycleTimes`); stays on the phone. */
    val cycleKnownAt: Instant? = null,
    /** The reminder profile's JSON as a newer build wrote it, only while it holds more than the columns. */
    val remindersData: String? = null,
    /** The section it is in. */
    val asset: Long? = null,
    /** The id of the section it is in, stamped from [asset] by every save (`ParentLinks.stamp`). */
    val assetID: UUID? = null,
) {
    companion object {
        /** [DefaultLeadDays] as the column's SQL default writes them. */
        const val DEFAULT_LEADS = "'[30,7,0]'"

        /** The iOS model's leads when nothing says otherwise: a month, a week and the day. */
        val DefaultLeadDays: List<Int> = listOf(30, 7, 0)
    }
}
