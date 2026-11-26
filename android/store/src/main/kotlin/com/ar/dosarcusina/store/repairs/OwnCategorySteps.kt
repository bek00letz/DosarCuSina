package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.catalog.CategorySwitches
import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.templates.behavior
import com.ar.dosarcusina.store.templates.switches
import com.ar.dosarcusina.store.templates.takingBoxAsGrouping
import com.ar.dosarcusina.store.templates.withBehavior

/**
 * A category of one's own an earlier version made with one box of its own for the whole category
 * ("O cutie pentru toate" before it was the grouping): its box becomes one per section, grouped,
 * which looks the same, by the one rule (`TemplateStore.takeBoxAsGrouping`), as the iOS app's
 * `OwnCategoryBoxesStep`. A grouping already chosen stays; one that behaves like Garanții, and a
 * built-in, keep their box. Nothing anyone sees changes, so it runs without asking.
 */
object OwnCategoryBoxesStep : DataRepairStep {
    override val id = DataRepairStepId.OWN_CATEGORY_BOXES
    override val group = DataRepairGroup.OWN_CATEGORY_BOXES
    override val runsByItself = true

    override fun runByItself(step: Step, context: DataRepairContext): Int {
        val changed = step.all(Tables.templates).mapNotNull { it.takingBoxAsGrouping() }
        changed.forEach(step::update)
        return changed.size
    }
}

/**
 * A category of one's own an earlier version made with a service and no visits gets the visits its
 * switch gives ([CategorySwitches.visit]: a job by time, a service by a counter), as the iOS app's
 * `OwnCategoryVisitsStep`. A kind already stated stays. Runs without asking.
 */
object OwnCategoryVisitsStep : DataRepairStep {
    override val id = DataRepairStepId.OWN_CATEGORY_VISITS
    override val group = DataRepairGroup.OWN_CATEGORY_VISITS
    override val runsByItself = true

    override fun runByItself(step: Step, context: DataRepairContext): Int {
        val changed = step.all(Tables.templates).filter { !it.isBuiltIn && it.behavior.visit == VisitKind.NONE }
            .mapNotNull { template ->
                val kind = CategorySwitches.visit(template.switches.service)
                if (kind == VisitKind.NONE) null else template.withBehavior(template.behavior.copy(visit = kind))
            }
        changed.forEach(step::update)
        return changed.size
    }
}

/**
 * A service deadline of a category of one's own whose note is only its rule, copied there by an
 * earlier version ("La 10.000 de km sau o dată pe an, ce vine întâi."): offered for removal, since
 * the deadline's page says how it repeats anyway, always up to date, as the iOS app's
 * `ServiceNotesStep`. A note the person wrote, or changed, stays.
 */
object ServiceNotesStep : DataRepairStep {
    override val id = DataRepairStepId.SERVICE_NOTES
    override val group = DataRepairGroup.SERVICES

    /**
     * Every way an earlier version wrote the rule, compared as values are ([RomanianText.compact], so
     * a number grouped any way is the same digits): every so many kilometres, engine hours or months,
     * in each of the plural forms the catalog gave it. Data to recognise, never words shown.
     */
    private val earlierNotes = Regex(
        "^(?:LA(?:[0-9]+(?:DE)?KM|UNKILOMETRU|[0-9]+(?:DE)?OREDEMOTOR|OORADEMOTOR)SAUODATAPEANCEVINEINTAI" +
            "|ODATA(?:LA[0-9]+(?:DE)?LUNI|PELUNA))$",
    )

    /** Whether [note] is the rule an earlier version copied into a service deadline. */
    fun isEarlierRule(note: String): Boolean = earlierNotes.matches(RomanianText.compact(note))

    private fun candidates(obligations: List<Obligation>): List<Obligation> =
        obligations.sortedBy { it.createdAt }.filter { obligation ->
            val key = obligation.blueprintKey
            val notes = obligation.notes
            !obligation.isExample && key != null && CategorySwitches.isServiceBlueprint(key) && notes != null &&
                isEarlierRule(notes)
        }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val sections = scan.view.all(Tables.assets).associateBy { it.pk }
        return candidates(scan.view.all(Tables.obligations)).map { obligation ->
            val notes = obligation.notes.orEmpty()
            DataRepairFinding(
                id = DataRepairFinding.id(id, RepairReading.key(obligation.id), RomanianText.compact(notes)),
                step = id,
                subject = DataRepairSubject.ServiceNote(
                    obligationId = obligation.id,
                    deadline = obligation.title,
                    section = obligation.asset?.let(sections::get)?.name,
                    note = notes,
                ),
            )
        }
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNull { (it.subject as? DataRepairSubject.ServiceNote)?.obligationId }.toSet()
        // Checked again: a note changed since the list was made stays.
        for (obligation in candidates(step.all(Tables.obligations))) {
            if (obligation.id in approved) step.update(obligation.copy(notes = null))
        }
    }
}
