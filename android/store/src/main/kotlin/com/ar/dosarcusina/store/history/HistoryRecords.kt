package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.core.history.HistoryItemSnapshot
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import java.math.BigDecimal

/**
 * A section's history as the binder keeps it, read the one way: its records, their parts and jobs, who did
 * them and the papers filed with them, as the iOS app's `Asset.history`, `HistoryEntry.items`,
 * `providerNames` and `HistoryItemSnapshot.items(of:)` read them.
 */
object HistoryRecords {
    /** [section]'s records of history, in row order. */
    fun of(view: BinderView, section: Asset): List<HistoryEntry> =
        view.pointingAt(Tables.history, "asset", section.pk).mapNotNull { view.row(Tables.history, it) }

    /** [entry]'s parts and jobs, in row order. */
    fun items(view: BinderView, entry: HistoryEntry): List<ServiceItem> =
        view.pointingAt(Tables.items, "entry", entry.pk).mapNotNull { view.row(Tables.items, it) }

    /** Who did [entry]'s work, in the order it keeps them. */
    fun providers(view: BinderView, entry: HistoryEntry): List<Provider> =
        view.linked(Tables.entryProviders, entry.pk).mapNotNull { view.row(Tables.providers, it) }

    /** Who did [entry]'s work, by name, in alphabetical order (`HistoryEntry.providerNames`). */
    fun providerNames(view: BinderView, entry: HistoryEntry): List<String> =
        providers(view, entry).map { it.name }.sorted()

    /** The papers filed with [entry], in row order. */
    fun papers(view: BinderView, entry: HistoryEntry): List<Attachment> =
        view.pointingAt(Tables.attachments, "historyEntry", entry.pk).mapNotNull { view.row(Tables.attachments, it) }

    /**
     * The line items of [section]'s history, each with the facts of its record: what the maintenance log
     * reads ([com.ar.dosarcusina.core.history.MaintenanceLog]).
     */
    fun snapshots(view: BinderView, section: Asset): List<HistoryItemSnapshot> = of(view, section).flatMap { entry ->
        val providers = providers(view, entry)
        val names = providers.map { it.name }.sorted()
        items(view, entry).map { item ->
            HistoryItemSnapshot(
                componentKey = item.componentKey, name = item.name, occurredAt = entry.occurredAt,
                entryId = entry.id, id = item.id, assetId = section.id, metricReading = entry.metricReading,
                cost = item.totalCost, partBrandOrCode = item.partBrandOrCode,
                supplierName = item.supplier?.let { view.row(Tables.providers, it) }?.name,
                providerNames = names, providerIds = providers.map { it.id },
            )
        }
    }
}

/** The record's own total, as stored; none when it has none. */
val HistoryEntry.totalCost: Money?
    get() = totalCostAmount?.let { Money(it, totalCostCurrency ?: Money.DEFAULT_CURRENCY) }

/** What the line cost: its own amount, else its labour and parts added up; none when it has none. */
val ServiceItem.totalCost: Money?
    get() = when {
        costAmount != null -> Money(costAmount, currency)
        laborCostAmount == null && partsCostAmount == null -> null
        else -> Money((laborCostAmount ?: BigDecimal.ZERO) + (partsCostAmount ?: BigDecimal.ZERO), currency)
    }
