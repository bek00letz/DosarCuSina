package com.dosarcusina.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface MeasurementLogDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(log: MeasurementLogEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(logs: List<MeasurementLogEntity>)

    @Update
    suspend fun update(log: MeasurementLogEntity)

    @Delete
    suspend fun delete(log: MeasurementLogEntity)

    @Query("SELECT * FROM measurement_logs WHERE id = :id")
    suspend fun getById(id: String): MeasurementLogEntity?

    @Query("SELECT * FROM measurement_logs WHERE assetId = :assetId ORDER BY recordedAt DESC")
    fun getForAsset(assetId: String): Flow<List<MeasurementLogEntity>>

    @Query("SELECT * FROM measurement_logs WHERE assetId = :assetId AND metricName = :metricName ORDER BY recordedAt DESC")
    suspend fun getForAssetAndMetric(assetId: String, metricName: String): List<MeasurementLogEntity>

    @Query("DELETE FROM measurement_logs WHERE assetId = :assetId")
    suspend fun deleteForAsset(assetId: String)
}
