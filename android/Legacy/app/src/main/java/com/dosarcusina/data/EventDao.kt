package com.dosarcusina.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface EventDao {
    @Query("SELECT * FROM lifecycle_events ORDER BY dueDate ASC")
    fun getAllEvents(): Flow<List<LifecycleEventEntity>>

    @Query("SELECT * FROM lifecycle_events WHERE id = :id")
    fun getEventById(id: String): Flow<LifecycleEventEntity?>

    @Query("SELECT * FROM lifecycle_events WHERE id = :id")
    suspend fun getEventByIdSync(id: String): LifecycleEventEntity?

    @Query("SELECT * FROM lifecycle_events WHERE assetId = :assetId ORDER BY dueDate ASC")
    fun getEventsForAsset(assetId: String): Flow<List<LifecycleEventEntity>>

    @Query("SELECT * FROM lifecycle_events WHERE assetId = :assetId ORDER BY dueDate ASC")
    suspend fun getEventsForAssetSync(assetId: String): List<LifecycleEventEntity>

    @Transaction
    @Query("SELECT * FROM lifecycle_events WHERE isCompleted = 0 ORDER BY dueDate ASC")
    fun getPendingEvents(): Flow<List<EventWithAsset>>

    @Transaction
    @Query("SELECT * FROM lifecycle_events WHERE isCompleted = 0 ORDER BY dueDate ASC LIMIT :limit")
    fun getUpcomingEvents(limit: Int = 10): Flow<List<EventWithAsset>>

    @Transaction
    @Query("SELECT * FROM lifecycle_events WHERE isCompleted = 0 AND dueDate < :currentTimestamp ORDER BY dueDate ASC")
    fun getOverdueEvents(currentTimestamp: Long = System.currentTimeMillis()): Flow<List<EventWithAsset>>

    @Query("SELECT SUM(cost) FROM lifecycle_events WHERE dueDate BETWEEN :start AND :end AND cost IS NOT NULL")
    fun getCostSumForRange(start: Long, end: Long): Flow<Double?>

    @Query("SELECT SUM(cost) FROM lifecycle_events WHERE dueDate BETWEEN :start AND :end AND cost IS NOT NULL")
    suspend fun getCostSumForRangeSync(start: Long, end: Long): Double?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertEvent(event: LifecycleEventEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertEvents(events: List<LifecycleEventEntity>)

    @Update
    suspend fun updateEvent(event: LifecycleEventEntity)

    @Delete
    suspend fun deleteEvent(event: LifecycleEventEntity)

    @Query("DELETE FROM lifecycle_events WHERE id = :id")
    suspend fun deleteEventById(id: String)

    @Query("UPDATE lifecycle_events SET isCompleted = :isCompleted, completedDate = :completedDate WHERE id = :id")
    suspend fun setCompletion(id: String, isCompleted: Boolean, completedDate: Long?)
}
