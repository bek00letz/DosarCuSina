package com.dosarcusina.data

import androidx.room.TypeConverter

/**
 * Room TypeConverter for list serialization.
 */
class Converters {
    @TypeConverter
    fun fromIntList(list: List<Int>?): String? {
        if (list == null) return null
        return list.joinToString(separator = ",")
    }

    @TypeConverter
    fun toIntList(data: String?): List<Int> {
        if (data.isNullOrEmpty()) return emptyList()
        return data.split(",")
            .mapNotNull { it.trim().toIntOrNull() }
    }
}
