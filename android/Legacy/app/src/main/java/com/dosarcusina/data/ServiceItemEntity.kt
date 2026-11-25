package com.dosarcusina.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * 1:1 parity with iOS ServiceItem.swift SwiftData model.
 * Records individual maintenance components replaced (e.g., brake pads, oil, filters).
 */
@Entity(
    tableName = "service_items",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["assetId"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = LifecycleEventEntity::class,
            parentColumns = ["id"],
            childColumns = ["eventId"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [
        Index(value = ["assetId"]),
        Index(value = ["eventId"])
    ]
)
data class ServiceItemEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val assetId: String,
    val eventId: String? = null,
    val componentName: String,
    val componentCategory: String = "general",
    val partBrand: String? = null,
    val partSerialNumber: String? = null,
    val cost: Double? = null,
    val serviceDate: Long = System.currentTimeMillis(),
    val mileageAtService: Double? = null,
    val notes: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)
