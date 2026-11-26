package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.catalog.ComponentCatalog
import com.ar.dosarcusina.core.capture.LabourLine
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.repairs.RepairReading
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.ServiceItem
import com.ar.dosarcusina.store.schema.keptComponents

/**
 * The one way a record's parts and jobs are written, as the iOS app's `HouseholdMutations.addItems`
 * (ios/DosarCuSina/Services/History/HistoryActions.swift): each line's part worked out from the section's
 * category ([ComponentCatalog]), and labour kept as the work's cost, never a part ([LabourLine]). A visit, a
 * repair, a completion and an import write theirs here. Nothing here saves: the step's unit does.
 */
object HistoryItems {
    /** The parts and jobs [section]'s category lists; none when its record isn't there. */
    fun components(view: BinderView, section: Asset): List<ComponentDefinition> =
        RepairReading.categories(view)[section.templateKey]?.keptComponents?.items.orEmpty()

    /** Writes [drafts] as [entry]'s parts and jobs, in [step], each worked out from its section's category. */
    fun add(step: Step, drafts: List<LineItemDraft>, entry: HistoryEntry) {
        if (drafts.isEmpty()) return
        val components = entry.asset?.let { step.row(Tables.assets, it) }?.let { components(step, it) }.orEmpty()
        for (draft in drafts) step.insert(item(draft, components, entry))
    }

    /** The line [draft] is, kept in [entry]: labour is the visit's work, never a part, and what it cost is labour. */
    private fun item(draft: LineItemDraft, components: List<ComponentDefinition>, entry: HistoryEntry): ServiceItem {
        val isLabour = draft.componentKey == null && LabourLine.matches(draft.name)
        val key = if (isLabour) null else draft.componentKey ?: ComponentCatalog.key(draft.name, components)
        val currency = (draft.cost ?: draft.laborCost ?: draft.partsCost)?.currency ?: Money.DEFAULT_CURRENCY
        val labour = if (isLabour) draft.laborCost ?: draft.cost else draft.laborCost
        return ServiceItem(
            name = draft.name,
            componentKey = key,
            group = draft.group ?: components.firstOrNull { it.key == key }?.group,
            partBrandOrCode = draft.partBrandOrCode,
            partSerialNumber = draft.partSerialNumber,
            costAmount = if (isLabour && draft.laborCost == null) null else draft.cost?.amount,
            laborCostAmount = labour?.amount,
            partsCostAmount = draft.partsCost?.amount,
            currency = currency,
            supplier = draft.supplier,
            batchOrTicket = draft.batchOrTicket,
            locationDetail = draft.locationDetail,
            daysInService = draft.daysInService,
            warrantyMonths = draft.warrantyMonths,
            notes = draft.notes,
            isExample = entry.isExample,
            entry = entry.pk,
        )
    }

    /**
     * Keeps [item] as a visit saved today keeps its labour: no part, its cost the labour's
     * (`LabourPartsStep.keepAsLabour`). What the visit cost stays the same.
     */
    fun keptAsLabour(item: ServiceItem): ServiceItem {
        val moves = item.laborCostAmount == null && item.costAmount != null
        return item.copy(
            componentKey = null,
            group = null,
            laborCostAmount = if (moves) item.costAmount else item.laborCostAmount,
            costAmount = if (moves) null else item.costAmount,
        )
    }

    /** Whether [item] is kept as a part of one's own (`custom.…`), one the category doesn't list. */
    fun isOwnPart(item: ServiceItem): Boolean =
        item.componentKey?.startsWith(ComponentCatalog.CUSTOM_KEY_PREFIX) == true
}
