package com.ar.dosarcusina.archive.v3

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

// The `.dosar` v3 records, field for field as shared/schemas/dosar-v3.md and the iOS app's
// DossierArchiveV3.swift describe them. Identifiers are lowercase UUID text, moments ISO 8601 in
// UTC, days `yyyy-MM-dd`, money a decimal string with its currency; an optional value is left
// out rather than written as null, and read as none either way. What a newer build wrote inside
// a record's objects is kept as written (KeptObject, KeptList); a key it wrote beside the
// record's own is ignored. Each `read` refuses a record of the wrong shape (UnreadableRecord),
// which refuses its file, as on iOS.

/** `manifest.json`: what the archive is and holds, with the SHA-256 of every other file. */
data class Manifest(
    val format: String,
    val schemaVersion: Int,
    val appVersion: String,
    val platform: String,
    val exportedAt: Instant,
    val counts: Counts,
    /** Lowercase hex SHA-256 of every other file, by path. */
    val checksums: Map<String, String>,
) {
    data class Counts(
        val templates: Int,
        val assets: Int,
        val obligations: Int,
        val historyEntries: Int,
        val serviceItems: Int,
        val providers: Int,
        val measurements: Int,
        val attachments: Int,
        /** Missing in archives from before database version 16. */
        val issuerLessons: Int? = null,
    ) {
        fun toJson(): JsonObject = jsonObject {
            put("templates", templates)
            put("assets", assets)
            put("obligations", obligations)
            put("historyEntries", historyEntries)
            put("serviceItems", serviceItems)
            put("providers", providers)
            put("measurements", measurements)
            put("attachments", attachments)
            put("issuerLessons", issuerLessons)
        }

        companion object {
            internal fun read(record: JsonRecord) = Counts(
                record.int("templates"), record.int("assets"), record.int("obligations"), record.int("historyEntries"),
                record.int("serviceItems"), record.int("providers"), record.int("measurements"),
                record.int("attachments"),
                record.intOrNull("issuerLessons"),
            )
        }
    }

    fun toJson(): JsonObject = jsonObject {
        put("format", format)
        put("schemaVersion", schemaVersion)
        put("appVersion", appVersion)
        put("platform", platform)
        put("exportedAt", exportedAt)
        put("counts", counts.toJson())
        put("checksums", JsonObject(checksums.mapValues { JsonPrimitive(it.value) }))
    }

    companion object {
        fun read(json: JsonElement): Manifest {
            val record = JsonRecord.of(json)
            return Manifest(
                record.string("format"), record.int("schemaVersion"), record.string("appVersion"),
                record.string("platform"),
                record.instant("exportedAt"), Counts.read(JsonRecord(record.obj("counts"))),
                record.obj("checksums").mapValues { JsonRecord.text(it.value) },
            )
        }
    }
}

/**
 * A category (`data/templates.json`): a built-in one with the household's preferences, or one of the person's own in
 * full.
 */
data class TemplateRecord(
    val key: String,
    val name: String,
    val summary: String?,
    val symbol: String,
    val tint: String,
    val heroStyle: String,
    val isBuiltIn: Boolean,
    val version: Int,
    val homeOrder: Int,
    val isOnHome: Boolean,
    /** Whether the device that made the archive kept it locked: it may lock the category here, never open it. */
    val isSensitive: Boolean,
    val sections: KeptList<FieldSection>,
    val blueprints: KeptList<ObligationBlueprint>,
    val components: KeptList<ComponentDefinition>?,
    /** Pocket keys as written; missing means the standard set. */
    val pockets: List<String>?,
    val createdAt: Instant,
    val updatedAt: Instant,
    val behavior: KeptObject<CategoryBehavior>?,
    /** `grouped` or `separate` as written; missing means nobody chose. */
    val boxGrouping: String?,
) {
    fun toJson(): JsonObject = jsonObject {
        put("key", key)
        put("name", name)
        put("summary", summary)
        put("symbol", symbol)
        put("tint", tint)
        put("heroStyle", heroStyle)
        put("isBuiltIn", isBuiltIn)
        put("version", version)
        put("homeOrder", homeOrder)
        put("isOnHome", isOnHome)
        put("isSensitive", isSensitive)
        put("sections", sections.toJson())
        put("blueprints", blueprints.toJson())
        put("components", components?.toJson())
        putStrings("pockets", pockets)
        put("createdAt", createdAt)
        put("updatedAt", updatedAt)
        put("behavior", behavior?.json)
        put("boxGrouping", boxGrouping)
    }

    companion object {
        fun read(json: JsonElement): TemplateRecord {
            val record = JsonRecord.of(json)
            return TemplateRecord(
                key = record.string("key"),
                name = record.string("name"),
                summary = record.stringOrNull("summary"),
                symbol = record.string("symbol"),
                tint = record.string("tint"),
                heroStyle = record.string("heroStyle"),
                isBuiltIn = record.bool("isBuiltIn"),
                version = record.int("version"),
                homeOrder = record.int("homeOrder"),
                isOnHome = record.bool("isOnHome"),
                isSensitive = record.bool("isSensitive"),
                sections = KeptList.read(record.list("sections"), FieldSection.codec, FieldSection::key),
                blueprints =
                    KeptList.read(record.list("blueprints"), ObligationBlueprint.codec, ObligationBlueprint::key),
                components = record.element("components")?.let {
                    KeptList.read(JsonRecord.list(it), ComponentDefinition.codec, ComponentDefinition::key)
                },
                pockets = record.stringsOrNull("pockets"),
                createdAt = record.instant("createdAt"),
                updatedAt = record.instant("updatedAt"),
                behavior = record.element("behavior")?.let {
                    KeptObject.decode(it, CategoryBehavior.codec) ?: throw UnreadableRecord()
                },
                boxGrouping = record.stringOrNull("boxGrouping"),
            )
        }
    }
}

/** A section (`data/assets.json`) and its values. */
data class AssetRecord(
    val id: String,
    val templateKey: String,
    val name: String,
    /** The section this one is filed under. */
    val parentId: String?,
    val symbolOverride: String?,
    val tintOverride: String?,
    val notes: String?,
    val values: KeptObject<FieldValues>,
    /** Rows under Date importante; rows this build can't read are kept raw. */
    val customFacts: KeptList<CustomFact>?,
    /** `vault/photos/<id>.jpg` when the section has a photo. */
    val photoPath: String?,
    val isExample: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("templateKey", templateKey)
        put("name", name)
        put("parentId", parentId)
        put("symbolOverride", symbolOverride)
        put("tintOverride", tintOverride)
        put("notes", notes)
        put("values", values.json)
        put("customFacts", customFacts?.toJson())
        put("photoPath", photoPath)
        put("isExample", isExample)
        put("createdAt", createdAt)
        put("updatedAt", updatedAt)
    }

    companion object {
        fun read(json: JsonElement): AssetRecord {
            val record = JsonRecord.of(json)
            return AssetRecord(
                id = record.string("id"),
                templateKey = record.string("templateKey"),
                name = record.string("name"),
                parentId = record.stringOrNull("parentId"),
                symbolOverride = record.stringOrNull("symbolOverride"),
                tintOverride = record.stringOrNull("tintOverride"),
                notes = record.stringOrNull("notes"),
                values = KeptObject.decode(record.obj("values"), FieldValues.codec) ?: throw UnreadableRecord(),
                customFacts = record.element("customFacts")?.let {
                    KeptList.read(JsonRecord.list(it), CustomFact.codec, CustomFact::id)
                },
                photoPath = record.stringOrNull("photoPath"),
                isExample = record.bool("isExample"),
                createdAt = record.instant("createdAt"),
                updatedAt = record.instant("updatedAt"),
            )
        }
    }
}

/** A deadline (`data/obligations.json`): its due day, recurrence and reminders. */
data class ObligationRecord(
    val id: String,
    val assetId: String?,
    val title: String,
    val notes: String?,
    val blueprintKey: String?,
    val kind: String,
    val dueDate: CalendarDay,
    val dueMetric: Double?,
    val reminders: KeptObject<ReminderProfile>,
    val reminderMinuteOfDay: Int?,
    val recurrence: KeptObject<RecurrenceRule>,
    val estimatedCost: Money?,
    val provider: String?,
    val reference: String?,
    val status: String,
    val snoozedUntil: Instant?,
    val isExample: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
    /** The person set the reminders themselves; written only when true. */
    val remindersCustomized: Boolean?,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("assetId", assetId)
        put("title", title)
        put("notes", notes)
        put("blueprintKey", blueprintKey)
        put("kind", kind)
        put("dueDate", dueDate)
        put("dueMetric", dueMetric)
        put("reminders", reminders.json)
        put("reminderMinuteOfDay", reminderMinuteOfDay)
        put("recurrence", recurrence.json)
        put("estimatedCost", estimatedCost)
        put("provider", provider)
        put("reference", reference)
        put("status", status)
        put("snoozedUntil", snoozedUntil)
        put("isExample", isExample)
        put("createdAt", createdAt)
        put("updatedAt", updatedAt)
        put("remindersCustomized", remindersCustomized)
    }

    companion object {
        fun read(json: JsonElement): ObligationRecord {
            val record = JsonRecord.of(json)
            return ObligationRecord(
                id = record.string("id"),
                assetId = record.stringOrNull("assetId"),
                title = record.string("title"),
                notes = record.stringOrNull("notes"),
                blueprintKey = record.stringOrNull("blueprintKey"),
                kind = record.string("kind"),
                dueDate = record.day("dueDate"),
                dueMetric = record.doubleOrNull("dueMetric"),
                reminders = KeptObject.decode(record.obj("reminders"), ReminderProfile.codec)
                    ?: throw UnreadableRecord(),
                reminderMinuteOfDay = record.intOrNull("reminderMinuteOfDay"),
                recurrence = KeptObject.read(
                    record.element("recurrence") ?: throw UnreadableRecord(),
                    RecurrenceRule.codec,
                    RecurrenceRule.None,
                ),
                estimatedCost = record.moneyOrNull("estimatedCost"),
                provider = record.stringOrNull("provider"),
                reference = record.stringOrNull("reference"),
                status = record.string("status"),
                snoozedUntil = record.instantOrNull("snoozedUntil"),
                isExample = record.bool("isExample"),
                createdAt = record.instant("createdAt"),
                updatedAt = record.instant("updatedAt"),
                remindersCustomized = record.boolOrNull("remindersCustomized"),
            )
        }
    }
}

/** Something that happened to a section (`data/history.json`); with `cycleDueDate`, a deadline's completion. */
data class HistoryEntryRecord(
    val id: String,
    val assetId: String?,
    val obligationId: String?,
    val kind: String,
    val title: String,
    val occurredAt: Instant,
    val metricReading: Double?,
    val totalCost: Money?,
    val note: String?,
    val rating: Int?,
    val cycleDueDate: CalendarDay?,
    val nextDueDate: CalendarDay?,
    val previousStatus: String?,
    val previousDueMetric: Double?,
    val providerIds: List<String>,
    val isExample: Boolean,
    /** The number of the paper it records (a bill's invoice number). */
    val reference: String? = null,
    /** Missing in archives from before database version 8: unknown. */
    val updatedAt: Instant? = null,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("assetId", assetId)
        put("obligationId", obligationId)
        put("kind", kind)
        put("title", title)
        put("occurredAt", occurredAt)
        put("metricReading", metricReading)
        put("totalCost", totalCost)
        put("note", note)
        put("rating", rating)
        put("cycleDueDate", cycleDueDate)
        put("nextDueDate", nextDueDate)
        put("previousStatus", previousStatus)
        put("previousDueMetric", previousDueMetric)
        putStrings("providerIds", providerIds)
        put("isExample", isExample)
        put("reference", reference)
        put("updatedAt", updatedAt)
    }

    companion object {
        fun read(json: JsonElement): HistoryEntryRecord {
            val record = JsonRecord.of(json)
            return HistoryEntryRecord(
                id = record.string("id"),
                assetId = record.stringOrNull("assetId"),
                obligationId = record.stringOrNull("obligationId"),
                kind = record.string("kind"),
                title = record.string("title"),
                occurredAt = record.instant("occurredAt"),
                metricReading = record.doubleOrNull("metricReading"),
                totalCost = record.moneyOrNull("totalCost"),
                note = record.stringOrNull("note"),
                rating = record.intOrNull("rating"),
                cycleDueDate = record.dayOrNull("cycleDueDate"),
                nextDueDate = record.dayOrNull("nextDueDate"),
                previousStatus = record.stringOrNull("previousStatus"),
                previousDueMetric = record.doubleOrNull("previousDueMetric"),
                providerIds = record.strings("providerIds"),
                isExample = record.bool("isExample"),
                reference = record.stringOrNull("reference"),
                updatedAt = record.instantOrNull("updatedAt"),
            )
        }
    }
}

/** A line item of a history entry (`data/service_items.json`). */
data class ServiceItemRecord(
    val id: String,
    val entryId: String?,
    val componentKey: String?,
    val name: String,
    val group: String?,
    val partBrandOrCode: String?,
    val partSerialNumber: String?,
    val cost: Money?,
    val laborCost: Money?,
    val partsCost: Money?,
    val supplierId: String?,
    val batchOrTicket: String?,
    val locationDetail: String?,
    val daysInService: Int?,
    val warrantyMonths: Int?,
    val notes: String?,
    val isExample: Boolean,
    /** Missing in archives from before database version 8: unknown. */
    val updatedAt: Instant? = null,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("entryId", entryId)
        put("componentKey", componentKey)
        put("name", name)
        put("group", group)
        put("partBrandOrCode", partBrandOrCode)
        put("partSerialNumber", partSerialNumber)
        put("cost", cost)
        put("laborCost", laborCost)
        put("partsCost", partsCost)
        put("supplierId", supplierId)
        put("batchOrTicket", batchOrTicket)
        put("locationDetail", locationDetail)
        put("daysInService", daysInService)
        put("warrantyMonths", warrantyMonths)
        put("notes", notes)
        put("isExample", isExample)
        put("updatedAt", updatedAt)
    }

    companion object {
        fun read(json: JsonElement): ServiceItemRecord {
            val record = JsonRecord.of(json)
            return ServiceItemRecord(
                id = record.string("id"),
                entryId = record.stringOrNull("entryId"),
                componentKey = record.stringOrNull("componentKey"),
                name = record.string("name"),
                group = record.stringOrNull("group"),
                partBrandOrCode = record.stringOrNull("partBrandOrCode"),
                partSerialNumber = record.stringOrNull("partSerialNumber"),
                cost = record.moneyOrNull("cost"),
                laborCost = record.moneyOrNull("laborCost"),
                partsCost = record.moneyOrNull("partsCost"),
                supplierId = record.stringOrNull("supplierId"),
                batchOrTicket = record.stringOrNull("batchOrTicket"),
                locationDetail = record.stringOrNull("locationDetail"),
                daysInService = record.intOrNull("daysInService"),
                warrantyMonths = record.intOrNull("warrantyMonths"),
                notes = record.stringOrNull("notes"),
                isExample = record.bool("isExample"),
                updatedAt = record.instantOrNull("updatedAt"),
            )
        }
    }
}

/** A person or firm (`data/providers.json`), with their trades and the sections they look after. */
data class ProviderRecord(
    val id: String,
    val name: String,
    val trades: List<String>,
    val phone: String?,
    val email: String?,
    val address: String?,
    val notes: String?,
    val manualRating: Int?,
    val wouldCallAgain: Boolean?,
    val assetIds: List<String>,
    val isExample: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
    /** The firm's tax ID (CUI), digits only. */
    val taxID: String? = null,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("name", name)
        putStrings("trades", trades)
        put("phone", phone)
        put("email", email)
        put("address", address)
        put("notes", notes)
        put("manualRating", manualRating)
        put("wouldCallAgain", wouldCallAgain)
        putStrings("assetIds", assetIds)
        put("isExample", isExample)
        put("createdAt", createdAt)
        put("updatedAt", updatedAt)
        put("taxID", taxID)
    }

    companion object {
        fun read(json: JsonElement): ProviderRecord {
            val record = JsonRecord.of(json)
            return ProviderRecord(
                id = record.string("id"),
                name = record.string("name"),
                trades = record.strings("trades"),
                phone = record.stringOrNull("phone"),
                email = record.stringOrNull("email"),
                address = record.stringOrNull("address"),
                notes = record.stringOrNull("notes"),
                manualRating = record.intOrNull("manualRating"),
                wouldCallAgain = record.boolOrNull("wouldCallAgain"),
                assetIds = record.strings("assetIds"),
                isExample = record.bool("isExample"),
                createdAt = record.instant("createdAt"),
                updatedAt = record.instant("updatedAt"),
                taxID = record.stringOrNull("taxID"),
            )
        }
    }
}

/** What capture learned of an issuer's papers (`data/issuer_lessons.json`): an issuer's words, never the person's. */
data class IssuerLessonRecord(
    val id: String,
    /** `cui:` and its CUI, or `name:` and its name compared the one way. */
    val issuerKey: String,
    val issuerName: String,
    /** A capture kind, as written. */
    val kind: String,
    /** A capture field key, as written. */
    val field: String,
    val label: String,
    /** The category of the section its paper was filed in; missing when not known. */
    val categoryKey: String? = null,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("issuerKey", issuerKey)
        put("issuerName", issuerName)
        put("kind", kind)
        put("field", field)
        put("label", label)
        put("categoryKey", categoryKey)
        put("createdAt", createdAt)
        put("updatedAt", updatedAt)
    }

    companion object {
        fun read(json: JsonElement): IssuerLessonRecord {
            val record = JsonRecord.of(json)
            return IssuerLessonRecord(
                id = record.string("id"),
                issuerKey = record.string("issuerKey"),
                issuerName = record.string("issuerName"),
                kind = record.string("kind"),
                field = record.string("field"),
                label = record.string("label"),
                categoryKey = record.stringOrNull("categoryKey"),
                createdAt = record.instant("createdAt"),
                updatedAt = record.instant("updatedAt"),
            )
        }
    }
}

/** A reading (`data/measurements.json`): a meter, a weight, an odometer. */
data class MeasurementRecord(
    val id: String,
    val assetId: String?,
    val kind: String,
    val name: String,
    val value: Double,
    val secondaryValue: Double?,
    /** A unit key, or "" for none. */
    val unit: String,
    val recordedAt: Instant,
    val unitPrice: Money?,
    val isSelfRead: Boolean,
    val referenceMin: Double?,
    val referenceMax: Double?,
    val source: String?,
    val notes: String?,
    val isExample: Boolean,
    /** Missing in archives from before database version 8: unknown. */
    val updatedAt: Instant? = null,
    /** True on a new counter's first reading; written only then. */
    val startsCounter: Boolean? = null,
    /** How it was taken (`read`, `estimated`), as written; missing when not said. */
    val basis: String? = null,
) {
    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("assetId", assetId)
        put("kind", kind)
        put("name", name)
        put("value", value)
        put("secondaryValue", secondaryValue)
        put("unit", unit)
        put("recordedAt", recordedAt)
        put("unitPrice", unitPrice)
        put("isSelfRead", isSelfRead)
        put("referenceMin", referenceMin)
        put("referenceMax", referenceMax)
        put("source", source)
        put("notes", notes)
        put("isExample", isExample)
        put("updatedAt", updatedAt)
        put("startsCounter", startsCounter)
        put("basis", basis)
    }

    companion object {
        fun read(json: JsonElement): MeasurementRecord {
            val record = JsonRecord.of(json)
            return MeasurementRecord(
                id = record.string("id"),
                assetId = record.stringOrNull("assetId"),
                kind = record.string("kind"),
                name = record.string("name"),
                value = record.double("value"),
                secondaryValue = record.doubleOrNull("secondaryValue"),
                unit = record.string("unit"),
                recordedAt = record.instant("recordedAt"),
                unitPrice = record.moneyOrNull("unitPrice"),
                isSelfRead = record.bool("isSelfRead"),
                referenceMin = record.doubleOrNull("referenceMin"),
                referenceMax = record.doubleOrNull("referenceMax"),
                source = record.stringOrNull("source"),
                notes = record.stringOrNull("notes"),
                isExample = record.bool("isExample"),
                updatedAt = record.instantOrNull("updatedAt"),
                startsCounter = record.boolOrNull("startsCounter"),
                basis = record.stringOrNull("basis"),
            )
        }
    }
}

/** A document's metadata (`data/attachments.json`); its files are in the vault. */
data class AttachmentRecord(
    val id: String,
    val title: String?,
    val fileName: String,
    val kind: String,
    /** The original file's type. */
    val contentType: String,
    val byteCount: Long,
    val sha256: String?,
    /** The original file, `vault/<id>.<ext>`, when there is one. */
    val path: String?,
    /** Scanned pages, `vault/<id>/page-<n>.heic` or `.jpg`, in order. */
    val pagePaths: List<String>,
    /** `vault/<id>/thumbnail.<ext>`. */
    val thumbnailPath: String?,
    val extractedText: String?,
    val documentDate: CalendarDay?,
    val isArchived: Boolean,
    val supersededById: String?,
    val createdAt: Instant,
    val isExample: Boolean,
    val assetId: String?,
    val obligationId: String?,
    val historyEntryId: String?,
    val serviceItemId: String?,
    val measurementId: String?,
    val providerId: String?,
    /** The last day the document itself is valid, as read when it was filed. */
    val validUntil: CalendarDay?,
    /** How the pages are shown; missing when every page is shown as it is. */
    val framing: KeptObject<DocumentFraming>? = null,
    /** Missing in archives from before database version 8: unknown. */
    val updatedAt: Instant? = null,
) {
    /** Every file it points to. */
    val allPaths: List<String> get() = listOfNotNull(path, thumbnailPath) + pagePaths

    fun toJson(): JsonObject = jsonObject {
        put("id", id)
        put("title", title)
        put("fileName", fileName)
        put("kind", kind)
        put("contentType", contentType)
        put("byteCount", MachineText.number(byteCount))
        put("sha256", sha256)
        put("path", path)
        putStrings("pagePaths", pagePaths)
        put("thumbnailPath", thumbnailPath)
        put("extractedText", extractedText)
        put("documentDate", documentDate)
        put("isArchived", isArchived)
        put("supersededById", supersededById)
        put("createdAt", createdAt)
        put("isExample", isExample)
        put("assetId", assetId)
        put("obligationId", obligationId)
        put("historyEntryId", historyEntryId)
        put("serviceItemId", serviceItemId)
        put("measurementId", measurementId)
        put("providerId", providerId)
        put("validUntil", validUntil)
        put("framing", framing?.json)
        put("updatedAt", updatedAt)
    }

    companion object {
        fun read(json: JsonElement): AttachmentRecord {
            val record = JsonRecord.of(json)
            return AttachmentRecord(
                id = record.string("id"),
                title = record.stringOrNull("title"),
                fileName = record.string("fileName"),
                kind = record.string("kind"),
                contentType = record.string("contentType"),
                byteCount = record.long("byteCount"),
                sha256 = record.stringOrNull("sha256"),
                path = record.stringOrNull("path"),
                pagePaths = record.strings("pagePaths"),
                thumbnailPath = record.stringOrNull("thumbnailPath"),
                extractedText = record.stringOrNull("extractedText"),
                documentDate = record.dayOrNull("documentDate"),
                isArchived = record.bool("isArchived"),
                supersededById = record.stringOrNull("supersededById"),
                createdAt = record.instant("createdAt"),
                isExample = record.bool("isExample"),
                assetId = record.stringOrNull("assetId"),
                obligationId = record.stringOrNull("obligationId"),
                historyEntryId = record.stringOrNull("historyEntryId"),
                serviceItemId = record.stringOrNull("serviceItemId"),
                measurementId = record.stringOrNull("measurementId"),
                providerId = record.stringOrNull("providerId"),
                validUntil = record.dayOrNull("validUntil"),
                framing = record.element("framing")?.let {
                    KeptObject.decode(it, DocumentFraming.codec) ?: throw UnreadableRecord()
                },
                updatedAt = record.instantOrNull("updatedAt"),
            )
        }
    }
}

/** Every data file's records, read one file at a time ([read]) and written as an array ([write]). */
object DataFiles {
    /** The records [json] holds: an array of records, each read by [record]. */
    fun <T> read(json: JsonElement, record: (JsonElement) -> T): List<T> = JsonRecord.list(json).map(record)

    fun write(records: List<JsonObject>): JsonArray = JsonArray(records)
}
