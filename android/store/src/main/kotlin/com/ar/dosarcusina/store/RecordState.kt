package com.ar.dosarcusina.store

import com.ar.dosarcusina.core.values.DecimalText
import com.ar.dosarcusina.store.schema.StoredMoment
import java.math.BigDecimal
import java.time.Instant

/**
 * Which record: its kind (the iOS model's name) and its row. A record keeps its row for good, so
 * a record a step deleted comes back under the same row, and every link that named it names it
 * again.
 */
data class RecordRef(val type: String, val row: Long) {
    override fun toString(): String = "$type $row"

    companion object {
        fun <R : Any> of(table: Table<R>, record: R): RecordRef = RecordRef(table.type, table.rowOf(record))

        fun of(record: Any): RecordRef = of(Tables.of(record), record)
    }
}

/**
 * One stored property's value: an attribute as it is stored, a picture or a file by its digest
 * (the store keeps the bytes beside the database, [StoreFiles]), or a relationship as the records
 * it points to.
 */
sealed interface StoredValue {
    data class Attribute(val value: Any?) : StoredValue

    /** A picture or a file kept beside the database, by its digest; none when there is none. */
    data class File(val digest: String?) : StoredValue

    data class One(val ref: RecordRef?) : StoredValue

    data class Many(override val refs: Set<RecordRef>) : StoredValue

    /** The records a relationship points to; none for an attribute or a file. */
    val refs: Set<RecordRef>
        get() = if (this is One) setOfNotNull(ref) else emptySet()
}

/**
 * Every stored property of one record, as plain values, pictures and files by their digest, and
 * links as the records they name, as the iOS app's `RecordState`
 * (ios/DosarCuSina/Services/Persistence/RecordState.swift). An undo receipt keeps these for the
 * records a step changed or deleted, and puts them back; tests compare them to check that undo
 * restores exactly the state before.
 */
data class RecordState(val ref: RecordRef, val values: Map<String, StoredValue>) {
    /** Every record this one points to, through any relationship. */
    val linked: Set<RecordRef> get() = values.values.flatMapTo(mutableSetOf()) { it.refs }

    /** The names of the properties whose values differ between this state and [other]. */
    fun changed(from: RecordState): Set<String> =
        (values.keys + from.values.keys).filterTo(mutableSetOf()) { values[it] != from.values[it] }

    companion object {
        /** Every stored property of [record], as [view] holds the binder. */
        fun <R : Any> capture(table: Table<R>, record: R, view: BinderView): RecordState =
            RecordState(RecordRef.of(table, record), table.properties.associate { it.name to it.read(record, view) })

        /** Only the relationships of [record]. */
        fun <R : Any> links(table: Table<R>, record: R, view: BinderView): RecordState = RecordState(
            RecordRef.of(table, record),
            table.properties.filter { it.isLink }.associate { it.name to it.read(record, view) },
        )
    }
}

/**
 * One stored property of a kind of record, named as the iOS model's: how it is read into a
 * [StoredValue] and written back.
 */
class StoredProperty<R : Any> internal constructor(
    val name: String,
    val kind: Kind,
    private val reader: (R, BinderView) -> StoredValue,
    /** Writes a value back; none for a list of the records that point at this one, which follows their links. */
    internal val write: ((R, StoredValue, BinderView) -> R)?,
) {
    enum class Kind {
        /** A value the record keeps. */
        ATTRIBUTE,

        /** A picture or a file kept beside the database, known by its digest (the iOS `.externalStorage`). */
        FILE,

        /** A link to one record. */
        TO_ONE,

        /** The records that point at this one (a section's deadlines): their link, no column of its own. */
        TO_MANY,

        /** A list of records this one keeps itself, the side of a link to many it owns ([ManyLink]). */
        LINKS,
    }

    /**
     * Whether the record keeps this itself, so changing it changes the record: its values, the
     * records it points to, and a list it keeps of its own. Not a list of the records that point
     * at it: those records keep the link, and adding one doesn't change this record.
     */
    val isOwn: Boolean get() = kind != Kind.TO_MANY

    val isLink: Boolean get() = kind == Kind.TO_ONE || kind == Kind.TO_MANY || kind == Kind.LINKS

    fun read(record: R, view: BinderView): StoredValue = reader(record, view)
}

/** The binder as a step or a snapshot holds it: every record of a kind, and the links to many. */
interface BinderView {
    /** Every record of [table], in row order. */
    fun <R : Any> all(table: Table<R>): List<R>

    /** The record of [table] in [row], if there is one. */
    fun <R : Any> row(table: Table<R>, row: Long): R?

    /** The rows [link] links [owner] to, in the order they were linked. */
    fun linked(link: ManyLink, owner: Long): List<Long>

    /** The rows of [table] whose link [linkName] points at [row]. */
    fun <R : Any> pointingAt(table: Table<R>, linkName: String, row: Long): List<Long> {
        val link = table.links.first { it.name == linkName }
        return all(table).filter { link.get(it) == row }.map(table.rowOf)
    }

    /** The owners [link] links to [row]. */
    fun linkedTo(link: ManyLink, row: Long): List<Long>
}

/** The property lists, by kind of record, in the iOS lists' order (`StoreShapeTest`, `UndoReceiptTest`). */
internal object StoredProperties {
    private fun <R : Any, V> attribute(name: String, get: (R) -> V, set: (R, V) -> R) = StoredProperty<R>(
        name,
        StoredProperty.Kind.ATTRIBUTE,
        { record, _ -> StoredValue.Attribute(asStored(get(record))) },
        { record, value, _ ->
            @Suppress("UNCHECKED_CAST")
            set(record, (value as StoredValue.Attribute).value as V)
        },
    )

    /**
     * A value as the database keeps it, so a state read from a step and one read back from the
     * store compare alike: an amount in its one form ([DecimalText.normalized]: 1.50 is 1.5), a
     * moment to the millisecond ([StoredMoment.kept]).
     */
    private fun asStored(value: Any?): Any? = when (value) {
        is BigDecimal -> DecimalText.normalized(value)
        is Instant -> StoredMoment.kept(value)
        else -> value
    }

    private fun <R : Any> file(name: String, get: (R) -> String?, set: (R, String?) -> R) = StoredProperty<R>(
        name,
        StoredProperty.Kind.FILE,
        { record, _ -> StoredValue.File(get(record)) },
        { record, value, _ -> set(record, (value as StoredValue.File).digest) },
    )

    private fun <R : Any> toOne(name: String, table: () -> Table<R>) = StoredProperty<R>(
        name,
        StoredProperty.Kind.TO_ONE,
        { record, _ ->
            val link = table().links.first { it.name == name }
            StoredValue.One(link.get(record)?.let { RecordRef(link.target.type, it) })
        },
        { record, value, view ->
            val link = table().links.first { it.name == name }
            // A record that isn't there any more is no link.
            val row = (value as StoredValue.One).ref?.row?.takeIf { view.row(link.target, it) != null }
            link.set(record, row)
        },
    )

    private fun <R : Any, S : Any> toMany(name: String, own: () -> Table<R>, source: () -> Table<S>, link: String) =
        StoredProperty<R>(
            name,
            StoredProperty.Kind.TO_MANY,
            { record, view ->
                val from = source()
                StoredValue.Many(
                    view.pointingAt(from, link, own().rowOf(record)).mapTo(mutableSetOf()) { RecordRef(from.type, it) },
                )
            },
            null,
        )

    /** The owners of [link] that link to this record (a section's firms). */
    private fun <R : Any> linkedFrom(name: String, own: () -> Table<R>, link: () -> ManyLink) = StoredProperty<R>(
        name,
        StoredProperty.Kind.TO_MANY,
        { record, view ->
            val many = link()
            StoredValue.Many(
                view.linkedTo(many, own().rowOf(record)).mapTo(mutableSetOf()) { RecordRef(many.owner.type, it) },
            )
        },
        null,
    )

    private fun <R : Any> links(name: String, own: () -> Table<R>, link: () -> ManyLink) = StoredProperty<R>(
        name,
        StoredProperty.Kind.LINKS,
        { record, view ->
            val many = link()
            StoredValue.Many(
                view.linked(many, own().rowOf(record)).mapTo(mutableSetOf()) { RecordRef(many.target.type, it) },
            )
        },
        // Written by the step, which keeps the link's rows ([Step.setLinked]).
        { record, _, _ -> record },
    )

    val assets: List<StoredProperty<com.ar.dosarcusina.store.schema.Asset>> by lazy {
        val t = { Tables.assets }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("name", { it.name }) { r, v -> r.copy(name = v) },
            attribute("templateKey", { it.templateKey }) { r, v -> r.copy(templateKey = v) },
            attribute("symbolOverride", { it.symbolOverride }) { r, v -> r.copy(symbolOverride = v) },
            attribute("tintOverrideRaw", { it.tintOverrideRaw }) { r, v -> r.copy(tintOverrideRaw = v) },
            attribute("notes", { it.notes }) { r, v -> r.copy(notes = v) },
            file("photoData", { it.photoData }) { r, v -> r.copy(photoData = v) },
            attribute("valuesData", { it.valuesData }) { r, v -> r.copy(valuesData = v) },
            attribute("customFactsData", { it.customFactsData }) { r, v -> r.copy(customFactsData = v) },
            attribute("isExample", { it.isExample }) { r, v -> r.copy(isExample = v) },
            attribute("createdAt", { it.createdAt }) { r, v -> r.copy(createdAt = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
            toMany("obligations", t, { Tables.obligations }, "asset"),
            toMany("attachments", t, { Tables.attachments }, "asset"),
            toMany("history", t, { Tables.history }, "asset"),
            toMany("measurements", t, { Tables.readings }, "asset"),
            linkedFrom("providers", t) { Tables.providerAssets },
            toOne("parent", t),
            toMany("children", t, t, "parent"),
        )
    }

    val obligations: List<StoredProperty<com.ar.dosarcusina.store.schema.Obligation>> by lazy {
        val t = { Tables.obligations }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("title", { it.title }) { r, v -> r.copy(title = v) },
            attribute("notes", { it.notes }) { r, v -> r.copy(notes = v) },
            attribute("blueprintKey", { it.blueprintKey }) { r, v -> r.copy(blueprintKey = v) },
            attribute("kindRaw", { it.kindRaw }) { r, v -> r.copy(kindRaw = v) },
            attribute("dueDayISO", { it.dueDayISO }) { r, v -> r.copy(dueDayISO = v) },
            attribute("dueMetric", { it.dueMetric }) { r, v -> r.copy(dueMetric = v) },
            attribute("reminderLeadDays", { it.reminderLeadDays }) { r, v -> r.copy(reminderLeadDays = v) },
            attribute("consequenceRaw", { it.consequenceRaw }) { r, v -> r.copy(consequenceRaw = v) },
            attribute("graceDays", { it.graceDays }) { r, v -> r.copy(graceDays = v) },
            attribute("followUpAfterLapse", { it.followUpAfterLapse }) { r, v -> r.copy(followUpAfterLapse = v) },
            attribute("travelMarginDays", { it.travelMarginDays }) { r, v -> r.copy(travelMarginDays = v) },
            attribute("remindersCustomized", { it.remindersCustomized }) { r, v -> r.copy(remindersCustomized = v) },
            attribute("reminderMinuteOfDay", { it.reminderMinuteOfDay }) { r, v -> r.copy(reminderMinuteOfDay = v) },
            attribute("recurrenceData", { it.recurrenceData }) { r, v -> r.copy(recurrenceData = v) },
            attribute("estimatedCostAmount", { it.estimatedCostAmount }) { r, v -> r.copy(estimatedCostAmount = v) },
            attribute("estimatedCostCurrency", { it.estimatedCostCurrency }) { r, v ->
                r.copy(estimatedCostCurrency = v)
            },
            attribute("provider", { it.provider }) { r, v -> r.copy(provider = v) },
            attribute("reference", { it.reference }) { r, v -> r.copy(reference = v) },
            attribute("statusRaw", { it.statusRaw }) { r, v -> r.copy(statusRaw = v) },
            attribute("snoozedUntilISO", { it.snoozedUntilISO }) { r, v -> r.copy(snoozedUntilISO = v) },
            attribute("isExample", { it.isExample }) { r, v -> r.copy(isExample = v) },
            attribute("createdAt", { it.createdAt }) { r, v -> r.copy(createdAt = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
            attribute("cycleKnownAt", { it.cycleKnownAt }) { r, v -> r.copy(cycleKnownAt = v) },
            attribute("remindersData", { it.remindersData }) { r, v -> r.copy(remindersData = v) },
            toOne("asset", t),
            attribute("assetID", { it.assetID }) { r, v -> r.copy(assetID = v) },
            toMany("historyEntries", t, { Tables.history }, "obligation"),
            toMany("attachments", t, { Tables.attachments }, "obligation"),
        )
    }

    val history: List<StoredProperty<com.ar.dosarcusina.store.schema.HistoryEntry>> by lazy {
        val t = { Tables.history }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("kindRaw", { it.kindRaw }) { r, v -> r.copy(kindRaw = v) },
            attribute("title", { it.title }) { r, v -> r.copy(title = v) },
            attribute("occurredAt", { it.occurredAt }) { r, v -> r.copy(occurredAt = v) },
            attribute("metricReading", { it.metricReading }) { r, v -> r.copy(metricReading = v) },
            attribute("totalCostAmount", { it.totalCostAmount }) { r, v -> r.copy(totalCostAmount = v) },
            attribute("totalCostCurrency", { it.totalCostCurrency }) { r, v -> r.copy(totalCostCurrency = v) },
            attribute("note", { it.note }) { r, v -> r.copy(note = v) },
            attribute("reference", { it.reference }) { r, v -> r.copy(reference = v) },
            attribute("rating", { it.rating }) { r, v -> r.copy(rating = v) },
            attribute("isExample", { it.isExample }) { r, v -> r.copy(isExample = v) },
            attribute("cycleDueDayISO", { it.cycleDueDayISO }) { r, v -> r.copy(cycleDueDayISO = v) },
            attribute("nextDueDayISO", { it.nextDueDayISO }) { r, v -> r.copy(nextDueDayISO = v) },
            attribute("previousStatusRaw", { it.previousStatusRaw }) { r, v -> r.copy(previousStatusRaw = v) },
            attribute("previousDueMetric", { it.previousDueMetric }) { r, v -> r.copy(previousDueMetric = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
            toOne("asset", t),
            attribute("assetID", { it.assetID }) { r, v -> r.copy(assetID = v) },
            toOne("obligation", t),
            links("providers", t) { Tables.entryProviders },
            toMany("items", t, { Tables.items }, "entry"),
            toMany("attachments", t, { Tables.attachments }, "historyEntry"),
        )
    }

    val items: List<StoredProperty<com.ar.dosarcusina.store.schema.ServiceItem>> by lazy {
        val t = { Tables.items }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("name", { it.name }) { r, v -> r.copy(name = v) },
            attribute("componentKey", { it.componentKey }) { r, v -> r.copy(componentKey = v) },
            attribute("group", { it.group }) { r, v -> r.copy(group = v) },
            attribute("partBrandOrCode", { it.partBrandOrCode }) { r, v -> r.copy(partBrandOrCode = v) },
            attribute("partSerialNumber", { it.partSerialNumber }) { r, v -> r.copy(partSerialNumber = v) },
            attribute("costAmount", { it.costAmount }) { r, v -> r.copy(costAmount = v) },
            attribute("laborCostAmount", { it.laborCostAmount }) { r, v -> r.copy(laborCostAmount = v) },
            attribute("partsCostAmount", { it.partsCostAmount }) { r, v -> r.copy(partsCostAmount = v) },
            attribute("currency", { it.currency }) { r, v -> r.copy(currency = v) },
            toOne("supplier", t),
            attribute("batchOrTicket", { it.batchOrTicket }) { r, v -> r.copy(batchOrTicket = v) },
            attribute("locationDetail", { it.locationDetail }) { r, v -> r.copy(locationDetail = v) },
            attribute("daysInService", { it.daysInService }) { r, v -> r.copy(daysInService = v) },
            attribute("warrantyMonths", { it.warrantyMonths }) { r, v -> r.copy(warrantyMonths = v) },
            attribute("notes", { it.notes }) { r, v -> r.copy(notes = v) },
            attribute("isExample", { it.isExample }) { r, v -> r.copy(isExample = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
            toOne("entry", t),
            attribute("entryID", { it.entryID }) { r, v -> r.copy(entryID = v) },
            toMany("attachments", t, { Tables.attachments }, "serviceItem"),
        )
    }

    val readings: List<StoredProperty<com.ar.dosarcusina.store.schema.MeasurementLog>> by lazy {
        val t = { Tables.readings }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("kindRaw", { it.kindRaw }) { r, v -> r.copy(kindRaw = v) },
            attribute("name", { it.name }) { r, v -> r.copy(name = v) },
            attribute("value", { it.value }) { r, v -> r.copy(value = v) },
            attribute("secondaryValue", { it.secondaryValue }) { r, v -> r.copy(secondaryValue = v) },
            attribute("unit", { it.unit }) { r, v -> r.copy(unit = v) },
            attribute("recordedAt", { it.recordedAt }) { r, v -> r.copy(recordedAt = v) },
            attribute("unitPriceAmount", { it.unitPriceAmount }) { r, v -> r.copy(unitPriceAmount = v) },
            attribute("unitPriceCurrency", { it.unitPriceCurrency }) { r, v -> r.copy(unitPriceCurrency = v) },
            attribute("isSelfRead", { it.isSelfRead }) { r, v -> r.copy(isSelfRead = v) },
            attribute("referenceMin", { it.referenceMin }) { r, v -> r.copy(referenceMin = v) },
            attribute("referenceMax", { it.referenceMax }) { r, v -> r.copy(referenceMax = v) },
            attribute("source", { it.source }) { r, v -> r.copy(source = v) },
            attribute("notes", { it.notes }) { r, v -> r.copy(notes = v) },
            attribute("isExample", { it.isExample }) { r, v -> r.copy(isExample = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
            attribute("startsCounter", { it.startsCounter }) { r, v -> r.copy(startsCounter = v) },
            attribute("basisRaw", { it.basisRaw }) { r, v -> r.copy(basisRaw = v) },
            toOne("asset", t),
            attribute("assetID", { it.assetID }) { r, v -> r.copy(assetID = v) },
            toMany("attachments", t, { Tables.attachments }, "measurement"),
        )
    }

    val attachments: List<StoredProperty<com.ar.dosarcusina.store.schema.Attachment>> by lazy {
        val t = { Tables.attachments }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("title", { it.title }) { r, v -> r.copy(title = v) },
            attribute("fileName", { it.fileName }) { r, v -> r.copy(fileName = v) },
            attribute("kindRaw", { it.kindRaw }) { r, v -> r.copy(kindRaw = v) },
            attribute("contentType", { it.contentType }) { r, v -> r.copy(contentType = v) },
            file("fileData", { it.fileData }) { r, v -> r.copy(fileData = v) },
            file("thumbnailData", { it.thumbnailData }) { r, v -> r.copy(thumbnailData = v) },
            attribute("byteCount", { it.byteCount }) { r, v -> r.copy(byteCount = v) },
            attribute("sha256", { it.sha256 }) { r, v -> r.copy(sha256 = v) },
            attribute("extractedText", { it.extractedText }) { r, v -> r.copy(extractedText = v) },
            attribute("documentDayISO", { it.documentDayISO }) { r, v -> r.copy(documentDayISO = v) },
            attribute("validUntilISO", { it.validUntilISO }) { r, v -> r.copy(validUntilISO = v) },
            attribute("documentID", { it.documentID }) { r, v -> r.copy(documentID = v) },
            attribute("isArchived", { it.isArchived }) { r, v -> r.copy(isArchived = v) },
            attribute("compactedAt", { it.compactedAt }) { r, v -> r.copy(compactedAt = v) },
            attribute("framingData", { it.framingData }) { r, v -> r.copy(framingData = v) },
            attribute("createdAt", { it.createdAt }) { r, v -> r.copy(createdAt = v) },
            attribute("isExample", { it.isExample }) { r, v -> r.copy(isExample = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
            toMany("pages", t, { Tables.pages }, "attachment"),
            toOne("supersededBy", t),
            toMany("supersedes", t, t, "supersededBy"),
            toOne("asset", t),
            attribute("assetID", { it.assetID }) { r, v -> r.copy(assetID = v) },
            toOne("obligation", t),
            toOne("historyEntry", t),
            toOne("serviceItem", t),
            toOne("measurement", t),
            toOne("provider", t),
        )
    }

    val pages: List<StoredProperty<com.ar.dosarcusina.store.schema.AttachmentPage>> by lazy {
        val t = { Tables.pages }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("index", { it.index }) { r, v -> r.copy(index = v) },
            file("imageData", { it.imageData }) { r, v -> r.copy(imageData = v) },
            toOne("attachment", t),
            attribute("attachmentID", { it.attachmentID }) { r, v -> r.copy(attachmentID = v) },
        )
    }

    val providers: List<StoredProperty<com.ar.dosarcusina.store.schema.Provider>> by lazy {
        val t = { Tables.providers }
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("name", { it.name }) { r, v -> r.copy(name = v) },
            attribute("trades", { it.trades }) { r, v -> r.copy(trades = v) },
            attribute("phone", { it.phone }) { r, v -> r.copy(phone = v) },
            attribute("email", { it.email }) { r, v -> r.copy(email = v) },
            attribute("address", { it.address }) { r, v -> r.copy(address = v) },
            attribute("notes", { it.notes }) { r, v -> r.copy(notes = v) },
            attribute("manualRating", { it.manualRating }) { r, v -> r.copy(manualRating = v) },
            attribute("wouldCallAgain", { it.wouldCallAgain }) { r, v -> r.copy(wouldCallAgain = v) },
            attribute("contactIdentifier", { it.contactIdentifier }) { r, v -> r.copy(contactIdentifier = v) },
            attribute("taxID", { it.taxID }) { r, v -> r.copy(taxID = v) },
            attribute("isExample", { it.isExample }) { r, v -> r.copy(isExample = v) },
            attribute("createdAt", { it.createdAt }) { r, v -> r.copy(createdAt = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
            links("assets", t) { Tables.providerAssets },
            linkedFrom("historyEntries", t) { Tables.entryProviders },
            toMany("suppliedItems", t, { Tables.items }, "supplier"),
            toMany("attachments", t, { Tables.attachments }, "provider"),
        )
    }

    val lessons: List<StoredProperty<com.ar.dosarcusina.store.schema.IssuerLesson>> by lazy {
        listOf(
            attribute("id", { it.id }) { r, v -> r.copy(id = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("issuerKey", { it.issuerKey }) { r, v -> r.copy(issuerKey = v) },
            attribute("issuerName", { it.issuerName }) { r, v -> r.copy(issuerName = v) },
            attribute("kindRaw", { it.kindRaw }) { r, v -> r.copy(kindRaw = v) },
            attribute("fieldKey", { it.fieldKey }) { r, v -> r.copy(fieldKey = v) },
            attribute("label", { it.label }) { r, v -> r.copy(label = v) },
            attribute("categoryKey", { it.categoryKey }) { r, v -> r.copy(categoryKey = v) },
            attribute("createdAt", { it.createdAt }) { r, v -> r.copy(createdAt = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
        )
    }

    val templates: List<StoredProperty<com.ar.dosarcusina.store.schema.CategoryTemplate>> by lazy {
        listOf(
            attribute("key", { it.key }) { r, v -> r.copy(key = v) },
            attribute("copyID", { it.copyID }) { r, v -> r.copy(copyID = v) },
            attribute("name", { it.name }) { r, v -> r.copy(name = v) },
            attribute("summary", { it.summary }) { r, v -> r.copy(summary = v) },
            attribute("symbol", { it.symbol }) { r, v -> r.copy(symbol = v) },
            attribute("tintRaw", { it.tintRaw }) { r, v -> r.copy(tintRaw = v) },
            attribute("heroStyleRaw", { it.heroStyleRaw }) { r, v -> r.copy(heroStyleRaw = v) },
            attribute("isBuiltIn", { it.isBuiltIn }) { r, v -> r.copy(isBuiltIn = v) },
            attribute("builtInVersion", { it.builtInVersion }) { r, v -> r.copy(builtInVersion = v) },
            attribute("homeOrder", { it.homeOrder }) { r, v -> r.copy(homeOrder = v) },
            attribute("isOnHome", { it.isOnHome }) { r, v -> r.copy(isOnHome = v) },
            attribute("boxGroupingRaw", { it.boxGroupingRaw }) { r, v -> r.copy(boxGroupingRaw = v) },
            attribute("lockedEverywhereAt", { it.lockedEverywhereAt }) { r, v -> r.copy(lockedEverywhereAt = v) },
            attribute("sectionsData", { it.sectionsData }) { r, v -> r.copy(sectionsData = v) },
            attribute("blueprintsData", { it.blueprintsData }) { r, v -> r.copy(blueprintsData = v) },
            attribute("componentsData", { it.componentsData }) { r, v -> r.copy(componentsData = v) },
            attribute("pocketsRaw", { it.pocketsRaw }) { r, v -> r.copy(pocketsRaw = v) },
            attribute("behaviorData", { it.behaviorData }) { r, v -> r.copy(behaviorData = v) },
            attribute("createdAt", { it.createdAt }) { r, v -> r.copy(createdAt = v) },
            attribute("updatedAt", { it.updatedAt }) { r, v -> r.copy(updatedAt = v) },
        )
    }
}
