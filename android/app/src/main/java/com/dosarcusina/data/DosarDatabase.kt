package com.dosarcusina.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

/**
 * Room SQLite Database for Dosar cu Șină with 1:1 SwiftData schema parity.
 */
@Database(
    entities = [
        AssetEntity::class,
        LifecycleEventEntity::class,
        AttachmentEntity::class,
        DynamicFieldEntity::class
    ],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class DosarDatabase : RoomDatabase() {
    abstract fun assetDao(): AssetDao
    abstract fun eventDao(): EventDao
    abstract fun attachmentDao(): AttachmentDao
    abstract fun dynamicFieldDao(): DynamicFieldDao

    companion object {
        @Volatile
        private var INSTANCE: DosarDatabase? = null

        fun getInstance(context: Context): DosarDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    DosarDatabase::class.java,
                    "dosarcusina.db"
                ).build()
                INSTANCE = instance
                instance
            }
        }

        /**
         * In-memory database factory for unit tests.
         */
        fun createInMemory(context: Context): DosarDatabase {
            return Room.inMemoryDatabaseBuilder(
                context,
                DosarDatabase::class.java
            )
                .allowMainThreadQueries()
                .build()
        }
    }
}
