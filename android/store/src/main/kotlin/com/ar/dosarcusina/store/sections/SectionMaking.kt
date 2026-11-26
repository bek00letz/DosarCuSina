package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.PlannedObligation
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.withKeptValues
import com.ar.dosarcusina.store.templates.HouseholdDeadlines
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** What a new section is made of, its values as saving keeps them: choices as keys, rules applied, secrets sealed. */
internal class Making(
    val name: String,
    val template: CategoryTemplate,
    val values: FieldValues,
    val notes: String?,
    val obligations: List<PlannedObligation>,
    val isExample: Boolean,
    val id: UUID = UUID.randomUUID(),
)

/**
 * The one way a section is made, as the body of the iOS app's `AssetActions.create`: for
 * [AssetActions.create], a move to a new person and the repair list's „Recuperate”
 * (`LostRecordsStep`). It records in the step it is given and saves nothing.
 */
internal object SectionMaking {
    /**
     * Makes [section] in [step] under the section in row [parent] at [now], with its selected
     * deadlines, its hero value as its first reading, and the household's deadlines after it
     * ([HouseholdDeadlines.reconcile]). Gives the section as the step has it.
     */
    @Suppress("LongParameterList") // A section, where it goes, and the step's clock, days and catalog.
    fun make(step: Step, section: Making, parent: Long?, now: Instant, zone: ZoneId, catalog: Catalog): Asset {
        val today = CalendarDay.of(now, zone)
        val asset = step.insert(
            Asset(
                id = section.id, name = section.name, templateKey = section.template.key, notes = section.notes,
                isExample = section.isExample, createdAt = now, updatedAt = now, parent = parent,
            ).withKeptValues(KeptObject.made(section.values, FieldValues.codec)),
        )
        for (planned in section.obligations) {
            if (!planned.isSelected) continue
            SectionDeadlines.make(step, planned.blueprint, asset, planned.firstDue, today, now, catalog)
        }
        // A new section has no readings before its first, so this never asks.
        val fields = section.template.keptSections.items.flatMap { it.fields }
        HeroMetric.value(section.values, fields)?.let { value ->
            val unit = HeroMetric.unit(fields)
            val planned = HouseholdReadings.plan(step, asset.pk, value, now, ReadingSource.PERSON, unit)
            HouseholdReadings.recordReading(step, planned, answer = null)
        }
        HouseholdDeadlines(catalog.household, zone).reconcile(step, today, now)
        return requireNotNull(step.row(Tables.assets, asset.pk))
    }
}
