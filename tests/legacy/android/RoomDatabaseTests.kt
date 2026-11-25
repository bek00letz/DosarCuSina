package com.dosarcusina.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.dosarcusina.data.AssetDao
import com.dosarcusina.data.AttachmentDao
import com.dosarcusina.data.Converters
import com.dosarcusina.data.DosarDatabase
import com.dosarcusina.data.DynamicFieldDao
import com.dosarcusina.data.EventDao
import com.dosarcusina.data.AssetEntity
import com.dosarcusina.data.AttachmentEntity
import com.dosarcusina.data.DynamicFieldEntity
import com.dosarcusina.data.LifecycleEventEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.IOException
import java.util.UUID

/**
 * Production automated test suite for Android Room SQLite database parity.
 *
 * Verifies:
 * 1. Room Entity CRUD operations for AssetEntity, LifecycleEventEntity, AttachmentEntity, DynamicFieldEntity.
 * 2. SQLite Foreign Key CASCADE deletion: deleting an AssetEntity automatically deletes
 *    associated LifecycleEventEntity, AttachmentEntity, and DynamicFieldEntity rows.
 * 3. Event CASCADE deletion: deleting a LifecycleEventEntity cascades to associated AttachmentEntity rows.
 * 4. TypeConverter round-trip serialization: reminderOffsetDays list to/from comma-separated SQLite string.
 * 5. Cost sum aggregation and event completion toggles.
 */
@RunWith(AndroidJUnit4::class)
class RoomDatabaseTests {

    private lateinit var db: DosarDatabase
    private lateinit var assetDao: AssetDao
    private lateinit var eventDao: EventDao
    private lateinit var attachmentDao: AttachmentDao
    private lateinit var dynamicFieldDao: DynamicFieldDao
    private val converters = Converters()

    @Before
    fun createDb() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, DosarDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        assetDao = db.assetDao()
        eventDao = db.eventDao()
        attachmentDao = db.attachmentDao()
        dynamicFieldDao = db.dynamicFieldDao()
    }

    @After
    @Throws(IOException::class)
    fun closeDb() {
        db.close()
    }

    // MARK: - 1. Entity CRUD Operations

    @Test
    fun testAssetEntityCrud() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        val asset = AssetEntity(
            id = assetId,
            name = "Apartament 4 Camere",
            subtitle = "Str. Aviației nr. 12",
            categoryRaw = "home",
            iconName = "house.fill",
            accentColorHex = "FF9500",
            currentMetricValue = 120.0,
            metricUnit = "mp"
        )

        // Insert & Read
        assetDao.insertAsset(asset)
        val fetched = assetDao.getAssetById(assetId).first()
        assertNotNull("Asset must be found by ID", fetched)
        assertEquals("Apartament 4 Camere", fetched?.name)
        assertEquals("Str. Aviației nr. 12", fetched?.subtitle)
        assertEquals("home", fetched?.categoryRaw)
        assertEquals(120.0, fetched?.currentMetricValue ?: 0.0, 0.001)
        assertEquals("mp", fetched?.metricUnit)

        // Update
        val updated = asset.copy(name = "Vila Snagov", currentMetricValue = 250.0)
        assetDao.updateAsset(updated)
        val fetchedUpdated = assetDao.getAssetById(assetId).first()
        assertEquals("Vila Snagov", fetchedUpdated?.name)
        assertEquals(250.0, fetchedUpdated?.currentMetricValue ?: 0.0, 0.001)

        // Delete
        assetDao.deleteAsset(updated)
        val fetchedDeleted = assetDao.getAssetById(assetId).first()
        assertNull("Asset must be null after deletion", fetchedDeleted)
    }

    @Test
    fun testLifecycleEventEntityCrud() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        val asset = AssetEntity(id = assetId, name = "VW Golf 7", categoryRaw = "vehicle")
        assetDao.insertAsset(asset)

        val eventId = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val dueDate = now + (30L * 24 * 60 * 60 * 1000) // +30 days

        val event = LifecycleEventEntity(
            id = eventId,
            assetId = assetId,
            title = "Schimb Ulei & Filtre",
            eventDescription = "Ulei 5W30 Castrol + filtre MANN",
            dueDate = dueDate,
            cost = 450.0,
            currency = "RON",
            cadenceDays = 365,
            cadenceMetricInterval = 15000.0,
            metricTriggerValue = 165000.0,
            reminderOffsetDays = listOf(30, 7, 1)
        )

        // Insert & Query
        eventDao.insertEvent(event)
        val fetched = eventDao.getEventById(eventId).first()
        assertNotNull("Event must be found", fetched)
        assertEquals("Schimb Ulei & Filtre", fetched?.title)
        assertEquals(450.0, fetched?.cost ?: 0.0, 0.001)
        assertEquals("RON", fetched?.currency)
        assertEquals(365, fetched?.cadenceDays)
        assertEquals(listOf(30, 7, 1), fetched?.reminderOffsetDays)
        assertFalse("Newly created event is not completed", fetched?.isCompleted ?: true)

        // Toggle Completion
        val completedTimestamp = System.currentTimeMillis()
        eventDao.setCompletion(eventId, true, completedTimestamp)
        val fetchedCompleted = eventDao.getEventById(eventId).first()
        assertTrue("Event must be marked completed", fetchedCompleted?.isCompleted ?: false)
        assertEquals(completedTimestamp, fetchedCompleted?.completedDate)
    }

    @Test
    fun testAttachmentEntityCrud() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        assetDao.insertAsset(AssetEntity(id = assetId, name = "Centrală Termică", categoryRaw = "home"))

        val eventId = UUID.randomUUID().toString()
        eventDao.insertEvent(
            LifecycleEventEntity(
                id = eventId,
                assetId = assetId,
                title = "Revizie ISCIR",
                dueDate = System.currentTimeMillis() + 86400000L
            )
        )

        val attachmentId = UUID.randomUUID().toString()
        val attachment = AttachmentEntity(
            id = attachmentId,
            assetId = assetId,
            eventId = eventId,
            fileName = "autorizatie_iscir.pdf",
            fileExtension = "pdf",
            filePath = "/data/user/0/com.dosarcusina/files/autorizatie_iscir.pdf",
            extractedText = "AUTORIZAȚIE DE FUNCȚIONARE ISCIR VALABILĂ PÂNĂ ÎN 2028"
        )

        attachmentDao.insertAttachment(attachment)
        val attachments = attachmentDao.getAttachmentsForAsset(assetId).first()
        assertEquals(1, attachments.size)
        assertEquals("autorizatie_iscir.pdf", attachments[0].fileName)
        assertTrue(attachments[0].extractedText?.contains("ISCIR") == true)
    }

    @Test
    fun testDynamicFieldEntityCrud() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        assetDao.insertAsset(AssetEntity(id = assetId, name = "Bicicletă Cursieră", categoryRaw = "custom"))

        val fieldId = UUID.randomUUID().toString()
        val field = DynamicFieldEntity(
            id = fieldId,
            assetId = assetId,
            key = "greutate_kg",
            label = "Greutate Cadru",
            fieldTypeRaw = "number",
            numberValue = 8.45
        )

        dynamicFieldDao.insertField(field)
        val fields = dynamicFieldDao.getFieldsForAsset(assetId).first()
        assertEquals(1, fields.size)
        assertEquals("greutate_kg", fields[0].key)
        assertEquals("Greutate Cadru", fields[0].label)
        assertEquals(8.45, fields[0].numberValue ?: 0.0, 0.01)
    }

    // MARK: - 2. Cascade Deletion Tests

    @Test
    fun testCascadeDeleteAssetDeletesEvents() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        assetDao.insertAsset(AssetEntity(id = assetId, name = "Dacia Duster", categoryRaw = "vehicle"))

        // Insert 3 child events linked to this asset
        eventDao.insertEvents(
            listOf(
                LifecycleEventEntity(id = UUID.randomUUID().toString(), assetId = assetId, title = "ITP", dueDate = 1000L),
                LifecycleEventEntity(id = UUID.randomUUID().toString(), assetId = assetId, title = "RCA", dueDate = 2000L),
                LifecycleEventEntity(id = UUID.randomUUID().toString(), assetId = assetId, title = "Rovinietă", dueDate = 3000L)
            )
        )

        // Verify inserted
        val beforeDelete = eventDao.getEventsForAsset(assetId).first()
        assertEquals(3, beforeDelete.size)

        // Delete parent asset
        assetDao.deleteAssetById(assetId)

        // Verify CASCADE deletion automatically removed all 3 child events
        val afterDelete = eventDao.getEventsForAsset(assetId).first()
        assertEquals("CASCADE delete must remove all associated lifecycle events", 0, afterDelete.size)
    }

    @Test
    fun testCascadeDeleteAssetDeletesAttachments() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        assetDao.insertAsset(AssetEntity(id = assetId, name = "Proprietate Brașov", categoryRaw = "home"))

        attachmentDao.insertAttachment(
            AttachmentEntity(
                id = UUID.randomUUID().toString(),
                assetId = assetId,
                fileName = "contract_vanzare.pdf",
                fileExtension = "pdf"
            )
        )
        attachmentDao.insertAttachment(
            AttachmentEntity(
                id = UUID.randomUUID().toString(),
                assetId = assetId,
                fileName = "releveu_cadastral.pdf",
                fileExtension = "pdf"
            )
        )

        val beforeDelete = attachmentDao.getAttachmentsForAsset(assetId).first()
        assertEquals(2, beforeDelete.size)

        // Delete parent asset
        assetDao.deleteAssetById(assetId)

        val afterDelete = attachmentDao.getAttachmentsForAsset(assetId).first()
        assertEquals("CASCADE delete must remove all associated attachments", 0, afterDelete.size)
    }

    @Test
    fun testCascadeDeleteAssetDeletesDynamicFields() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        assetDao.insertAsset(AssetEntity(id = assetId, name = "Espressor Cafea", categoryRaw = "custom"))

        dynamicFieldDao.insertFields(
            listOf(
                DynamicFieldEntity(id = UUID.randomUUID().toString(), assetId = assetId, key = "presiune_bar", label = "Presiune Pompa", fieldTypeRaw = "number", numberValue = 15.0),
                DynamicFieldEntity(id = UUID.randomUUID().toString(), assetId = assetId, key = "tip_portafiltru", label = "Portafiltru", fieldTypeRaw = "text", stringValue = "58mm")
            )
        )

        val beforeDelete = dynamicFieldDao.getFieldsForAsset(assetId).first()
        assertEquals(2, beforeDelete.size)

        // Delete parent asset
        assetDao.deleteAssetById(assetId)

        val afterDelete = dynamicFieldDao.getFieldsForAsset(assetId).first()
        assertEquals("CASCADE delete must remove all associated dynamic fields", 0, afterDelete.size)
    }

    @Test
    fun testCascadeDeleteEventDeletesAttachments() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        assetDao.insertAsset(AssetEntity(id = assetId, name = "Clinica Sanador", categoryRaw = "health"))

        val eventId = UUID.randomUUID().toString()
        eventDao.insertEvent(
            LifecycleEventEntity(
                id = eventId,
                assetId = assetId,
                title = "Analize Anuale Sânge",
                dueDate = 1700000000000L
            )
        )

        val attachmentId = UUID.randomUUID().toString()
        attachmentDao.insertAttachment(
            AttachmentEntity(
                id = attachmentId,
                assetId = assetId,
                eventId = eventId,
                fileName = "buletin_analize.pdf",
                fileExtension = "pdf"
            )
        )

        val beforeDelete = attachmentDao.getAttachmentsForEvent(eventId).first()
        assertEquals(1, beforeDelete.size)

        // Delete the parent event
        eventDao.deleteEventById(eventId)

        val afterDelete = attachmentDao.getAttachmentsForEvent(eventId).first()
        assertEquals("Deleting event must CASCADE delete its child attachments", 0, afterDelete.size)
    }

    // MARK: - 3. TypeConverter Tests

    @Test
    fun testTypeConverter_FromIntList() {
        assertEquals("30,7,1", converters.fromIntList(listOf(30, 7, 1)))
        assertEquals("30,14,7,3,1,0", converters.fromIntList(listOf(30, 14, 7, 3, 1, 0)))
        assertEquals("", converters.fromIntList(emptyList()))
        assertNull(converters.fromIntList(null))
    }

    @Test
    fun testTypeConverter_ToIntList() {
        assertEquals(listOf(30, 7, 1), converters.toIntList("30,7,1"))
        assertEquals(listOf(30, 14, 7, 1), converters.toIntList(" 30 , 14 , 7 , 1 "))
        assertEquals(emptyList<Int>(), converters.toIntList(""))
        assertEquals(emptyList<Int>(), converters.toIntList(null))
        // Non-numeric tokens are dropped gracefully
        assertEquals(listOf(30, 7), converters.toIntList("30,abc,7"))
    }

    @Test
    fun testTypeConverter_RoundTrip() {
        val original = listOf(60, 30, 14, 7, 1)
        val serialized = converters.fromIntList(original)
        val deserialized = converters.toIntList(serialized)
        assertEquals("TypeConverter round-trip must preserve exact integer list", original, deserialized)
    }

    // MARK: - 4. Cost Aggregation

    @Test
    fun testCostSumAggregation() = runBlocking {
        val assetId = UUID.randomUUID().toString()
        assetDao.insertAsset(AssetEntity(id = assetId, name = "Casă", categoryRaw = "home"))

        // Events within 2026 range (timestamps 1000..5000)
        eventDao.insertEvents(
            listOf(
                LifecycleEventEntity(id = UUID.randomUUID().toString(), assetId = assetId, title = "Factură Gaze", dueDate = 1500L, cost = 250.0),
                LifecycleEventEntity(id = UUID.randomUUID().toString(), assetId = assetId, title = "Factură Curent", dueDate = 2500L, cost = 150.50),
                // Out of range event (timestamp 8000)
                LifecycleEventEntity(id = UUID.randomUUID().toString(), assetId = assetId, title = "Factură Viitoare", dueDate = 8000L, cost = 500.0)
            )
        )

        val costSum = eventDao.getCostSumForRange(1000L, 5000L).first()
        assertEquals(400.50, costSum ?: 0.0, 0.01)
    }
}
