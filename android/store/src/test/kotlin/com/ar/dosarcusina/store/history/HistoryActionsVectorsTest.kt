package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.history.MaintenanceLog
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.Undoable
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.examples.ExampleSectionQuestion
import com.ar.dosarcusina.store.obligations.DeadlineReminders
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.obligations.dueDay
import com.ar.dosarcusina.store.providers.ProviderActions
import com.ar.dosarcusina.store.providers.ProviderTrade
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.LowerReadingAsked
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptValues
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.math.BigDecimal
import java.time.Instant

/**
 * The iOS app's answers for what every history action leaves in the binder (shared/test-vectors/history/
 * actions.json), run through this store's own actions on the real Room store: each case's section, firms and
 * deadline are made, its earlier actions taken, then its action, and the history, the readings, the deadline,
 * the firms, the section's hero value and the parts its history follows, and what undo gives back, must be the
 * iOS app's. A visit filed from its form goes through [VisitDraft.filing] and [HistoryActions.file], as the
 * iOS form files through `CaptureFiler`.
 */
class HistoryActionsVectorsTest {
    private class Made(
        val binder: TestBinderStore,
        val asset: Asset,
        val firms: List<Provider>,
        val deadline: Obligation?,
    ) {
        val entries = ArrayList<HistoryEntry>()
        val history = HistoryActions(binder.unit, vectorWording)
        val obligations = ObligationActions(binder.unit, zone = { bucharest })
    }

    private fun make(case: JsonObject): Made {
        val binder = TestBinderStore(now = Instant.ofEpochSecond(case.text("now").toLong()))
        binder.launch.installBuiltIns(binder.now)
        val json = requireNotNull(case.obj("section"))
        val asset = binder.unit.performPrivate { step ->
            val asset = step.insert(Asset(name = json.text("name"), templateKey = json.text("category")))
            val values = requireNotNull(FieldValues.codec.decode(json.getValue("values")))
            val valued = asset.withKeptValues(KeptObject.made(values, FieldValues.codec))
            step.update(valued)
            for (reading in json.objects("readings")) {
                step.insert(
                    MeasurementLog(
                        kindRaw = "odometer", value = reading.text("value").toDouble(), unit = "km",
                        recordedAt = requireNotNull(MachineText.moment(reading.text("at"))), asset = asset.pk,
                    ),
                )
            }
            valued
        }
        val firms = case.texts("firms").map { name ->
            ProviderActions(binder.unit).create(name, listOf(ProviderTrade.MECHANIC), linkedTo = listOf(asset))
        }
        val deadline = case.obj("deadline")?.let { start ->
            val blueprints = DeadlineReminders.blueprintsOf(binder.snapshot(), asset)
            ObligationActions(binder.unit, zone = { bucharest }).create(
                blueprints.first { it.key == start.text("blueprint") }, asset,
                firstDue = CalendarDay.parse(start.text("firstDue")),
            )
        }
        return Made(binder, asset, firms, deadline)
    }

    private fun on(action: JsonObject): Instant? = action.textOrNull("on")?.toLong()?.let(Instant::ofEpochSecond)

    private fun lower(action: JsonObject): LowerReadingAnswer? = when (action.textOrNull("lowerReading")) {
        "newCounter" -> LowerReadingAnswer.NEW_COUNTER
        "wasEstimate" -> LowerReadingAnswer.WAS_ESTIMATE
        "correctOld" -> LowerReadingAnswer.CORRECT_OLD
        "keepAside" -> LowerReadingAnswer.KEEP_ASIDE
        else -> null
    }

    private fun items(action: JsonObject, key: String = "items"): List<LineItemDraft> = action.objects(key).map {
        LineItemDraft(
            name = it.textOrNull("name").orEmpty(), componentKey = it.textOrNull("componentKey"),
            cost = it.money("cost"), laborCost = it.money("laborCost"), partsCost = it.money("partsCost"),
        )
    }

    /** Runs [action] on [made]: its receipt when it gives one. */
    private fun run(made: Made, action: JsonObject): UndoReceipt? {
        val entry = action.intOrNull("entry")?.let { made.entries[it] }
        return when (val name = action.text("do")) {
            "recordVisit" -> made.history.recordVisit(made.asset, visit(made, action), lower(action))
                .also { made.entries += it.value }.receipt
            "record" -> {
                made.entries += made.history.record(made.asset, record(made, action), lower(action))
                null
            }
            "file" -> file(made, action).also { made.entries += it.value }.receipt
            "addNote" -> made.history.addNote(made.asset, action.textOrNull("text").orEmpty(), on(action))
                .also { made.entries += it.value }.receipt
            "complete" -> made.obligations.complete(
                requireNotNull(made.deadline), on = on(action), cost = action.money("cost"),
                metricReading = action.doubleOrNull("metricReading"), items = items(action),
            ).also { made.entries += it.value }.receipt
            else -> runOnRecord(made, action, name, requireNotNull(entry) { "No action $name" })
        }
    }

    /** Runs [name], an action on a record an earlier step made ([entry]): its receipt when it gives one. */
    private fun runOnRecord(made: Made, action: JsonObject, name: String, entry: HistoryEntry): UndoReceipt? {
        when (name) {
            "setNote" -> return made.history.setNote(entry, action.textOrNull("text"))
            "rate" -> made.history.rate(entry, action.intOrNull("rating"))
            "delete" -> made.history.delete(entry)
            "addItems" -> made.history.addItems(items(action), entry)
            else -> error("No action $name")
        }
        return null
    }

    private fun visit(made: Made, action: JsonObject) = VisitRecord(
        kind = action.textOrNull("kind")?.let(HistoryKind::stored) ?: HistoryKind.MAINTENANCE,
        title = action.textOrNull("title"),
        occurredAt = on(action),
        checklist = action.objects("checklist").map {
            ChecklistItem(it.text("componentKey"), it.money("cost"), it.textOrNull("brand"))
        },
        extraItems = items(action),
        totalCost = action.money("total"),
        odometer = action.doubleOrNull("odometer"),
        provider = action.intOrNull("provider")?.let { made.firms[it] },
        note = action.textOrNull("note"),
        reference = action.textOrNull("reference"),
        rating = action.intOrNull("rating"),
    )

    private fun record(made: Made, action: JsonObject) = HistoryRecord(
        kind = requireNotNull(action.textOrNull("kind")?.let(HistoryKind::stored)),
        title = action.textOrNull("title").orEmpty(),
        occurredAt = on(action),
        metricReading = action.doubleOrNull("metricReading"),
        totalCost = action.money("total"),
        note = action.textOrNull("note"),
        reference = action.textOrNull("reference"),
        items = items(action),
        providers = listOfNotNull(action.intOrNull("provider")?.let { made.firms[it] }),
        rating = action.intOrNull("rating"),
    )

    /** Fills the visit form's draft with everything [action] gives and files what the form keeps. */
    private fun file(made: Made, action: JsonObject): Undoable<HistoryEntry> {
        val template = made.binder.snapshot().all(Tables.templates).first { it.key == made.asset.templateKey }
        val form = requireNotNull(VisitForm.of(template))
        val ticked = action.objects("ticked")
        val draft = VisitDraft(
            date = on(action) ?: made.binder.now,
            ticked = ticked.map { it.text("componentKey") },
            parts = ticked.associate {
                it.text("componentKey") to VisitDraft.Part(decimal(it, "cost"), it.textOrNull("brand").orEmpty())
            },
            extras = action.objects("extras").map {
                VisitDraft.Extra(it.textOrNull("name").orEmpty(), decimal(it, "cost"))
            },
            odometer = action.doubleOrNull("odometer"),
            total = decimal(action, "total"),
            note = action.textOrNull("note").orEmpty(),
            rating = action.intOrNull("rating"),
            reference = action.textOrNull("reference"),
        )
        val firm = action.intOrNull("provider")
        val who = when {
            firm != null -> VisitFiling.Who.Existing(made.firms[firm])
            action.textOrNull("named") != null -> VisitFiling.Who.Named(
                action.text("named"), form.shape.providerTrade ?: ProviderTrade.OTHER, action.textOrNull("taxID"),
            )
            else -> VisitFiling.Who.None
        }
        return made.history.file(draft.filing(made.asset, form, who), lower(action))
    }

    private fun decimal(json: JsonObject, key: String): BigDecimal? = json.money(key)?.amount

    private fun refusal(error: Throwable): String = when (error) {
        is LowerReadingAsked -> "lowerReading"
        is HistoryNoteEmpty -> "noteEmpty"
        is ExampleSectionQuestion -> "example"
        else -> throw error
    }

    // What a case compares

    private data class Item(
        val name: String, val componentKey: String?, val group: String?, val cost: BigDecimal?,
        val laborCost: BigDecimal?, val partsCost: BigDecimal?, val currency: String, val brand: String?,
    )

    private data class Record(
        val kind: String, val title: String, val occurredAt: Long, val metricReading: Double?, val cost: Money?,
        val note: String?, val reference: String?, val rating: Int?, val cycleDueDay: String?, val isExample: Boolean,
        val providers: List<String>, val items: List<Item>,
    )

    private data class Firm(val name: String, val taxID: String?, val trades: List<String>, val sections: Int)

    private data class Tracked(val key: String, val name: String?, val date: Long?, val metricAtTime: Double?)

    private data class State(
        val history: List<Record>,
        val readings: List<Triple<Long, Double, Boolean>>,
        val deadline: Triple<String, String, Double?>?,
        val firms: List<Firm>,
        val hero: Double?,
        val tracked: List<Tracked>,
    )

    private fun state(json: JsonObject): State {
        val history = json.objects("history").map {
            Record(
                it.text("kind"), it.text("title"), it.text("occurredAt").toLong(), it.doubleOrNull("metricReading"),
                money(it["cost"]), it.textOrNull("note"), it.textOrNull("reference"), it.intOrNull("rating"),
                it.textOrNull("cycleDueDay"), it.bool("isExample"), it.texts("providers"),
                it.objects("items").map { item ->
                    Item(
                        item.text("name"), item.textOrNull("componentKey"), item.textOrNull("group"),
                        amount(decimal(item, "cost")), amount(decimal(item, "laborCost")),
                        amount(decimal(item, "partsCost")), item.text("currency"),
                        item.textOrNull("brand"),
                    )
                },
            )
        }
        val readings = json.objects("readings").map {
            Triple(it.text("at").toLong(), it.text("value").toDouble(), it.bool("startsCounter"))
        }
        val deadline = json.obj("deadline")?.let {
            Triple(it.text("dueDay"), it.text("status"), it.doubleOrNull("dueMetric"))
        }
        val firms = json.objects("firms").map {
            Firm(it.text("name"), it.textOrNull("taxID"), it.texts("trades"), it.text("sections").toInt())
        }
        val section = requireNotNull(json.obj("section"))
        val tracked = section.objects("tracked").map {
            val date = it.textOrNull("date")?.toLong()
            Tracked(it.text("key"), it.textOrNull("name"), date, it.doubleOrNull("metricAtTime"))
        }
        return State(history, readings, deadline, firms, section.doubleOrNull("hero"), tracked)
    }

    private fun state(made: Made): State {
        val view = made.binder.snapshot()
        val history = view.all(Tables.history).sortedWith(compareBy({ it.occurredAt }, { it.title })).map { entry ->
            val items = HistoryRecords.items(view, entry)
                .sortedWith(compareBy({ it.name }, { it.componentKey.orEmpty() }))
            Record(
                entry.kindRaw, entry.title, entry.occurredAt.epochSecond, entry.metricReading, entry.totalCost,
                entry.note, entry.reference, entry.rating, entry.cycleDueDayISO, entry.isExample,
                HistoryRecords.providerNames(view, entry),
                items.map {
                    Item(
                        it.name, it.componentKey, it.group, amount(it.costAmount), amount(it.laborCostAmount),
                        amount(it.partsCostAmount), it.currency, it.partBrandOrCode,
                    )
                },
            )
        }
        val readings = view.all(Tables.readings).sortedWith(compareBy({ it.recordedAt }, { it.value }))
            .map { Triple(it.recordedAt.epochSecond, it.value, it.startsCounter) }
        val deadline = made.deadline?.let { start -> view.all(Tables.obligations).firstOrNull { it.id == start.id } }
            ?.let { Triple(it.dueDay(bucharest).isoString, it.statusRaw, it.dueMetric) }
        val firms = view.all(Tables.providers).sortedBy { it.name }.map {
            Firm(it.name, it.taxID, it.trades.sorted(), view.linked(Tables.providerAssets, it.pk).size)
        }
        val asset = requireNotNull(view.row(Tables.assets, made.asset.pk))
        val hero = HeroMetric.value(asset.keptValues.value, HeroMetric.categoryFields(view, asset))
        val items = HistoryRecords.snapshots(view, asset)
        val tracked = MaintenanceLog.trackedComponents(items).sorted().map { key ->
            val last = MaintenanceLog.lastOccurrence(key, items, made.binder.now, bucharest)
            Tracked(key, last?.name, last?.date?.epochSecond, last?.metricAtTime)
        }
        return State(history, readings, deadline, firms, hero, tracked)
    }

    @TestFactory
    fun actions(): List<DynamicTest> = HistoryVectorFiles.cases("actions").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val made = make(case)
            for (step in case.getValue("before").jsonArray) run(made, step.jsonObject)
            val before = state(made)
            var refused: String? = null
            var receipt: UndoReceipt? = null
            try {
                receipt = run(made, case.getValue("action").jsonObject)
            } catch (error: Exception) {
                refused = refusal(error)
            }
            assertEquals(case.textOrNull("refused"), refused, "What the step refused")
            assertEquals(state(requireNotNull(case.obj("after"))), state(made), "The binder after it")
            assertEquals(case.bool("receipt"), receipt != null, "A receipt where the iOS action gives one")
            assertEquals(case.bool("canUndo"), receipt?.canUndo ?: false, "Something to take back")
            if (receipt != null && receipt.canUndo) {
                receipt.undo()
                val undoes = case.textOrNull("undoRestores")?.toBooleanStrict()
                assertEquals(undoes, state(made) == before, "What undo gives back")
            }
        }
    }
}
