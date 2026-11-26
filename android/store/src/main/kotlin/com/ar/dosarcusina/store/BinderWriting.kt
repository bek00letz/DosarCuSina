package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.binder.BinderAsset
import com.ar.dosarcusina.archive.binder.BinderAttachment
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.binder.BinderHistoryEntry
import com.ar.dosarcusina.archive.binder.BinderIssuerLesson
import com.ar.dosarcusina.archive.binder.BinderMeasurement
import com.ar.dosarcusina.archive.binder.BinderObligation
import com.ar.dosarcusina.archive.binder.BinderProvider
import com.ar.dosarcusina.archive.binder.BinderServiceItem
import com.ar.dosarcusina.archive.binder.BinderTemplate
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.IssuerLesson
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import com.ar.dosarcusina.store.schema.withDefinition
import com.ar.dosarcusina.store.schema.withKeptFacts
import com.ar.dosarcusina.store.schema.withKeptFraming
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import com.ar.dosarcusina.store.schema.withKeptReminders
import com.ar.dosarcusina.store.schema.withKeptValues
import java.util.UUID

/**
 * Writes an import's [BinderChanges] into the store's rows, through a step of the unit of work
 * ([UnitOfWork.performPrivate]), which saves it once, its words masked like any save's; the
 * catalog's install at launch writes its plan the same way, as the app's own step.
 *
 * A record written over the one with the same id (or key) stays that row: it keeps its copy
 * ([Asset.copyID]), and every column the archive's model doesn't carry (a document's
 * [Attachment.documentID], when a category was last locked anywhere, a page's id); a new record is
 * a new row, a new copy. It goes in two passes, so a link can point at a record the same import
 * brings: first a row for every record new here, then every record written whole with its links,
 * its holder's id stamped from its link (`ParentLinks.stamp`). A record taken out goes alone, as
 * [BinderChanges] says, with only what is no record of its own ([RecordContents.deleteRow]).
 *
 * Files are already kept ([Step.keep]) when this runs: a column names a file by its digest.
 */
// One writer per kind of record, as the importer has.
@Suppress("TooManyFunctions")
internal class BinderWriting(private val step: Step, private val changes: BinderChanges) {
    private val templates = LinkedHashMap<String, CategoryTemplate>()
    private val assets = Rows<Asset> { it.pk }
    private val obligations = Rows<Obligation> { it.pk }
    private val history = Rows<HistoryEntry> { it.pk }
    private val items = Rows<ServiceItem> { it.pk }
    private val readings = Rows<MeasurementLog> { it.pk }
    private val attachments = Rows<Attachment> { it.pk }
    private val providers = Rows<Provider> { it.pk }
    private val lessons = Rows<IssuerLesson> { it.pk }

    /** One table's rows by id, the first copy in row order when there are two, and every row by its key. */
    private class Rows<R>(private val rowOf: (R) -> Long) {
        val byId = LinkedHashMap<UUID, R>()
        val byRow = HashMap<Long, R>()

        fun add(id: UUID, record: R) {
            byId.putIfAbsent(id, record)
            byRow[rowOf(record)] = record
        }

        /** The row of the record [id] names, if the binder has it. */
        fun row(id: UUID?): Long? = id?.let(byId::get)?.let(rowOf)
    }

    fun write() {
        readCurrent()
        addNewRows()
        writeTemplates()
        writeAssets()
        writeObligations()
        writeHistory()
        writeItems()
        writeReadings()
        writeAttachments()
        writeProviders()
        writeLessons()
        removeTakenOut()
    }

    private fun readCurrent() {
        step.all(Tables.templates).forEach { templates.putIfAbsent(it.key, it) }
        step.all(Tables.assets).forEach { assets.add(it.id, it) }
        step.all(Tables.obligations).forEach { obligations.add(it.id, it) }
        step.all(Tables.history).forEach { history.add(it.id, it) }
        step.all(Tables.items).forEach { items.add(it.id, it) }
        step.all(Tables.readings).forEach { readings.add(it.id, it) }
        step.all(Tables.attachments).forEach { attachments.add(it.id, it) }
        step.all(Tables.providers).forEach { providers.add(it.id, it) }
        step.all(Tables.lessons).forEach { lessons.add(it.id, it) }
    }

    /** The first pass: a row, with no links yet, for every record the binder doesn't have. */
    private fun addNewRows() {
        val written = changes.written
        for (record in written.templates) {
            if (record.key in templates) continue
            templates[record.key] = step.insert(CategoryTemplate(key = record.key))
        }
        add(assets, written.assets.map { it.id }) { step.insert(Asset(id = it)) }
        add(obligations, written.obligations.map { it.id }) { step.insert(Obligation(id = it)) }
        add(history, written.historyEntries.map { it.id }) { step.insert(HistoryEntry(id = it)) }
        add(items, written.serviceItems.map { it.id }) { step.insert(ServiceItem(id = it)) }
        add(readings, written.measurements.map { it.id }) { step.insert(MeasurementLog(id = it)) }
        add(attachments, written.attachments.map { it.id }) { step.insert(Attachment(id = it)) }
        add(providers, written.providers.map { it.id }) { step.insert(Provider(id = it)) }
        add(lessons, written.issuerLessons.map { it.id }) { step.insert(IssuerLesson(id = it)) }
    }

    /** A row made by [insert] for each record [ids] name that the binder doesn't have. */
    private fun <R> add(rows: Rows<R>, ids: List<UUID>, insert: (UUID) -> R) {
        for (id in ids) if (id !in rows.byId) rows.add(id, insert(id))
    }

    private fun assetRow(id: UUID?): Long? = assets.row(id)

    // The second pass: each record written whole over its row. A row added in the first pass
    // is found by its id, which gives its row.

    private fun writeTemplates() {
        for (record in changes.written.templates) {
            val row = requireNotNull(templates[record.key])
            update(row, written(row, record))
        }
    }

    private fun written(row: CategoryTemplate, record: BinderTemplate): CategoryTemplate = row.copy(
        name = record.name, summary = record.summary, symbol = record.symbol, tintRaw = record.tint,
        heroStyleRaw = record.heroStyle, isBuiltIn = record.isBuiltIn, builtInVersion = record.version,
        homeOrder = record.homeOrder, isOnHome = record.isOnHome, pocketsRaw = record.pockets,
        boxGroupingRaw = record.boxGrouping, createdAt = record.createdAt, updatedAt = record.updatedAt,
    ).withDefinition(record.sections, record.blueprints, record.components, record.behavior)

    private fun writeAssets() {
        for (record in changes.written.assets) {
            val row = pkOf(assets, record.id)
            update(row, written(row, record))
        }
    }

    private fun written(row: Asset, record: BinderAsset): Asset = row.copy(
        name = record.name, templateKey = record.templateKey, symbolOverride = record.symbolOverride,
        tintOverrideRaw = record.tintOverride, notes = record.notes, photoData = record.photo?.sha256?.lowercase(),
        isExample = record.isExample, createdAt = record.createdAt, updatedAt = record.updatedAt,
        parent = assetRow(record.parentId),
    ).withKeptValues(record.values).withKeptFacts(record.customFacts)

    private fun writeObligations() {
        val ids = idsOf(assets) { it.id }
        for (record in changes.written.obligations) {
            val row = pkOf(obligations, record.id)
            update(row, ParentLinks.stamp(written(row, record), ids))
        }
    }

    private fun written(row: Obligation, record: BinderObligation): Obligation = row.copy(
        title = record.title, notes = record.notes, blueprintKey = record.blueprintKey, kindRaw = record.kind,
        dueDayISO = StoredDay.text(record.dueDay), dueMetric = record.dueMetric,
        remindersCustomized = record.remindersCustomized, reminderMinuteOfDay = record.reminderMinuteOfDay,
        estimatedCostAmount = record.estimatedCost?.amount, estimatedCostCurrency = record.estimatedCost?.currency,
        provider = record.provider, reference = record.reference, statusRaw = record.status,
        snoozedUntilISO = record.snoozedUntil?.let(StoredDay::text), isExample = record.isExample,
        createdAt = record.createdAt, updatedAt = record.updatedAt, cycleKnownAt = record.cycleKnownAt,
        asset = assetRow(record.assetId),
    ).withKeptReminders(record.reminders).withKeptRecurrence(record.recurrence)

    private fun writeHistory() {
        val ids = idsOf(assets) { it.id }
        for (record in changes.written.historyEntries) {
            val row = pkOf(history, record.id)
            update(row, ParentLinks.stamp(written(row, record), ids))
            step.setLinked(Tables.entryProviders, row.pk, record.providerIds.mapNotNull(providers::row))
        }
    }

    private fun written(row: HistoryEntry, record: BinderHistoryEntry): HistoryEntry = row.copy(
        kindRaw = record.kind, title = record.title, occurredAt = record.occurredAt,
        metricReading = record.metricReading, totalCostAmount = record.totalCost?.amount,
        totalCostCurrency = record.totalCost?.currency, note = record.note, reference = record.reference,
        rating = record.rating, isExample = record.isExample, updatedAt = record.updatedAt,
        cycleDueDayISO = record.cycleDueDay?.let(StoredDay::text),
        nextDueDayISO = record.nextDueDay?.let(StoredDay::text),
        previousStatusRaw = record.previousStatus, previousDueMetric = record.previousDueMetric,
        asset = assetRow(record.assetId), obligation = obligations.row(record.obligationId),
    )

    private fun writeItems() {
        val ids = idsOf(history) { it.id }
        for (record in changes.written.serviceItems) {
            val row = pkOf(items, record.id)
            update(row, ParentLinks.stamp(written(row, record), ids))
        }
    }

    private fun written(row: ServiceItem, record: BinderServiceItem): ServiceItem = row.copy(
        name = record.name, componentKey = record.componentKey, group = record.group,
        partBrandOrCode = record.partBrandOrCode, partSerialNumber = record.partSerialNumber,
        costAmount = record.costAmount, laborCostAmount = record.laborCostAmount,
        partsCostAmount = record.partsCostAmount, currency = record.currency,
        supplier = providers.row(record.supplierId), batchOrTicket = record.batchOrTicket,
        locationDetail = record.locationDetail, daysInService = record.daysInService,
        warrantyMonths = record.warrantyMonths, notes = record.notes, isExample = record.isExample,
        updatedAt = record.updatedAt, entry = history.row(record.entryId),
    )

    private fun writeReadings() {
        val ids = idsOf(assets) { it.id }
        for (record in changes.written.measurements) {
            val row = pkOf(readings, record.id)
            update(row, ParentLinks.stamp(written(row, record), ids))
        }
    }

    private fun written(row: MeasurementLog, record: BinderMeasurement): MeasurementLog = row.copy(
        kindRaw = record.kind, name = record.name, value = record.value, secondaryValue = record.secondaryValue,
        unit = record.unit, recordedAt = record.recordedAt, unitPriceAmount = record.unitPriceAmount,
        unitPriceCurrency = record.unitPriceCurrency, isSelfRead = record.isSelfRead,
        referenceMin = record.referenceMin, referenceMax = record.referenceMax, source = record.source,
        notes = record.notes, isExample = record.isExample, updatedAt = record.updatedAt,
        startsCounter = record.startsCounter, basisRaw = record.basis, asset = assetRow(record.assetId),
    )

    private fun writeAttachments() {
        val ids = idsOf(assets) { it.id }
        for (record in changes.written.attachments) {
            val row = pkOf(attachments, record.id)
            update(row, ParentLinks.stamp(written(row, record), ids))
            writePages(row, record)
        }
    }

    private fun written(row: Attachment, record: BinderAttachment): Attachment = row.copy(
        title = record.title, fileName = record.fileName, kindRaw = record.kind, contentType = record.contentType,
        fileData = record.file?.sha256?.lowercase(), thumbnailData = record.thumbnail?.sha256?.lowercase(),
        byteCount = record.byteCount, sha256 = record.sha256, extractedText = record.extractedText,
        documentDayISO = record.documentDay?.let(StoredDay::text),
        validUntilISO = record.validUntil?.let(StoredDay::text),
        isArchived = record.isArchived, compactedAt = record.compactedAt, createdAt = record.createdAt,
        isExample = record.isExample, updatedAt = record.updatedAt,
        supersededBy = attachments.row(record.supersededById), asset = assetRow(record.assetId),
        obligation = obligations.row(record.obligationId),
        historyEntry = history.row(record.historyEntryId),
        serviceItem = items.row(record.serviceItemId),
        measurement = readings.row(record.measurementId),
        provider = providers.row(record.providerId),
    ).withKeptFraming(record.framing)

    /**
     * A document's pages as the archive gives them, in order: each page already there stays the
     * page it was (its id, its copy), with the picture the archive gives it.
     */
    private fun writePages(document: Attachment, record: BinderAttachment) {
        val current = step.all(Tables.pages).filter { it.attachment == document.pk }
            .sortedWith(compareBy({ it.index }, { it.pk }))
        record.pages.forEachIndexed { index, file ->
            val page = current.getOrNull(index)
            val wanted = (page ?: AttachmentPage()).copy(
                index = index,
                imageData = file.sha256.lowercase(),
                attachment = document.pk,
                attachmentID = document.id,
            )
            if (page == null) step.insert(wanted) else if (wanted != page) step.update(wanted)
        }
        current.drop(record.pages.size).forEach(step::remove)
    }

    private fun writeProviders() {
        for (record in changes.written.providers) {
            val row = pkOf(providers, record.id)
            update(row, written(row, record))
            step.setLinked(Tables.providerAssets, row.pk, record.assetIds.mapNotNull(::assetRow))
        }
    }

    private fun written(row: Provider, record: BinderProvider): Provider = row.copy(
        name = record.name, trades = record.trades, phone = record.phone, email = record.email,
        address = record.address, notes = record.notes, manualRating = record.manualRating,
        wouldCallAgain = record.wouldCallAgain, contactIdentifier = record.contactIdentifier,
        taxID = record.taxID, isExample = record.isExample, createdAt = record.createdAt,
        updatedAt = record.updatedAt,
    )

    private fun writeLessons() {
        for (record in changes.written.issuerLessons) {
            val row = pkOf(lessons, record.id)
            update(row, written(row, record))
        }
    }

    private fun written(row: IssuerLesson, record: BinderIssuerLesson): IssuerLesson = row.copy(
        issuerKey = record.issuerKey, issuerName = record.issuerName, kindRaw = record.kind,
        fieldKey = record.field, label = record.label, categoryKey = record.categoryKey,
        createdAt = record.createdAt, updatedAt = record.updatedAt,
    )

    /** What an import takes out: every copy of each record it names, alone. */
    private fun removeTakenOut() {
        val removed = changes.removed
        takeOut(step.all(Tables.templates).filter { it.key in removed.templates })
        takeOut(step.all(Tables.assets).filter { it.id in removed.assets })
        takeOut(step.all(Tables.obligations).filter { it.id in removed.obligations })
        takeOut(step.all(Tables.history).filter { it.id in removed.historyEntries })
        takeOut(step.all(Tables.items).filter { it.id in removed.serviceItems })
        takeOut(step.all(Tables.providers).filter { it.id in removed.providers })
        takeOut(step.all(Tables.readings).filter { it.id in removed.measurements })
        takeOut(step.all(Tables.attachments).filter { it.id in removed.attachments })
        takeOut(step.all(Tables.lessons).filter { it.id in removed.issuerLessons })
    }

    private fun takeOut(rows: List<Any>) {
        for (row in rows) RecordContents.deleteRow(step, row)
    }

    // Helpers

    /** The row of the record [id] names, as it now is: after the first pass, every written record has one. */
    private fun <R> pkOf(rows: Rows<R>, id: UUID): R = requireNotNull(rows.byId[id])

    private fun <R> idsOf(rows: Rows<R>, id: (R) -> UUID) = ParentLinks.IdOfRow { row -> rows.byRow[row]?.let(id) }

    private fun <R : Any> update(row: R, wanted: R) {
        if (wanted != row) step.update(wanted)
    }
}
