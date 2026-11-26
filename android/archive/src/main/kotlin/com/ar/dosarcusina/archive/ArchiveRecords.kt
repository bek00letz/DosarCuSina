package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderAsset
import com.ar.dosarcusina.archive.binder.BinderAttachment
import com.ar.dosarcusina.archive.binder.BinderHistoryEntry
import com.ar.dosarcusina.archive.binder.BinderIssuerLesson
import com.ar.dosarcusina.archive.binder.BinderMeasurement
import com.ar.dosarcusina.archive.binder.BinderObligation
import com.ar.dosarcusina.archive.binder.BinderProvider
import com.ar.dosarcusina.archive.binder.BinderServiceItem
import com.ar.dosarcusina.archive.binder.BinderTemplate
import com.ar.dosarcusina.archive.v3.AssetRecord
import com.ar.dosarcusina.archive.v3.AttachmentRecord
import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.HistoryEntryRecord
import com.ar.dosarcusina.archive.v3.Ids
import com.ar.dosarcusina.archive.v3.IssuerLessonRecord
import com.ar.dosarcusina.archive.v3.MeasurementRecord
import com.ar.dosarcusina.archive.v3.ObligationRecord
import com.ar.dosarcusina.archive.v3.ProviderRecord
import com.ar.dosarcusina.archive.v3.ServiceItemRecord
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.archive.v3.TemplateRecord
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.Money
import java.time.ZoneId

/**
 * The binder as an archive writes it: each record of the store as its `.dosar` v3 record, and
 * every file a record holds by the path it goes under, as the iOS app's
 * `DossierArchiveWriter` makes its records. Secrets (PIN codes, secret rows, anything sealed)
 * never leave the phone: an archive carries none. What stays on the phone
 * ([DossierV3.STAY_ON_THE_PHONE]) is never written.
 */
data class ArchiveContents(
    val templates: List<TemplateRecord>,
    val assets: List<AssetRecord>,
    val obligations: List<ObligationRecord>,
    val historyEntries: List<HistoryEntryRecord>,
    val serviceItems: List<ServiceItemRecord>,
    val providers: List<ProviderRecord>,
    val measurements: List<MeasurementRecord>,
    val attachments: List<AttachmentRecord>,
    val issuerLessons: List<IssuerLessonRecord>,
    /** Every vault file, by its path, in the order the writer writes them. */
    val files: List<Pair<String, StoredFile>>,
)

object ArchiveRecords {
    /**
     * [binder]'s records as an archive writes them, in the iOS writer's order. [zone] is the
     * time zone days are counted in: a snooze's day is written as its start there.
     */
    fun of(binder: Binder, zone: ZoneId): ArchiveContents {
        val fields = binder.templates.associate { it.key to it.sections.items.flatMap(FieldSection::fields) }
        val files = ArrayList<Pair<String, StoredFile>>()
        val assets = binder.assets.sortedBy { it.createdAt }.map { asset ->
            val photoPath = asset.photo?.let { photo ->
                "${DossierV3.Path.PHOTOS_PREFIX}${Ids.text(asset.id)}.jpg".also { files += it to photo }
            }
            asset(asset, photoPath, fields[asset.templateKey])
        }
        val attachments = binder.attachments.sortedBy { it.createdAt }.map { attachment(it, files) }
        return ArchiveContents(
            templates = binder.templates.sortedBy { it.homeOrder }.map { template(it, binder.locks[it.key] ?: false) },
            assets = assets,
            obligations = binder.obligations.sortedBy { it.createdAt }.map { obligation(it, zone) },
            historyEntries = binder.historyEntries.sortedBy { it.occurredAt }.map(::historyEntry),
            serviceItems = binder.serviceItems.sortedBy { it.name }.map(::serviceItem),
            providers = binder.providers.sortedBy { it.createdAt }.map(::provider),
            measurements = binder.measurements.sortedBy { it.recordedAt }.map(::measurement),
            attachments = attachments,
            issuerLessons = binder.issuerLessons.sortedBy { Ids.text(it.id) }.map(::issuerLesson),
            files = files,
        )
    }

    private fun template(template: BinderTemplate, isLocked: Boolean) = TemplateRecord(
        key = template.key, name = template.name, summary = template.summary, symbol = template.symbol,
        tint = template.tint, heroStyle = template.heroStyle, isBuiltIn = template.isBuiltIn,
        version = template.version,
        homeOrder = template.homeOrder, isOnHome = template.isOnHome, isSensitive = isLocked,
        sections = template.sections, blueprints = template.blueprints,
        // As stored: a pocket from a newer build goes out as it came in.
        components = template.components, pockets = template.pockets,
        createdAt = template.createdAt, updatedAt = template.updatedAt,
        behavior = template.behavior?.omitted { it.isStandard }, boxGrouping = template.boxGrouping,
    )

    /** Secrets never leave the phone: an archive carries none. */
    private fun asset(asset: BinderAsset, photoPath: String?, fields: List<FieldDefinition>?) = AssetRecord(
        id = Ids.text(asset.id), templateKey = asset.templateKey, name = asset.name,
        parentId = asset.parentId?.let(Ids::text), symbolOverride = asset.symbolOverride,
        tintOverride = asset.tintOverride, notes = asset.notes,
        values = SecretRules.stripping(asset.values, fields),
        customFacts = SecretRules.strippingFacts(asset.customFacts).takeUnless { it.items.isEmpty() && it.isFullyRead },
        photoPath = photoPath, isExample = asset.isExample, createdAt = asset.createdAt, updatedAt = asset.updatedAt,
    )

    private fun obligation(obligation: BinderObligation, zone: ZoneId) = ObligationRecord(
        id = Ids.text(obligation.id), assetId = obligation.assetId?.let(Ids::text), title = obligation.title,
        notes = obligation.notes, blueprintKey = obligation.blueprintKey, kind = obligation.kind,
        dueDate = obligation.dueDay, dueMetric = obligation.dueMetric, reminders = obligation.reminders,
        reminderMinuteOfDay = obligation.reminderMinuteOfDay, recurrence = obligation.recurrence,
        estimatedCost = obligation.estimatedCost, provider = obligation.provider, reference = obligation.reference,
        status = obligation.status, snoozedUntil = obligation.snoozedUntil?.startOfDay(zone),
        isExample = obligation.isExample, createdAt = obligation.createdAt, updatedAt = obligation.updatedAt,
        remindersCustomized = obligation.remindersCustomized.takeIf { it },
    )

    private fun historyEntry(entry: BinderHistoryEntry) = HistoryEntryRecord(
        id = Ids.text(entry.id), assetId = entry.assetId?.let(Ids::text),
        obligationId = entry.obligationId?.let(Ids::text),
        kind = entry.kind, title = entry.title, occurredAt = entry.occurredAt, metricReading = entry.metricReading,
        totalCost = entry.totalCost, note = entry.note, rating = entry.rating, cycleDueDate = entry.cycleDueDay,
        nextDueDate = entry.nextDueDay, previousStatus = entry.previousStatus,
        previousDueMetric = entry.previousDueMetric,
        providerIds = entry.providerIds.map(Ids::text).sorted(), isExample = entry.isExample,
        reference = entry.reference, updatedAt = ChangeTime.written(entry.updatedAt),
    )

    private fun serviceItem(item: BinderServiceItem) = ServiceItemRecord(
        id = Ids.text(item.id), entryId = item.entryId?.let(Ids::text), componentKey = item.componentKey,
        name = item.name, group = item.group, partBrandOrCode = item.partBrandOrCode,
        partSerialNumber = item.partSerialNumber,
        cost = item.costAmount?.let { Money(it, item.currency) },
        laborCost = item.laborCostAmount?.let { Money(it, item.currency) },
        partsCost = item.partsCostAmount?.let { Money(it, item.currency) },
        supplierId = item.supplierId?.let(Ids::text), batchOrTicket = item.batchOrTicket,
        locationDetail = item.locationDetail,
        daysInService = item.daysInService, warrantyMonths = item.warrantyMonths, notes = item.notes,
        isExample = item.isExample, updatedAt = ChangeTime.written(item.updatedAt),
    )

    private fun provider(provider: BinderProvider) = ProviderRecord(
        id = Ids.text(provider.id), name = provider.name, trades = provider.trades, phone = provider.phone,
        email = provider.email, address = provider.address, notes = provider.notes,
        manualRating = provider.manualRating,
        wouldCallAgain = provider.wouldCallAgain, assetIds = provider.assetIds.map(Ids::text).sorted(),
        isExample = provider.isExample, createdAt = provider.createdAt, updatedAt = provider.updatedAt,
        taxID = provider.taxID,
    )

    private fun issuerLesson(lesson: BinderIssuerLesson) = IssuerLessonRecord(
        id = Ids.text(lesson.id), issuerKey = lesson.issuerKey, issuerName = lesson.issuerName, kind = lesson.kind,
        field = lesson.field, label = lesson.label, categoryKey = lesson.categoryKey, createdAt = lesson.createdAt,
        updatedAt = lesson.updatedAt,
    )

    private fun measurement(log: BinderMeasurement) = MeasurementRecord(
        id = Ids.text(log.id), assetId = log.assetId?.let(Ids::text), kind = log.kind, name = log.name,
        value = log.value,
        secondaryValue = log.secondaryValue, unit = MeasurementUnit.storedKey(log.unit), recordedAt = log.recordedAt,
        unitPrice = log.unitPriceAmount?.let { Money(it, log.unitPriceCurrency ?: Money.DEFAULT_CURRENCY) },
        isSelfRead = log.isSelfRead, referenceMin = log.referenceMin, referenceMax = log.referenceMax,
        source = log.source,
        notes = log.notes, isExample = log.isExample, updatedAt = ChangeTime.written(log.updatedAt),
        startsCounter = log.startsCounter.takeIf { it }, basis = log.basis,
    )

    /**
     * A document's record, its files added to [files] under the paths it names: pages and thumbnails by what their
     * bytes are.
     */
    private fun attachment(
        attachment: BinderAttachment,
        files: MutableList<Pair<String, StoredFile>>,
    ): AttachmentRecord {
        val base = "${DossierV3.Path.VAULT_PREFIX}${Ids.text(attachment.id)}"
        val path = attachment.file?.let { file ->
            "$base.${FileExtensions.of(attachment.fileName, attachment.contentType)}".also { files += it to file }
        }
        val pagePaths = attachment.pages.mapIndexed { index, page ->
            "$base/page-${index + 1}.${pictureExtension(page)}".also { files += it to page }
        }
        val thumbnailPath = attachment.thumbnail?.let { thumbnail ->
            "$base/thumbnail.${pictureExtension(thumbnail)}".also { files += it to thumbnail }
        }
        return AttachmentRecord(
            id = Ids.text(attachment.id), title = attachment.title, fileName = attachment.fileName,
            kind = attachment.kind,
            contentType = attachment.contentType, byteCount = attachment.byteCount, sha256 = attachment.sha256,
            path = path, pagePaths = pagePaths, thumbnailPath = thumbnailPath, extractedText = attachment.extractedText,
            documentDate = attachment.documentDay, isArchived = attachment.isArchived,
            supersededById = attachment.supersededById?.let(Ids::text), createdAt = attachment.createdAt,
            isExample = attachment.isExample, assetId = attachment.assetId?.let(Ids::text),
            obligationId = attachment.obligationId?.let(Ids::text),
            historyEntryId = attachment.historyEntryId?.let(Ids::text),
            serviceItemId = attachment.serviceItemId?.let(Ids::text),
            measurementId = attachment.measurementId?.let(Ids::text),
            providerId = attachment.providerId?.let(Ids::text), validUntil = attachment.validUntil,
            framing = attachment.framing?.omitted { it.isPlain }, updatedAt = ChangeTime.written(attachment.updatedAt),
        )
    }

    private fun pictureExtension(file: StoredFile): String =
        DossierV3.Path.pictureExtension(file.header(DossierV3.Path.PICTURE_HEADER_BYTES))
}

/** The extension a document's original file is written under, as the iOS writer's `fileExtension(for:)`. */
internal object FileExtensions {
    /** A type's usual extension, for the types documents come in: Apple's identifiers and MIME types alike. */
    private val BY_TYPE = mapOf(
        "com.adobe.pdf" to "pdf", "application/pdf" to "pdf",
        "public.jpeg" to "jpeg", "image/jpeg" to "jpeg",
        "public.png" to "png", "image/png" to "png",
        "public.heic" to "heic", "image/heic" to "heic",
        "public.plain-text" to "txt", "text/plain" to "txt",
    )

    /** The file name's own extension when it is letters and digits; else the type's; else `bin`. */
    fun of(fileName: String, contentType: String): String {
        val dot = fileName.lastIndexOf('.')
        val fromName = if (dot > 0) fileName.substring(dot + 1).lowercase() else ""
        if (fromName.isNotEmpty() && fromName.all(Char::isLetterOrDigit)) return fromName
        return BY_TYPE[contentType.lowercase()] ?: "bin"
    }
}
