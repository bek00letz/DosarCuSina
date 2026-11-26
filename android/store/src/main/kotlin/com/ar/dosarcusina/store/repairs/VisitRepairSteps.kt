package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.capture.LabourLine
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.history.HistoryItems
import com.ar.dosarcusina.store.history.HistoryRecords
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.ServiceItem
import java.time.ZoneId
import java.util.UUID

// The repairs for papers and visits an earlier version filed wrongly, as the iOS app's `CaptureRepairs`
// (ios/DosarCuSina/Services/Documents/CaptureRepairs.swift) and `LabourPartsStep`
// (ios/DosarCuSina/Services/Repairs/LabourPartsStep.swift). Each lists what it would change and changes only
// what the owner approved, checked again first; each is idempotent.

/**
 * Documents moved here that still point at another section's deadline or visit, as the iOS app's
 * `StaleDocumentLinksStep`: the move left the old place's links. Applying drops them; the document stays
 * where it is now, with its pages and everything read from it.
 */
object StaleDocumentLinksStep : DataRepairStep {
    override val id = DataRepairStepId.STALE_DOCUMENT_LINKS
    override val group = DataRepairGroup.MOVED_DOCUMENTS

    private fun candidates(view: BinderView): List<DataRepairSubject.StaleLinks> =
        view.all(Tables.attachments).mapNotNull { document ->
            val home = document.asset ?: return@mapNotNull null
            val obligation = document.obligation?.let { view.row(Tables.obligations, it) }?.takeIf { it.asset != home }
            val entry = document.historyEntry?.let { view.row(Tables.history, it) }?.takeIf { it.asset != home }
            if (obligation == null && entry == null) return@mapNotNull null
            DataRepairSubject.StaleLinks(
                document.id, obligation?.id, entry?.id, document.title ?: document.fileName,
                view.row(Tables.assets, home)?.name.orEmpty(),
            )
        }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> = candidates(scan.view).map {
        DataRepairFinding(DataRepairFinding.id(id, RepairReading.key(it.attachmentId)), id, it)
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNull { (it.subject as? DataRepairSubject.StaleLinks)?.attachmentId }.toSet()
        for (document in step.all(Tables.attachments).filter { it.id in approved }) {
            val home = document.asset
            val obligation = document.obligation?.let { step.row(Tables.obligations, it) }
            val entry = document.historyEntry?.let { step.row(Tables.history, it) }
            step.update(
                document.copy(
                    obligation = document.obligation.takeUnless { obligation != null && obligation.asset != home },
                    historyEntry = document.historyEntry.takeUnless { entry != null && entry.asset != home },
                ),
            )
        }
    }
}

/**
 * Visits saved without their invoice while the one invoice that fits sits loose beside them, as the iOS app's
 * `VisitsWithoutInvoiceStep`: the visit form was given a photo already in the binder and saved without it.
 * The invoice is the only one filed in the week before the visit, or on its day, and belongs to no record. A
 * visit with two possible invoices isn't offered: the owner would have to guess.
 */
object VisitsWithoutInvoiceStep : DataRepairStep {
    override val id = DataRepairStepId.VISITS_WITHOUT_INVOICE
    override val group = DataRepairGroup.VISITS_WITHOUT_INVOICE

    private const val WEEK = 7
    private val visitKinds = setOf(HistoryKind.MAINTENANCE.raw, HistoryKind.REPAIR.raw)

    /** Each visit that may have lost its invoice, with the one invoice that fits. */
    fun candidates(view: BinderView, zone: ZoneId): List<Pair<UUID, UUID>> {
        val used = HashSet<Long>()
        val found = ArrayList<Pair<UUID, UUID>>()
        for (entry in view.all(Tables.history).sortedBy { it.occurredAt }) {
            val invoice = looseInvoice(view, entry, zone, used) ?: continue
            used += invoice.pk
            found += entry.id to invoice.id
        }
        return found
    }

    /**
     * The one invoice that fits [entry], when it is a visit saved without a paper: filed on its section in the
     * week before it or on its day, belonging to no record, not taken by an earlier visit ([used]).
     */
    private fun looseInvoice(view: BinderView, entry: HistoryEntry, zone: ZoneId, used: Set<Long>): Attachment? {
        val asset = entry.asset
        val isVisit = entry.kindRaw in visitKinds && entry.obligation == null && asset != null
        if (!isVisit || HistoryRecords.papers(view, entry).isNotEmpty()) return null
        val visitDay = CalendarDay.of(entry.occurredAt, zone)
        val weekBefore = visitDay.addingDays(-WEEK)
        return view.pointingAt(Tables.attachments, "asset", requireNotNull(asset))
            .mapNotNull { view.row(Tables.attachments, it) }
            .filter { invoice ->
                val isLoose = invoice.kindRaw == INVOICE && invoice.historyEntry == null && invoice.pk !in used
                isLoose && filedDay(invoice, zone) in weekBefore..visitDay
            }
            .singleOrNull()
    }

    private fun filedDay(invoice: Attachment, zone: ZoneId): CalendarDay =
        StoredDay.day(invoice.documentDayISO) ?: CalendarDay.of(invoice.createdAt, zone)

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val entries = scan.view.all(Tables.history).reversed().associateBy { it.id }
        return candidates(scan.view, scan.context.zone).map { (visit, invoice) ->
            val entry = entries[visit]
            val section = entry?.asset?.let { scan.view.row(Tables.assets, it) }?.name.orEmpty()
            val day = CalendarDay.of(requireNotNull(entry).occurredAt, scan.context.zone)
            DataRepairFinding(
                DataRepairFinding.id(id, RepairReading.key(visit), RepairReading.key(invoice)), id,
                DataRepairSubject.VisitInvoice(visit, invoice, day, section),
            )
        }
    }

    /** Links each approved invoice to its visit. An invoice already linked to a record is left alone. */
    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        for (pair in findings.mapNotNull { it.subject as? DataRepairSubject.VisitInvoice }) link(step, pair)
    }

    private fun link(step: Step, pair: DataRepairSubject.VisitInvoice) {
        val entry = step.all(Tables.history).firstOrNull { it.id == pair.visitId }
        val invoice = step.all(Tables.attachments).firstOrNull { it.id == pair.invoiceId }
        if (entry == null || invoice == null || invoice.historyEntry != null) return
        val firm = invoice.provider ?: step.linked(Tables.entryProviders, entry.pk).firstOrNull()
        step.update(invoice.copy(historyEntry = entry.pk, provider = firm))
    }

    private const val INVOICE = "invoice"
}

/**
 * Labour kept as a part, as the iOS app's `LabourPartsStep`: before labour had a rule of its own
 * ([LabourLine]), an invoice's labour line („Manoperă”, „Mână de lucru”) was saved as a part of one's own
 * (`custom.<slug>`), so it was listed with the parts and counted when a part was last done. This finds every
 * line of a visit that is a part of one's own and whose name is labour, and keeps it as the visit's labour:
 * no part, its cost the labour's ([HistoryItems.keptAsLabour]). What the visit cost stays the same. It asks
 * first: it changes what Istoric lists.
 */
object LabourPartsStep : DataRepairStep {
    override val id = DataRepairStepId.LABOUR_PARTS
    override val group = DataRepairGroup.LABOUR

    /** Lines kept as a part of one's own whose words are labour. A catalog part is never one. */
    private fun candidates(view: BinderView): List<ServiceItem> = view.all(Tables.items).sortedBy { it.name }
        .filter { it.isVisitLine && HistoryItems.isOwnPart(it) && LabourLine.matches(it.name) }

    /** A line of a record, not an example's. */
    private val ServiceItem.isVisitLine: Boolean get() = !isExample && entry != null

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> = candidates(scan.view).map { item ->
        val entry = item.entry?.let { scan.view.row(Tables.history, it) }
        val section = entry?.asset?.let { scan.view.row(Tables.assets, it) }
        val place = section?.name ?: entry?.title ?: item.name
        val day = entry?.let { CalendarDay.of(it.occurredAt, scan.context.zone) }
        DataRepairFinding(
            DataRepairFinding.id(id, RepairReading.key(item.id)), id,
            DataRepairSubject.LabourPart(item.id, place, item.name, day),
        )
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNull { (it.subject as? DataRepairSubject.LabourPart)?.itemId }.toSet()
        // Checked again: a line renamed or changed since the list was made stays.
        for (item in candidates(step)) if (item.id in approved) step.update(HistoryItems.keptAsLabour(item))
    }
}
