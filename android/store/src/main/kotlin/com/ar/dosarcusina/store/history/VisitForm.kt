package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.capture.LabourLine
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.repairs.RepairReading
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.keptComponents
import com.ar.dosarcusina.store.templates.behavior

/**
 * The visit form as one category shows it, as the iOS app's `VisitForm`
 * (ios/DosarCuSina/Services/History/VisitForm.swift): its kind's shape ([VisitShape]) laid over what the
 * category has, its parts and jobs (a checklist only when it lists some), its counter (only one that goes
 * up), the warranty a product keeps. Data only: what it says is the screens' (Phase 4).
 */
data class VisitForm(
    val kind: VisitKind,
    val shape: VisitShape,
    /** The category's parts and jobs, ticked on the checklist; empty when there is no checklist. */
    val components: List<ComponentDefinition>,
    /** The counter it asks (km, engine hours): the category's hero field, when it only goes up. */
    val counterField: FieldDefinition?,
    /** The product's warranty end, when the kind checks it and the category keeps one. */
    val warrantyField: FieldDefinition?,
) {
    /** Whether what was done is ticked on the category's parts and jobs. Never an empty list. */
    val hasChecklist: Boolean get() = components.isNotEmpty()

    /** Whether what was done is written in rows: beside the checklist ("Altceva"), or alone. */
    val hasRows: Boolean get() = shape.asksWork

    /** The fields this category's form shows. */
    val fields: Set<VisitShape.Field>
        get() = if (counterField == null) shape.fields - VisitShape.Field.COUNTER else shape.fields

    /**
     * Whether what it lists are a vehicle's parts: a service's rows, ticked on the category's checklist of
     * parts. A category of one's own whose service lists none writes plain rows. The one rule for „Piesele…”
     * on the form and on the record's page ([HistoryEntryShape]).
     */
    val rowsAreParts: Boolean get() = shape.sum == VisitShape.Sum.PARTS && hasChecklist

    /** Whether the rows add up under the money field: a form with rows or a checklist. */
    val sumsRows: Boolean get() = hasChecklist || hasRows

    /** What a paper can fill in on this form: its day and total, and who issued it where it asks who did it. */
    val paperFacts: List<PaperFact>
        get() = if (VisitShape.Field.PROVIDER in fields) PaperFact.entries else listOf(PaperFact.DAY, PaperFact.TOTAL)

    /** What a paper read without rows gives the form. */
    enum class PaperFact { DAY, TOTAL, ISSUER }

    /** The record's title in Istoric: what was done when it is one or two things, else the kind's. */
    fun entryTitle(items: List<String>): EntryTitle {
        val names = LabourLine.work(items.filter { it.isNotEmpty() })
        return when {
            names.isEmpty() -> EntryTitle.OfKind(kind)
            names.size <= NAMED_JOBS -> EntryTitle.Names(names)
            shape.sum == VisitShape.Sum.PARTS -> EntryTitle.ManyJobs(names.size)
            else -> EntryTitle.OfKind(kind)
        }
    }

    companion object {
        /** The most jobs a title names; more are counted. */
        const val NAMED_JOBS = 2

        /** The form for [template]'s sections; none when its visits are none. */
        fun of(template: CategoryTemplate): VisitForm? = of(template.behavior.visit, template)

        /** The form [kind] gives [template]'s sections; none when the kind has no visits. */
        fun of(kind: VisitKind, template: CategoryTemplate): VisitForm? {
            val shape = VisitShape.of(kind) ?: return null
            val fields = RepairReading.fields(template)
            val counter = HeroMetric.field(fields).takeIf { field ->
                shape.asksCounter && field != null &&
                    MeasurementKind.forUnit(field.unit?.let(MeasurementUnit::of)).isCumulative
            }
            return VisitForm(
                kind = kind,
                shape = shape,
                components = if (shape.asksWork) template.keptComponents.items else emptyList(),
                counterField = counter,
                warrantyField = if (shape.checksWarranty) fields.firstOrNull { it.role == WARRANTY_UNTIL } else null,
            )
        }

        /** Whether [template]'s visits list parts: its visit form's rule ([rowsAreParts]), for a record's page. */
        fun listsParts(template: CategoryTemplate?): Boolean = template?.let(::of)?.rowsAreParts ?: false

        private const val WARRANTY_UNTIL = "warrantyUntil"
    }
}

/**
 * A record's title in Istoric, as a kind: the words are the app's ([HistoryWording]), the names the person's.
 * iOS writes the same titles (`VisitForm.entryTitle`, `HistoryActions.visitTitle`).
 */
sealed interface EntryTitle {
    /** One or two things done, by name, joined: „Ulei și filtru, Plăcuțe frână față”. */
    data class Names(val names: List<String>) : EntryTitle

    /** The kind's own title when nothing done is named: „Vizită la service”, „Reparație”. */
    data class OfKind(val kind: VisitKind) : EntryTitle

    /** A visit of no kind with nothing listed: „Vizită”. */
    data object Visit : EntryTitle

    /** A service of [count] jobs: „Revizie: 3 lucrări”. */
    data class ManyJobs(val count: Int) : EntryTitle

    companion object {
        /** A visit's title from what it lists, when nothing names its kind (`HistoryActions.visitTitle`). */
        fun of(items: List<String>): EntryTitle {
            val names = LabourLine.work(items.filter { it.isNotEmpty() })
            return when {
                names.isEmpty() -> Visit
                names.size <= VisitForm.NAMED_JOBS -> Names(names)
                else -> ManyJobs(names.size)
            }
        }
    }
}

/**
 * The words a record of history is written with, the app's (Phase 4, from its strings, as the iOS app's
 * String Catalog has them): what the store writes as a record's title when nothing done names it.
 */
interface HistoryWording {
    /** The kind's title („Vizită la service”); for none, a visit's („Vizită”). */
    fun entryTitle(kind: VisitKind?): String

    /** A service of [count] jobs: „Revizie: 3 lucrări”, in the count's plural form. */
    fun manyJobs(count: Int): String

    /** [title] in words: names joined by a comma, a kind's or a count's in the app's. */
    fun title(title: EntryTitle): String = when (title) {
        is EntryTitle.Names -> title.names.joinToString(", ")
        is EntryTitle.OfKind -> entryTitle(title.kind)
        EntryTitle.Visit -> entryTitle(null)
        is EntryTitle.ManyJobs -> manyJobs(title.count)
    }
}
