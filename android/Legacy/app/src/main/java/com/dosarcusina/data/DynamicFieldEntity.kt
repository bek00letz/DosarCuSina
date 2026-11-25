package com.dosarcusina.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * 1:1 parity with iOS DynamicFieldType
 */
enum class DynamicFieldType(val rawValue: String) {
    TEXT("text"),
    NUMBER("number"),
    DATE("date"),
    BOOLEAN("boolean"),
    CURRENCY("currency");

    companion object {
        fun fromRaw(raw: String?): DynamicFieldType {
            if (raw == null) return TEXT
            return entries.firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: TEXT
        }
    }
}

/**
 * 1:1 parity with iOS DynamicField.swift SwiftData model.
 */
@Entity(
    tableName = "dynamic_fields",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["assetId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["assetId"])
    ]
)
data class DynamicFieldEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val assetId: String,
    val key: String,
    val label: String,
    val fieldTypeRaw: String = "text",
    val stringValue: String? = null,
    val numberValue: Double? = null,
    val dateValue: Long? = null,
    val boolValue: Boolean? = null
) {
    val fieldType: DynamicFieldType
        get() = DynamicFieldType.fromRaw(fieldTypeRaw)
}
