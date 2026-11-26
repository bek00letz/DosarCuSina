package com.ar.dosarcusina.store.examples

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.ExampleHousehold
import com.ar.dosarcusina.catalog.ExampleStep
import com.ar.dosarcusina.catalog.PlannedObligation
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.history.HistoryRecord
import com.ar.dosarcusina.store.history.LineItemDraft
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.providers.ProviderActions
import com.ar.dosarcusina.store.providers.ProviderTrade
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.sections.AssetActions
import com.ar.dosarcusina.store.templates.byKey
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/** The actions the example loader makes the household through, each one the person's own. */
internal class ExampleActions(
    val assets: AssetActions,
    val obligations: ObligationActions,
    val history: HistoryActions,
    val providers: ProviderActions,
)

/**
 * Makes the example household's steps in order, inside the one step [step] of the loader's unit,
 * each through its action (which joins that unit), every record marked as an example, as the iOS
 * app's `ExampleDataService.addExampleHousehold`. A step naming a section that wasn't made (its
 * category isn't in the binder) is left out with it.
 */
internal class ExampleLoader(
    private val actions: ExampleActions,
    private val step: Step,
    private val now: Instant,
    private val zone: ZoneId,
) {
    private val templates: Map<String, CategoryTemplate> = step.all(Tables.templates).byKey()
    private val sections = HashMap<String, Asset>()
    private val firms = HashMap<String, Provider>()
    private val today = CalendarDay.of(now, zone)

    fun load(household: ExampleHousehold) {
        for (made in household.steps) {
            when (made) {
                is ExampleStep.Section -> make(made)
                is ExampleStep.Firm -> make(made)
                is ExampleStep.Record -> make(made)
                is ExampleStep.PastCompletion -> make(made)
                is ExampleStep.Reading -> make(made)
            }
        }
    }

    /** The moment [days] days from now, at the same time of day where the app counts days. */
    private fun moment(days: Int): Instant = ZonedDateTime.ofInstant(now, zone).plusDays(days.toLong()).toInstant()

    private fun make(section: ExampleStep.Section) {
        val template = templates[section.category] ?: return
        val parent = section.parent?.let { sections[it] ?: return }
        val values = FieldValues(section.values.mapValues { (_, value) -> value.on(today) })
        val planned = actions.assets.plannedObligations(template, values).map { plan ->
            val firstDue = section.firstDue[plan.blueprint.key]?.let(today::addingDays) ?: plan.firstDue
            // The add flow's rule, with the example's own dates given.
            plan.copy(firstDue = firstDue, isSelected = PlannedObligation.startsSelected(plan.blueprint, firstDue))
        }
        sections[section.ref] = actions.assets.create(
            section.name, template, values, obligations = planned, parent = parent, isExample = true,
        )
    }

    private fun make(firm: ExampleStep.Firm) {
        val linked = firm.linkedTo.map { sections[it] ?: return }
        val trades = firm.trades.map { requireNotNull(ProviderTrade.of(it)) { "No trade $it" } }
        var provider = actions.providers.create(firm.name, trades, phone = firm.phone, linkedTo = linked)
        firm.rating?.let { actions.providers.setRating(provider, it) }
        firm.wouldCallAgain?.let { actions.providers.setWouldCallAgain(provider, it) }
        provider = requireNotNull(step.row(Tables.providers, provider.pk))
        firms[firm.ref] = provider
    }

    private fun make(record: ExampleStep.Record) {
        val section = sections[record.section] ?: return
        val kind = requireNotNull(HistoryKind.stored(record.kind)) { "No kind of record ${record.kind}" }
        val made = HistoryRecord(
            kind = kind, title = record.title, occurredAt = moment(record.daysFromNow),
            metricReading = record.metricReading, totalCost = record.totalCost,
            items = record.items.map { item ->
                LineItemDraft(name = item.name, partBrandOrCode = item.partBrandOrCode, cost = item.cost)
            },
            providers = record.firms.mapNotNull { firms[it] }, rating = record.rating, asExample = true,
        )
        actions.history.record(section, made)
    }

    /** A completion from before the binder knew the deadline, logged without moving the deadline. */
    private fun make(completion: ExampleStep.PastCompletion) {
        val section = sections[completion.section] ?: return
        val deadline = step.all(Tables.obligations)
            .firstOrNull { it.asset == section.pk && it.blueprintKey == completion.deadline } ?: return
        actions.obligations.recordPastCompletion(deadline, moment(completion.daysFromNow), completion.cost)
    }

    private fun make(reading: ExampleStep.Reading) {
        val section = sections[reading.section] ?: return
        actions.assets.recordMeasurement(
            section, MeasurementKind.stored(reading.kind), reading.value, name = reading.name.orEmpty(),
            at = moment(reading.daysFromNow), asExample = true,
        )
    }
}
