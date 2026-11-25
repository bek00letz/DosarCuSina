package com.dosarcusina.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * 1:1 parity with iOS DocumentAttachment.swift SwiftData model.
 */
@Entity(
    tableName = "attachments",
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
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["assetId"]),
        Index(value = ["eventId"])
    ]
)
data class AttachmentEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val assetId: String? = null,
    val eventId: String? = null,
    val fileName: String,
    val fileExtension: String,
    val filePath: String? = null,
    val extractedText: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)
