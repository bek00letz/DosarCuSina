package com.dosarcusina.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface ServiceItemDao {
    @Query("SELECT * FROM service_items WHERE assetId = :assetId ORDER BY serviceDate DESC")
    fun getItemsForAsset(assetId: String): Flow<List<ServiceItemEntity>>

    @Query("SELECT * FROM service_items WHERE assetId = :assetId AND componentName = :name ORDER BY serviceDate DESC")
    suspend fun getHistoryForComponent(assetId: String, name: String): List<ServiceItemEntity>

    @Query("SELECT * FROM service_items WHERE eventId = :eventId")
    suspend fun getItemsForEvent(eventId: String): List<ServiceItemEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: ServiceItemEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(items: List<ServiceItemEntity>)

    @Update
    suspend fun update(item: ServiceItemEntity)

    @Delete
    suspend fun delete(item: ServiceItemEntity)
}
