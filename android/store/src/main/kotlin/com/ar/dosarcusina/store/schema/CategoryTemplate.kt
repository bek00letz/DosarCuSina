package com.ar.dosarcusina.store.schema

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.Index
import androidx.room3.PrimaryKey
import java.time.Instant
import java.util.UUID

/**
 * A category: its definition and the household's choices for it, as the iOS app's
 * `CategoryTemplate` (ios/DosarCuSina/Models/Schema/CategoryTemplateModel.swift). It is known by
 * its [key]. Whether it is locked on this phone is never kept here (the iOS app's `SectionLocks`,
 * beside the store); only when it was last locked anywhere ([lockedEverywhereAt]).
 */
@Entity(tableName = "CategoryTemplate", indices = [Index("key")])
data class CategoryTemplate(
    @PrimaryKey(autoGenerate = true) val pk: Long = 0,
    @ColumnInfo(defaultValue = Defaults.EMPTY) val key: String = "",
    val copyID: UUID? = UUID.randomUUID(),
    @ColumnInfo(defaultValue = Defaults.EMPTY) val name: String = "",
    val summary: String? = null,
    @ColumnInfo(defaultValue = "'square.grid.2x2'") val symbol: String = "square.grid.2x2",
    @ColumnInfo(defaultValue = "'gray'") val tintRaw: String = "gray",
    @ColumnInfo(defaultValue = "'standard'") val heroStyleRaw: String = "standard",
    @ColumnInfo(defaultValue = Defaults.FALSE) val isBuiltIn: Boolean = false,
    /** The catalog version of a built-in's definition; 0 for one of the person's own. */
    @ColumnInfo(defaultValue = Defaults.ZERO) val builtInVersion: Int = 0,
    @ColumnInfo(defaultValue = Defaults.ZERO) val homeOrder: Int = 0,
    @ColumnInfo(defaultValue = Defaults.TRUE) val isOnHome: Boolean = true,
    /** The person's choice of one box or one per section (`BoxGrouping`); none: the catalog's. */
    val boxGroupingRaw: String? = null,
    /** When it was last locked on one of the person's devices; never in a backup. */
    val lockedEverywhereAt: Instant? = null,
    /** JSON `[FieldSection]`, read and written through `keptSections`. */
    val sectionsData: String? = null,
    /** JSON `[ObligationBlueprint]`. */
    val blueprintsData: String? = null,
    /** JSON `[ComponentDefinition]`. */
    val componentsData: String? = null,
    /** `SectionPocket` keys. */
    @ColumnInfo(defaultValue = STANDARD_POCKETS) val pocketsRaw: List<String> = StandardPockets,
    /** JSON `CategoryBehavior`; none for the standard behaviour with nothing more. */
    val behaviorData: String? = null,
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val createdAt: Instant = StoredMoment.now(),
    @ColumnInfo(defaultValue = StoredMoment.UNKNOWN_MILLIS) val updatedAt: Instant = StoredMoment.now(),
) {
    companion object {
        /** `SectionPocket.standard`, as the column's SQL default writes it. */
        const val STANDARD_POCKETS = "'[\"upcoming\",\"documents\",\"history\",\"people\",\"money\",\"keyFacts\"]'"

        /** `SectionPocket.standard`: the pockets a category shows when it doesn't say. */
        val StandardPockets: List<String> = listOf("upcoming", "documents", "history", "people", "money", "keyFacts")
    }
}
