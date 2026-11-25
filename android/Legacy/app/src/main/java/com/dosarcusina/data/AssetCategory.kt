package com.dosarcusina.data

/**
 * 1:1 parity with iOS AssetCategory.swift
 */
enum class AssetCategory(
    val rawValue: String,
    val title: String,
    val systemIcon: String,
    val defaultColorHex: String
) {
    HOME("home", "Casă", "house.fill", "FF9500"),
    VEHICLE("vehicle", "Mașină", "car.fill", "007AFF"),
    PET("pet", "Pet", "pawprint.fill", "A2845E"),
    HEALTH("health", "Sănătate", "heart.text.square.fill", "FF2D55"),
    DOCUMENTS("documents", "Documente", "person.text.rectangle.fill", "5856D6"),
    WARRANTIES("warranties", "Garanții", "shield.lefthalf.filled", "30B0C7"),
    SUBSCRIPTIONS("subscriptions", "Abonamente", "creditcard.fill", "AF52DE"),
    CUSTOM("custom", "Personalizat", "square.grid.2x2.fill", "8E8E93");

    companion object {
        fun fromRaw(raw: String?): AssetCategory {
            if (raw == null) return CUSTOM
            return entries.firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: CUSTOM
        }
    }
}
