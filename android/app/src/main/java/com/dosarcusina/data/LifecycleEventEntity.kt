package com.dosarcusina.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.Calendar
import java.util.UUID
import kotlin.math.abs

/**
 * 1:1 parity with iOS LifecycleEvent.swift SwiftData model.
 */
@Entity(
    tableName = "lifecycle_events",
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
        Index(value = ["dueDate"]),
        Index(value = ["isCompleted"])
    ]
)
data class LifecycleEventEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val assetId: String,
    val title: String,
    val eventDescription: String? = null,
    val dueDate: Long,
    val completedDate: Long? = null,
    val isCompleted: Boolean = false,
    val cost: Double? = null,
    val currency: String = "RON",
    val cadenceDays: Int? = null,
    val cadenceMetricInterval: Double? = null,
    val metricTriggerValue: Double? = null,
    val reminderOffsetDays: List<Int> = listOf(30, 7, 1),
    val createdAt: Long = System.currentTimeMillis(),

    // Policy & Service Provider Expansion
    val provider: String? = null,
    val policyOrContractNumber: String? = null,
    val coverageType: String? = null,
    val bonusMalusClass: String? = null,
    val mileageAtEvent: Double? = null,
    val serviceLocation: String? = null
) {
    val daysRemaining: Int
        get() {
            val nowCal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val dueCal = Calendar.getInstance().apply {
                timeInMillis = dueDate
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val diffMillis = dueCal.timeInMillis - nowCal.timeInMillis
            return (diffMillis / (1000 * 60 * 60 * 24)).toInt()
        }

    val isOverdue: Boolean
        get() = !isCompleted && daysRemaining < 0

    val isUrgent: Boolean
        get() = !isCompleted && daysRemaining in 0..7

    val statusBadgeText: String
        get() {
            return when {
                isCompleted -> "Rezolvat"
                daysRemaining < 0 -> "Expirat de ${abs(daysRemaining)}z"
                daysRemaining == 0 -> "Azi"
                daysRemaining == 1 -> "Mâine"
                else -> "$daysRemaining zile rămase"
            }
        }
}
