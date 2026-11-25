package com.dosarcusina.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * 1:1 Parity with iOS SwiftData MeasurementLog.swift model.
 * Records quantitative time-series telemetry (utility meters, biomarkers, vitals, pet weights, odometer).
 */
@Entity(
    tableName = "measurement_logs",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["assetId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["assetId"]),
        Index(value = ["recordedAt"])
    ]
)
data class MeasurementLogEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val assetId: String,
    val domainRawValue: String,
    val metricName: String,
    val value: Double,
    val secondaryValue: Double? = null,
    val unit: String,
    val recordedAt: Long = System.currentTimeMillis(),
    val previousValue: Double? = null,
    val unitPrice: Double? = null,
    val isSelfRead: Boolean = true,
    val referenceMin: Double? = null,
    val referenceMax: Double? = null,
    val labOrProviderName: String? = null,
    val notes: String? = null,
    val createdAt: Long = System.currentTimeMillis()
) {
    val deltaFromPrevious: Double?
        get() = previousValue?.let { value - it }

    val estimatedCost: Double?
        get() = deltaFromPrevious?.let { delta ->
            if (delta > 0 && unitPrice != null) delta * unitPrice else null
        }

    val isOutOfRange: Boolean
        get() = (referenceMin != null && value < referenceMin) ||
                (referenceMax != null && value > referenceMax)
}
