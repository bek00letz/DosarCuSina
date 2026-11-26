package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.text.PaymentCardNumbers
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.FreeText
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem

/**
 * Before the unit of work kept card numbers out of every record's words ([FreeText]), a card number
 * typed into a row under Date importante, a note, a title or any other text was kept whole; so was
 * one in a backup's notes or titles. Every record whose words hold one is offered, in plain words, to
 * keep only the last four digits, by the same rule a save uses, as the iOS app's `CardNumbersStep`. It
 * asks, because it changes what the person sees. A record saved again for any other reason is masked
 * by that save.
 *
 * The list names each record by its own name and its section's, each masked: never with the number.
 */
object CardNumbersStep : DataRepairStep {
    override val id = DataRepairStepId.CARD_NUMBERS
    override val group = DataRepairGroup.CARD_NUMBERS

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> =
        FreeText.lists.flatMap { candidates(typed(it), scan.view) }.map { subject ->
            DataRepairFinding(
                id = DataRepairFinding.id(id, subject.record.type, subject.record.key),
                step = id,
                subject = subject,
            )
        }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val records = findings.mapNotNull { (it.subject as? DataRepairSubject.CardNumbers)?.record }
        for (record in records) {
            val list = FreeText.lists.firstOrNull { it.table.type == record.type } ?: continue
            mask(typed(list), record.key, step)
        }
    }

    private fun <R : Any> candidates(list: FreeText.Lists<R>, view: BinderView): List<DataRepairSubject.CardNumbers> =
        view.all(list.table).mapNotNull { record ->
            if (FreeText.holding(record, list, view).isEmpty()) return@mapNotNull null
            val (name, section) = names(record, view)
            val shown = PaymentCardNumbers.redact(name)
            DataRepairSubject.CardNumbers(
                record = RecordKey(list.table.type, list.table.keyOf(record)),
                name = shown,
                section = section?.let { PaymentCardNumbers.redact(it) }?.takeIf { it != shown },
            )
        }

    /** Masks the record of [list] with [key] as it is now; one that holds no number any more stays. */
    private fun <R : Any> mask(list: FreeText.Lists<R>, key: String, step: Step) {
        val record = step.find(list.table, key) ?: return
        step.update(FreeText.masked(record, list, step))
    }

    /** What the list calls a record, and the section it belongs to. */
    private fun names(record: Any, view: BinderView): Pair<String, String?> {
        fun section(row: Long?): String? = row?.let { view.row(Tables.assets, it) }?.name
        return when (record) {
            is Asset -> record.name to null
            is Obligation -> record.title to section(record.asset)
            is HistoryEntry -> record.title to section(record.asset)
            is ServiceItem -> record.name to section(record.entry?.let { view.row(Tables.history, it) }?.asset)
            is MeasurementLog -> record.name to section(record.asset)
            is Attachment -> (record.title ?: record.fileName) to section(record.asset)
            is Provider -> record.name to null
            is CategoryTemplate -> record.name to null
            else -> "" to null
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun typed(list: FreeText.Lists<*>): FreeText.Lists<Any> = list as FreeText.Lists<Any>
}
