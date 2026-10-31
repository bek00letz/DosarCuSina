package com.dosarcusina.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface DynamicFieldDao {
    @Query("SELECT * FROM dynamic_fields WHERE assetId = :assetId")
    fun getFieldsForAsset(assetId: String): Flow<List<DynamicFieldEntity>>

    @Query("SELECT * FROM dynamic_fields WHERE assetId = :assetId")
    suspend fun getFieldsForAssetSync(assetId: String): List<DynamicFieldEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertField(field: DynamicFieldEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertFields(fields: List<DynamicFieldEntity>)

    @Update
    suspend fun updateField(field: DynamicFieldEntity)

    @Delete
    suspend fun deleteField(field: DynamicFieldEntity)

    @Query("DELETE FROM dynamic_fields WHERE id = :id")
    suspend fun deleteFieldById(id: String)
}
