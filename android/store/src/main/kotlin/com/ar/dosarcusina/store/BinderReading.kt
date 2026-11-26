package com.ar.dosarcusina.store

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
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.BinderDatabase
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.IssuerLesson
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import com.ar.dosarcusina.store.schema.documentDay
import com.ar.dosarcusina.store.schema.dueDay
import com.ar.dosarcusina.store.schema.keptBehavior
import com.ar.dosarcusina.store.schema.keptBlueprints
import com.ar.dosarcusina.store.schema.keptComponents
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.keptFraming
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.keptReminders
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.snoozedUntil
import com.ar.dosarcusina.store.schema.validUntil
import java.math.BigDecimal
import java.time.ZoneId
import java.util.UUID

/**
 * The store's rows as the archive's binder model reads them ([Binder]): every record in row
 * order, a link as the id of the row it points at. Read inside one read transaction, so a
 * backup sees the binder as it was at one moment.
 */
// One mapping per kind of record.
@Suppress("TooManyFunctions")
internal class BinderReading(private val files: StoreFiles, private val zone: ZoneId) {
    private var assetIds: Map<Long, UUID> = emptyMap()
    private var obligationIds: Map<Long, UUID> = emptyMap()
    private var entryIds: Map<Long, UUID> = emptyMap()
    private var itemIds: Map<Long, UUID> = emptyMap()
    private var readingIds: Map<Long, UUID> = emptyMap()
    private var attachmentIds: Map<Long, UUID> = emptyMap()
    private var providerIds: Map<Long, UUID> = emptyMap()

    suspend fun read(database: BinderDatabase, locks: Map<String, Boolean>): Binder {
        val assets = database.assets().all()
        val obligations = database.obligations().all()
        val history = database.history().all()
        val items = database.items().all()
        val readings = database.readings().all()
        val attachments = database.attachments().all()
        val providers = database.providers().all()
        assetIds = assets.associate { it.pk to it.id }
        obligationIds = obligations.associate { it.pk to it.id }
        entryIds = history.associate { it.pk to it.id }
        itemIds = items.associate { it.pk to it.id }
        readingIds = readings.associate { it.pk to it.id }
        attachmentIds = attachments.associate { it.pk to it.id }
        providerIds = providers.associate { it.pk to it.id }
        val providersOfEntry = database.entryProviders().all()
            .groupBy({ it.historyEntry }, { it.provider?.let(providerIds::get) })
        val assetsOfProvider = database.providerAssets().all()
            .groupBy({ it.provider }, { it.asset?.let(assetIds::get) })
        val pagesOf = database.pages().all().groupBy { it.attachment }
        return Binder(
            templates = database.templates().all().map(::template),
            assets = assets.map(::asset),
            obligations = obligations.map(::obligation),
            historyEntries = history.map { entry(it, providersOfEntry[it.pk].orEmpty().filterNotNull()) },
            serviceItems = items.map(::item),
            providers = providers.map { provider(it, assetsOfProvider[it.pk].orEmpty().filterNotNull()) },
            measurements = readings.map(::reading),
            attachments = attachments.map { attachment(it, pagesOf[it.pk].orEmpty()) },
            issuerLessons = database.lessons().all().map(::lesson),
            locks = locks,
        )
    }

    private fun money(amount: BigDecimal?, currency: String?): Money? =
        amount?.let { Money(it, currency ?: Money.DEFAULT_CURRENCY) }

    private fun template(row: CategoryTemplate) = BinderTemplate(
        key = row.key, name = row.name, summary = row.summary, symbol = row.symbol, tint = row.tintRaw,
        heroStyle = row.heroStyleRaw, isBuiltIn = row.isBuiltIn, version = row.builtInVersion,
        homeOrder = row.homeOrder, isOnHome = row.isOnHome, sections = row.keptSections,
        blueprints = row.keptBlueprints, components = row.keptComponents, pockets = row.pocketsRaw,
        behavior = row.keptBehavior, boxGrouping = row.boxGroupingRaw, createdAt = row.createdAt,
        updatedAt = row.updatedAt,
    )

    private fun asset(row: Asset) = BinderAsset(
        id = row.id, templateKey = row.templateKey, name = row.name, parentId = row.parent?.let(assetIds::get),
        symbolOverride = row.symbolOverride, tintOverride = row.tintOverrideRaw, notes = row.notes,
        values = row.keptValues, customFacts = row.keptFacts, photo = row.photoData?.let(files::file),
        isExample = row.isExample, createdAt = row.createdAt, updatedAt = row.updatedAt,
    )

    private fun obligation(row: Obligation) = BinderObligation(
        id = row.id, assetId = row.asset?.let(assetIds::get), title = row.title, notes = row.notes,
        blueprintKey = row.blueprintKey, kind = row.kindRaw,
        // A deadline whose stored day can't be read is due on the day it was made (`Obligation.dueDay`).
        dueDay = row.dueDay ?: DosarCalendar.day(row.createdAt, zone),
        dueMetric = row.dueMetric, reminders = row.keptReminders, remindersCustomized = row.remindersCustomized,
        reminderMinuteOfDay = row.reminderMinuteOfDay, recurrence = row.keptRecurrence,
        estimatedCost = money(row.estimatedCostAmount, row.estimatedCostCurrency), provider = row.provider,
        reference = row.reference, status = row.statusRaw, snoozedUntil = row.snoozedUntil,
        isExample = row.isExample, createdAt = row.createdAt, updatedAt = row.updatedAt,
        cycleKnownAt = row.cycleKnownAt,
    )

    private fun entry(row: HistoryEntry, providers: List<UUID>) = BinderHistoryEntry(
        id = row.id, assetId = row.asset?.let(assetIds::get), obligationId = row.obligation?.let(obligationIds::get),
        kind = row.kindRaw, title = row.title, occurredAt = row.occurredAt, metricReading = row.metricReading,
        totalCost = money(row.totalCostAmount, row.totalCostCurrency), note = row.note, rating = row.rating,
        cycleDueDay = StoredDay.day(row.cycleDueDayISO), nextDueDay = StoredDay.day(row.nextDueDayISO),
        previousStatus = row.previousStatusRaw, previousDueMetric = row.previousDueMetric, providerIds = providers,
        isExample = row.isExample, reference = row.reference, updatedAt = row.updatedAt,
    )

    private fun item(row: ServiceItem) = BinderServiceItem(
        id = row.id, entryId = row.entry?.let(entryIds::get), componentKey = row.componentKey, name = row.name,
        group = row.group, partBrandOrCode = row.partBrandOrCode, partSerialNumber = row.partSerialNumber,
        currency = row.currency, costAmount = row.costAmount, laborCostAmount = row.laborCostAmount,
        partsCostAmount = row.partsCostAmount, supplierId = row.supplier?.let(providerIds::get),
        batchOrTicket = row.batchOrTicket, locationDetail = row.locationDetail, daysInService = row.daysInService,
        warrantyMonths = row.warrantyMonths, notes = row.notes, isExample = row.isExample, updatedAt = row.updatedAt,
    )

    private fun provider(row: Provider, assets: List<UUID>) = BinderProvider(
        id = row.id, name = row.name, trades = row.trades, phone = row.phone, email = row.email,
        address = row.address, notes = row.notes, manualRating = row.manualRating,
        wouldCallAgain = row.wouldCallAgain, assetIds = assets, isExample = row.isExample,
        createdAt = row.createdAt, updatedAt = row.updatedAt, taxID = row.taxID,
        contactIdentifier = row.contactIdentifier,
    )

    private fun reading(row: MeasurementLog) = BinderMeasurement(
        id = row.id, assetId = row.asset?.let(assetIds::get), kind = row.kindRaw, name = row.name,
        value = row.value, secondaryValue = row.secondaryValue, unit = row.unit, recordedAt = row.recordedAt,
        unitPriceAmount = row.unitPriceAmount, unitPriceCurrency = row.unitPriceCurrency,
        isSelfRead = row.isSelfRead, referenceMin = row.referenceMin, referenceMax = row.referenceMax,
        source = row.source, notes = row.notes, isExample = row.isExample, updatedAt = row.updatedAt,
        startsCounter = row.startsCounter, basis = row.basisRaw,
    )

    private fun attachment(row: Attachment, pages: List<AttachmentPage>) = BinderAttachment(
        id = row.id, title = row.title, fileName = row.fileName, kind = row.kindRaw, contentType = row.contentType,
        byteCount = row.byteCount, sha256 = row.sha256, file = row.fileData?.let(files::file),
        pages = pages.sortedWith(compareBy({ it.index }, { it.pk })).mapNotNull { it.imageData?.let(files::file) },
        thumbnail = row.thumbnailData?.let(files::file), extractedText = row.extractedText,
        documentDay = row.documentDay, validUntil = row.validUntil, framing = row.keptFraming,
        isArchived = row.isArchived, supersededById = row.supersededBy?.let(attachmentIds::get),
        createdAt = row.createdAt, isExample = row.isExample, assetId = row.asset?.let(assetIds::get),
        obligationId = row.obligation?.let(obligationIds::get), historyEntryId = row.historyEntry?.let(entryIds::get),
        serviceItemId = row.serviceItem?.let(itemIds::get), measurementId = row.measurement?.let(readingIds::get),
        providerId = row.provider?.let(providerIds::get), updatedAt = row.updatedAt, compactedAt = row.compactedAt,
    )

    private fun lesson(row: IssuerLesson) = BinderIssuerLesson(
        id = row.id, issuerKey = row.issuerKey, issuerName = row.issuerName, kind = row.kindRaw,
        field = row.fieldKey, label = row.label, categoryKey = row.categoryKey, createdAt = row.createdAt,
        updatedAt = row.updatedAt,
    )
}
