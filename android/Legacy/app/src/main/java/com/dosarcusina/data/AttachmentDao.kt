package com.dosarcusina.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface AttachmentDao {
    @Query("SELECT * FROM attachments WHERE assetId = :assetId ORDER BY createdAt DESC")
    fun getAttachmentsForAsset(assetId: String): Flow<List<AttachmentEntity>>

    @Query("SELECT * FROM attachments WHERE assetId = :assetId ORDER BY createdAt DESC")
    suspend fun getAttachmentsForAssetSync(assetId: String): List<AttachmentEntity>

    @Query("SELECT * FROM attachments WHERE eventId = :eventId ORDER BY createdAt DESC")
    fun getAttachmentsForEvent(eventId: String): Flow<List<AttachmentEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAttachment(attachment: AttachmentEntity): Long

    @Update
    suspend fun updateAttachment(attachment: AttachmentEntity)

    @Delete
    suspend fun deleteAttachment(attachment: AttachmentEntity)

    @Query("DELETE FROM attachments WHERE id = :id")
    suspend fun deleteAttachmentById(id: String)
}
