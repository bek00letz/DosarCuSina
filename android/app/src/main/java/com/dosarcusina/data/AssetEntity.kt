package com.dosarcusina.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * 1:1 parity with iOS Asset.swift SwiftData model.
 */
@Entity(tableName = "assets")
data class AssetEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val subtitle: String? = null,
    val categoryRaw: String = "home",
    val iconName: String = "house.fill",
    val accentColorHex: String = "007AFF",
    val currentMetricValue: Double? = null,
    val metricUnit: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    val category: AssetCategory
        get() = AssetCategory.fromRaw(categoryRaw)
}
