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
    val updatedAt: Long = System.currentTimeMillis(),

    // Vehicle Specialized Attributes
    val licensePlate: String? = null,
    val vinNumber: String? = null,
    val manufactureYear: Int? = null,
    val fuelType: String? = null,
    val engineDisplacementCm3: Int? = null,
    val enginePowerHp: Int? = null,

    // Home Specialized Attributes
    val fullAddress: String? = null,
    val surfaceAreaM2: Double? = null,
    val constructionYear: Int? = null,
    val heatingBoilerModel: String? = null,
    val heatingBoilerSerial: String? = null,
    val gasMeterSerial: String? = null,
    val electricityMeterSerial: String? = null,
    val waterMeterSerial: String? = null,

    // Pet Specialized Attributes
    val petSpecies: String? = null,
    val petBreed: String? = null,
    val petMicrochipNumber: String? = null,
    val petBirthDate: Long? = null,
    val veterinarianClinic: String? = null,
    val veterinarianPhone: String? = null,

    // Health Specialized Attributes
    val bloodType: String? = null,
    val familyDoctorName: String? = null,
    val familyDoctorPhone: String? = null,
    val emergencyContactName: String? = null,
    val emergencyContactPhone: String? = null,
    val allergiesNotes: String? = null
) {
    val category: AssetCategory
        get() = AssetCategory.fromRaw(categoryRaw)
}
