package com.ar.dosarcusina.archive.binder

import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.DocumentFraming
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.Money
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

// The binder's records as an archive reads them in and writes them out: the stored properties
// of the iOS app's models (ios/DosarCuSina/Models/Schema/), as far as a backup carries them,
// with the few that stay on the phone and that an import decides (since when a deadline's cycle
// is known, when a document's pages were made smaller, the card in the phone's contacts). Phase
// 2's Room store keeps them in its own tables and implements [ArchiveTarget] over them; nothing
// here knows about Android.
//
// A change time that isn't known is ChangeTime.UNKNOWN; a link is the id of the record it points
// at. Values a newer build wrote are kept as written (KeptObject, KeptList), as the store keeps them.

/** A category: its definition (the archive's, until the shared catalog comes) and the household's choices. */
data class BinderTemplate(
    val key: String,
    val name: String,
    val summary: String?,
    val symbol: String,
    /** As written: a tint from a newer build goes out again unchanged. */
    val tint: String,
    val heroStyle: String,
    val isBuiltIn: Boolean,
    /** The catalog version of a built-in's definition; 0 for one of the person's own. */
    val version: Int,
    val homeOrder: Int,
    val isOnHome: Boolean,
    val sections: KeptList<FieldSection>,
    val blueprints: KeptList<ObligationBlueprint>,
    val components: KeptList<ComponentDefinition>,
    val pockets: List<String>,
    val behavior: KeptObject<CategoryBehavior>?,
    val boxGrouping: String?,
    val createdAt: Instant,
    val updatedAt: Instant,
)

data class BinderAsset(
    val id: UUID,
    val templateKey: String,
    val name: String,
    val parentId: UUID?,
    val symbolOverride: String?,
    val tintOverride: String?,
    val notes: String?,
    /** As stored: a secret's value is sealed text, and never leaves the phone. */
    val values: KeptObject<FieldValues>,
    val customFacts: KeptList<CustomFact>,
    val photo: StoredFile?,
    val isExample: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
)

data class BinderObligation(
    val id: UUID,
    val assetId: UUID?,
    val title: String,
    val notes: String?,
    val blueprintKey: String?,
    val kind: String,
    val dueDay: CalendarDay,
    val dueMetric: Double?,
    val reminders: KeptObject<ReminderProfile>,
    val remindersCustomized: Boolean,
    /** Minutes after midnight the reminders come at; none for the household's general time. */
    val reminderMinuteOfDay: Int?,
    val recurrence: KeptObject<RecurrenceRule>,
    val estimatedCost: Money?,
    val provider: String?,
    val reference: String?,
    val status: String,
    /** The day a snooze ends, kept as a day. */
    val snoozedUntil: CalendarDay?,
    val isExample: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
    /** Since when this phone counts the deadline's cycle; a copy a backup brings has none (stays on the phone). */
    val cycleKnownAt: Instant? = null,
)

data class BinderHistoryEntry(
    val id: UUID,
    val assetId: UUID?,
    val obligationId: UUID?,
    val kind: String,
    val title: String,
    val occurredAt: Instant,
    val metricReading: Double?,
    val totalCost: Money?,
    val note: String?,
    val rating: Int?,
    val cycleDueDay: CalendarDay?,
    val nextDueDay: CalendarDay?,
    val previousStatus: String?,
    val previousDueMetric: Double?,
    val providerIds: List<UUID>,
    val isExample: Boolean,
    val reference: String?,
    val updatedAt: Instant,
)

/** A line item: its three amounts share one currency, as the iOS model keeps them. */
data class BinderServiceItem(
    val id: UUID,
    val entryId: UUID?,
    val componentKey: String?,
    val name: String,
    val group: String?,
    val partBrandOrCode: String?,
    val partSerialNumber: String?,
    val currency: String,
    val costAmount: BigDecimal?,
    val laborCostAmount: BigDecimal?,
    val partsCostAmount: BigDecimal?,
    val supplierId: UUID?,
    val batchOrTicket: String?,
    val locationDetail: String?,
    val daysInService: Int?,
    val warrantyMonths: Int?,
    val notes: String?,
    val isExample: Boolean,
    val updatedAt: Instant,
)

data class BinderProvider(
    val id: UUID,
    val name: String,
    val trades: List<String>,
    val phone: String?,
    val email: String?,
    val address: String?,
    val notes: String?,
    val manualRating: Int?,
    val wouldCallAgain: Boolean?,
    val assetIds: List<UUID>,
    val isExample: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
    val taxID: String?,
    /** The card in this phone's contacts: never in a backup. */
    val contactIdentifier: String? = null,
)

data class BinderMeasurement(
    val id: UUID,
    val assetId: UUID?,
    val kind: String,
    val name: String,
    val value: Double,
    val secondaryValue: Double?,
    /** A unit key, or "" for none. */
    val unit: String,
    val recordedAt: Instant,
    val unitPriceAmount: BigDecimal?,
    val unitPriceCurrency: String?,
    val isSelfRead: Boolean,
    val referenceMin: Double?,
    val referenceMax: Double?,
    val source: String?,
    val notes: String?,
    val isExample: Boolean,
    val updatedAt: Instant,
    val startsCounter: Boolean,
    val basis: String?,
)

data class BinderAttachment(
    val id: UUID,
    val title: String?,
    val fileName: String,
    val kind: String,
    val contentType: String,
    val byteCount: Long,
    val sha256: String?,
    /** The original file, when there is one. */
    val file: StoredFile?,
    /** The scanned pages, in order. */
    val pages: List<StoredFile>,
    val thumbnail: StoredFile?,
    val extractedText: String?,
    val documentDay: CalendarDay?,
    val validUntil: CalendarDay?,
    val framing: KeptObject<DocumentFraming>?,
    val isArchived: Boolean,
    val supersededById: UUID?,
    val createdAt: Instant,
    val isExample: Boolean,
    val assetId: UUID?,
    val obligationId: UUID?,
    val historyEntryId: UUID?,
    val serviceItemId: UUID?,
    val measurementId: UUID?,
    val providerId: UUID?,
    val updatedAt: Instant,
    /** When this phone made its pages smaller; none once the pages are another's (stays on the phone). */
    val compactedAt: Instant? = null,
)

data class BinderIssuerLesson(
    val id: UUID,
    val issuerKey: String,
    val issuerName: String,
    val kind: String,
    val field: String,
    val label: String,
    val categoryKey: String?,
    val createdAt: Instant,
    val updatedAt: Instant,
)

/**
 * Everything the binder holds, read once, as an import or a backup sees it. [locks] says, for
 * each category key the binder has, whether the category is locked on this phone now (the
 * iOS app's `CategoryTemplate.isSensitive`, which reads the phone's own lock choices).
 */
data class Binder(
    val templates: List<BinderTemplate> = emptyList(),
    val assets: List<BinderAsset> = emptyList(),
    val obligations: List<BinderObligation> = emptyList(),
    val historyEntries: List<BinderHistoryEntry> = emptyList(),
    val serviceItems: List<BinderServiceItem> = emptyList(),
    val providers: List<BinderProvider> = emptyList(),
    val measurements: List<BinderMeasurement> = emptyList(),
    val attachments: List<BinderAttachment> = emptyList(),
    val issuerLessons: List<BinderIssuerLesson> = emptyList(),
    val locks: Map<String, Boolean> = emptyMap(),
)

/**
 * The ids of records an import takes out ("Înlocuiește tot": what the archive lacks; lessons that contradict each
 * other).
 */
data class Removed(
    val templates: Set<String> = emptySet(),
    val assets: Set<UUID> = emptySet(),
    val obligations: Set<UUID> = emptySet(),
    val historyEntries: Set<UUID> = emptySet(),
    val serviceItems: Set<UUID> = emptySet(),
    val providers: Set<UUID> = emptySet(),
    val measurements: Set<UUID> = emptySet(),
    val attachments: Set<UUID> = emptySet(),
    val issuerLessons: Set<UUID> = emptySet(),
)

/**
 * What one import writes, everything or nothing: each record written whole (a new one, or one
 * written over the record with the same id or key, which keeps the copy it is and what the
 * model doesn't carry), the records taken out, and the locks put on ([locks]: a category key and
 * whether it is locked; an import never opens a category that is locked here).
 */
data class BinderChanges(
    val written: Binder,
    val removed: Removed,
    val locks: Map<String, Boolean>,
)

/**
 * Where an import writes and a backup reads: the binder's store. Phase 2's Room store
 * implements it over its tables and its unit of work; the tests use an in-memory one. The
 * importer reads [snapshot] once, decides everything without the store ([com.ar.dosarcusina.archive.DossierImporter]),
 * then hands [apply] what to write.
 */
interface ArchiveTarget {
    /** Everything the binder holds now, its locks included. */
    fun snapshot(): Binder

    /**
     * Writes [changes] in one step, everything or nothing: on any failure the binder is as it
     * was. Every file a record holds is copied in from where it is ([StoredFile.open]), a piece
     * at a time. A record taken out goes alone: what it held is in [changes] too.
     */
    fun apply(changes: BinderChanges)
}
