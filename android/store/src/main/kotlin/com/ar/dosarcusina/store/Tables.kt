package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.BinderDatabase
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.HistoryEntryProviders
import com.ar.dosarcusina.store.schema.IssuerLesson
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ProviderAssets
import com.ar.dosarcusina.store.schema.Rows
import com.ar.dosarcusina.store.schema.ServiceItem
import java.time.Instant
import kotlin.reflect.KClass

/**
 * One kind of record the store keeps, under the iOS model's name ([type]): how its rows are read
 * and written, what identifies one, its links to one record ([links]), when it last changed
 * ([updatedAt], none for a document's page, which is part of its document), and every stored
 * property, named as the iOS app's `storedProperties` ([properties], `StoredProperties`).
 *
 * Only the store reads and writes rows; everything else goes through a step of the unit of work
 * ([Step]), which finds a kind of record here ([Tables]).
 */
class Table<R : Any> internal constructor(
    /** The iOS model's name, which is also the table's. */
    val type: String,
    internal val kind: KClass<R>,
    internal val rowOf: (R) -> Long,
    internal val withRow: (R, Long) -> R,
    /** What identifies the record across contexts, as the iOS app's `recordKey`: its id, a category's key. */
    val keyOf: (R) -> String,
    /** An empty record, to bring back one a step deleted; every property is then written. */
    internal val blank: () -> R,
    internal val readAll: suspend (BinderDatabase) -> List<R>,
    internal val rows: (BinderDatabase) -> Rows<R>,
    /** When it last changed, for the records that keep it (`ChangeTimed`); none for one that is part of another. */
    internal val updatedAt: ((R) -> Instant)? = null,
    internal val withUpdatedAt: ((R, Instant) -> R)? = null,
    links: () -> List<ToOne<R>>,
    properties: () -> List<StoredProperty<R>>,
) {
    /** Its links to one record: what lets go when the record it points at goes. */
    val links: List<ToOne<R>> by lazy(links)

    /** Every stored attribute and relationship, by its name in the iOS schema. */
    val properties: List<StoredProperty<R>> by lazy(properties)

    override fun toString(): String = type
}

/** A link to one record: the row it points at, in the column named as the iOS relationship. */
class ToOne<R : Any> internal constructor(
    val name: String,
    target: () -> Table<*>,
    internal val get: (R) -> Long?,
    internal val set: (R, Long?) -> R,
) {
    val target: Table<*> by lazy(target)
}

/**
 * A link to many records kept on one side, a table of its own ([ProviderAssets],
 * [HistoryEntryProviders]): the sections a firm looks after, who did the work of a record of
 * history. Part of the owner's own state, so a change to it is the owner's.
 */
class ManyLink internal constructor(
    /** The iOS relationship's name on the owner. */
    val name: String,
    owner: () -> Table<*>,
    target: () -> Table<*>,
    /** Every link as (owner row, target row), in the order it was written. */
    internal val readAll: suspend (BinderDatabase) -> List<Pair<Long, Long>>,
    internal val deleteOf: suspend (BinderDatabase, Long) -> Unit,
    internal val insert: suspend (BinderDatabase, Long, Long) -> Unit,
) {
    val owner: Table<*> by lazy(owner)
    val target: Table<*> by lazy(target)

    override fun toString(): String = "${owner.type}.$name"
}

/** Every kind of record the store keeps, in the iOS schema's order, and the links to many. */
// One descriptor per model.
@Suppress("TooManyFunctions")
object Tables {
    val templates: Table<CategoryTemplate> = Table(
        type = "CategoryTemplate", kind = CategoryTemplate::class,
        rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.key }, blank = { CategoryTemplate() },
        readAll = { it.templates().all() }, rows = { it.templates() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = { emptyList() },
        properties = { StoredProperties.templates },
    )

    val assets: Table<Asset> = Table(
        type = "Asset", kind = Asset::class, rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { Asset() },
        readAll = { it.assets().all() }, rows = { it.assets() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = { listOf(ToOne("parent", { assets }, { it.parent }) { r, v -> r.copy(parent = v) }) },
        properties = { StoredProperties.assets },
    )

    val obligations: Table<Obligation> = Table(
        type = "Obligation", kind = Obligation::class, rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { Obligation() },
        readAll = { it.obligations().all() }, rows = { it.obligations() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = { listOf(ToOne("asset", { assets }, { it.asset }) { r, v -> r.copy(asset = v) }) },
        properties = { StoredProperties.obligations },
    )

    val history: Table<HistoryEntry> = Table(
        type = "HistoryEntry", kind = HistoryEntry::class, rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { HistoryEntry() },
        readAll = { it.history().all() }, rows = { it.history() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = {
            listOf(
                ToOne("asset", { assets }, { it.asset }) { r, v -> r.copy(asset = v) },
                ToOne("obligation", { obligations }, { it.obligation }) { r, v -> r.copy(obligation = v) },
            )
        },
        properties = { StoredProperties.history },
    )

    val items: Table<ServiceItem> = Table(
        type = "ServiceItem", kind = ServiceItem::class, rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { ServiceItem() },
        readAll = { it.items().all() }, rows = { it.items() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = {
            listOf(
                ToOne("supplier", { providers }, { it.supplier }) { r, v -> r.copy(supplier = v) },
                ToOne("entry", { history }, { it.entry }) { r, v -> r.copy(entry = v) },
            )
        },
        properties = { StoredProperties.items },
    )

    val readings: Table<MeasurementLog> = Table(
        type = "MeasurementLog", kind = MeasurementLog::class,
        rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { MeasurementLog() },
        readAll = { it.readings().all() }, rows = { it.readings() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = { listOf(ToOne("asset", { assets }, { it.asset }) { r, v -> r.copy(asset = v) }) },
        properties = { StoredProperties.readings },
    )

    val attachments: Table<Attachment> = Table(
        type = "Attachment", kind = Attachment::class, rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { Attachment() },
        readAll = { it.attachments().all() }, rows = { it.attachments() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = {
            listOf(
                ToOne("supersededBy", { attachments }, { it.supersededBy }) { r, v -> r.copy(supersededBy = v) },
                ToOne("asset", { assets }, { it.asset }) { r, v -> r.copy(asset = v) },
                ToOne("obligation", { obligations }, { it.obligation }) { r, v -> r.copy(obligation = v) },
                ToOne("historyEntry", { history }, { it.historyEntry }) { r, v -> r.copy(historyEntry = v) },
                ToOne("serviceItem", { items }, { it.serviceItem }) { r, v -> r.copy(serviceItem = v) },
                ToOne("measurement", { readings }, { it.measurement }) { r, v -> r.copy(measurement = v) },
                ToOne("provider", { providers }, { it.provider }) { r, v -> r.copy(provider = v) },
            )
        },
        properties = { StoredProperties.attachments },
    )

    val pages: Table<AttachmentPage> = Table(
        type = "AttachmentPage", kind = AttachmentPage::class,
        rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { AttachmentPage() },
        readAll = { it.pages().all() }, rows = { it.pages() },
        links = { listOf(ToOne("attachment", { attachments }, { it.attachment }) { r, v -> r.copy(attachment = v) }) },
        properties = { StoredProperties.pages },
    )

    val providers: Table<Provider> = Table(
        type = "Provider", kind = Provider::class, rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { Provider() },
        readAll = { it.providers().all() }, rows = { it.providers() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = { emptyList() },
        properties = { StoredProperties.providers },
    )

    val lessons: Table<IssuerLesson> = Table(
        type = "IssuerLesson", kind = IssuerLesson::class, rowOf = { it.pk }, withRow = { r, pk -> r.copy(pk = pk) },
        keyOf = { it.id.toString() }, blank = { IssuerLesson() },
        readAll = { it.lessons().all() }, rows = { it.lessons() },
        updatedAt = { it.updatedAt }, withUpdatedAt = { r, t -> r.copy(updatedAt = t) },
        links = { emptyList() },
        properties = { StoredProperties.lessons },
    )

    /** The sections a firm looks after (`Provider.assets`). */
    val providerAssets: ManyLink = ManyLink(
        name = "assets", owner = { providers }, target = { assets },
        readAll = { db -> db.providerAssets().all().mapNotNull { row -> pair(row.provider, row.asset) } },
        deleteOf = { db, owner -> db.providerAssets().deleteOfProvider(owner) },
        insert = { db, owner, target -> db.providerAssets().insert(ProviderAssets(provider = owner, asset = target)) },
    )

    /** Who did the work of a record of history (`HistoryEntry.providers`). */
    val entryProviders: ManyLink = ManyLink(
        name = "providers", owner = { history }, target = { providers },
        readAll = { db -> db.entryProviders().all().mapNotNull { row -> pair(row.historyEntry, row.provider) } },
        deleteOf = { db, owner -> db.entryProviders().deleteOfEntry(owner) },
        insert = { db, owner, target ->
            db.entryProviders().insert(HistoryEntryProviders(historyEntry = owner, provider = target))
        },
    )

    /** Every kind of record, in the iOS schema's order. */
    val all: List<Table<*>> by lazy {
        listOf(templates, assets, obligations, history, items, readings, attachments, pages, providers, lessons)
    }

    /** Every link to many records. */
    val manyLinks: List<ManyLink> by lazy { listOf(providerAssets, entryProviders) }

    /** The kind of record [type] names (the iOS model's name). */
    fun named(type: String): Table<*>? = all.firstOrNull { it.type == type }

    /** The kind of [record]. */
    @Suppress("UNCHECKED_CAST")
    fun <R : Any> of(record: R): Table<R> =
        requireNotNull(all.firstOrNull { it.kind.isInstance(record) }) {
            "Not a record of the binder: ${record::class.simpleName}"
        } as Table<R>

    private fun pair(owner: Long?, target: Long?): Pair<Long, Long>? =
        if (owner != null && target != null) owner to target else null
}
