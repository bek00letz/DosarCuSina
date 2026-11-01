package com.dosarcusina.data

import androidx.room.Embedded
import androidx.room.Relation

/**
 * Composite model containing an asset and all its lifecycle events.
 */
data class AssetWithEvents(
    @Embedded
    val asset: AssetEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "assetId"
    )
    val events: List<LifecycleEventEntity> = emptyList()
)

/**
 * Composite model containing an asset with events, attachments, and dynamic fields.
 */
data class AssetWithDetails(
    @Embedded
    val asset: AssetEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "assetId"
    )
    val events: List<LifecycleEventEntity> = emptyList(),
    @Relation(
        parentColumn = "id",
        entityColumn = "assetId"
    )
    val attachments: List<AttachmentEntity> = emptyList(),
    @Relation(
        parentColumn = "id",
        entityColumn = "assetId"
    )
    val dynamicFields: List<DynamicFieldEntity> = emptyList(),
    @Relation(
        parentColumn = "id",
        entityColumn = "assetId"
    )
    val serviceItems: List<ServiceItemEntity> = emptyList(),
    @Relation(
        parentColumn = "id",
        entityColumn = "assetId"
    )
    val measurements: List<MeasurementLogEntity> = emptyList()
)

/**
 * Composite model representing an event joined with its parent asset.
 */
data class EventWithAsset(
    @Embedded
    val event: LifecycleEventEntity,
    @Relation(
        parentColumn = "assetId",
        entityColumn = "id"
    )
    val asset: AssetEntity? = null
)
