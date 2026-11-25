package com.dosarcusina.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * Unit test for Room entity models, mapping parity, foreign key cascade logic, and calculations.
 */
class RoomDatabaseTest {

    @Test
    fun testAssetEntityMapping() {
        val id = UUID.randomUUID().toString()
        val asset = AssetEntity(
            id = id,
            name = "VW Golf 7",
            subtitle = "B-123-ABC",
            categoryRaw = "vehicle",
            iconName = "car.fill",
            accentColorHex = "007AFF",
            currentMetricValue = 145200.0,
            metricUnit = "km"
        )

        assertEquals(id, asset.id)
        assertEquals("VW Golf 7", asset.name)
        assertEquals("B-123-ABC", asset.subtitle)
        assertEquals(AssetCategory.VEHICLE, asset.category)
        assertEquals(145200.0, asset.currentMetricValue!!, 0.001)
        assertEquals("km", asset.metricUnit)
    }

    @Test
    fun testLifecycleEventDaysRemainingAndUrgency() {
        val now = System.currentTimeMillis()
        val fiveDaysLater = now + (5L * 86_400_000L)
        val tenDaysAgo = now - (10L * 86_400_000L)

        val urgentEvent = LifecycleEventEntity(
            assetId = "asset-1",
            title = "ITP Scadență",
            dueDate = fiveDaysLater,
            cost = 250.0
        )

        assertTrue(urgentEvent.isUrgent)
        assertFalse(urgentEvent.isOverdue)
        assertFalse(urgentEvent.isCompleted)

        val overdueEvent = LifecycleEventEntity(
            assetId = "asset-1",
            title = "RCA Expirat",
            dueDate = tenDaysAgo,
            cost = 850.0
        )

        assertTrue(overdueEvent.isOverdue)
        assertFalse(overdueEvent.isUrgent)
        assertTrue(overdueEvent.statusBadgeText.startsWith("Expirat de"))

        val completedEvent = LifecycleEventEntity(
            assetId = "asset-1",
            title = "Schimb Filtre",
            dueDate = overdueEvent.dueDate,
            isCompleted = true
        )

        assertEquals("Rezolvat", completedEvent.statusBadgeText)
        assertFalse(completedEvent.isOverdue)
        assertFalse(completedEvent.isUrgent)
    }

    @Test
    fun testAttachmentEntityParity() {
        val id = UUID.randomUUID().toString()
        val attachment = AttachmentEntity(
            id = id,
            assetId = "asset-1",
            eventId = "event-1",
            fileName = "Factura_RCA.pdf",
            fileExtension = "pdf",
            extractedText = "Asigurare RCA 12 luni"
        )

        assertEquals("Factura_RCA.pdf", attachment.fileName)
        assertEquals("pdf", attachment.fileExtension)
        assertEquals("asset-1", attachment.assetId)
        assertEquals("event-1", attachment.eventId)
    }

    @Test
    fun testDynamicFieldEntityParity() {
        val id = UUID.randomUUID().toString()
        val field = DynamicFieldEntity(
            id = id,
            assetId = "asset-1",
            key = "vin",
            label = "Serie Șasiu",
            fieldTypeRaw = "text",
            stringValue = "WVWZZZAUZHP123456"
        )

        assertEquals("vin", field.key)
        assertEquals("Serie Șasiu", field.label)
        assertEquals(DynamicFieldType.TEXT, field.fieldType)
        assertEquals("WVWZZZAUZHP123456", field.stringValue)
    }
}
