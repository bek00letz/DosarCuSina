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
interface AssetDao {
    @Query("SELECT * FROM assets ORDER BY createdAt DESC")
    fun getAllAssets(): Flow<List<AssetEntity>>

    @Query("SELECT * FROM assets WHERE id = :id")
    fun getAssetById(id: String): Flow<AssetEntity?>

    @Query("SELECT * FROM assets WHERE id = :id")
    suspend fun getAssetByIdSync(id: String): AssetEntity?

    @Transaction
    @Query("SELECT * FROM assets ORDER BY createdAt DESC")
    fun getAssetsWithEvents(): Flow<List<AssetWithEvents>>

    @Transaction
    @Query("SELECT * FROM assets ORDER BY createdAt DESC")
    fun getAllAssetsWithDetails(): Flow<List<AssetWithDetails>>

    @Transaction
    @Query("SELECT * FROM assets WHERE id = :id")
    fun getAssetWithDetails(id: String): Flow<AssetWithDetails?>

    @Transaction
    @Query("SELECT * FROM assets WHERE id = :id")
    suspend fun getAssetWithDetailsSync(id: String): AssetWithDetails?

    @Query("SELECT COUNT(*) FROM assets")
    fun getAssetsCount(): Flow<Int>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAsset(asset: AssetEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAssets(assets: List<AssetEntity>)

    @Update
    suspend fun updateAsset(asset: AssetEntity)

    @Delete
    suspend fun deleteAsset(asset: AssetEntity)

    @Query("DELETE FROM assets WHERE id = :id")
    suspend fun deleteAssetById(id: String)
}
