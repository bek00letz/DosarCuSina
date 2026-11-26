package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.catalog.obligationKind
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.obligations.status
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptBlueprints
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.withKeptRecurrence

/**
 * Deadlines brought from a first-version backup have no blueprint and a plain interval: an ITP
 * doesn't follow the legal rule (counted by the car's age), and nothing keyed by the blueprint (what
 * to bring, the policy facts) finds them. One whose title and kind match one of its category's
 * blueprints gets that blueprint and its rule, asking first, as the iOS app's
 * `FirstVersionDeadlinesStep`. The day the person has stays.
 */
object FirstVersionDeadlinesStep : DataRepairStep {
    override val id = DataRepairStepId.FIRST_VERSION_DEADLINES
    override val group = DataRepairGroup.OLD_BACKUP_DEADLINES

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val view = scan.view
        val categories = RepairReading.categories(view)
        return view.all(Tables.obligations).mapNotNull { obligation ->
            val blueprint = blueprint(obligation, view, categories) ?: return@mapNotNull null
            val section = obligation.asset?.let { view.row(Tables.assets, it) } ?: return@mapNotNull null
            DataRepairFinding(
                id = DataRepairFinding.id(id, RepairReading.key(obligation.id), blueprint.key),
                step = id,
                subject = DataRepairSubject.Blueprint(obligation.id, blueprint.key, obligation.title, section.name),
            )
        }
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val categories = RepairReading.categories(step)
        for (subject in findings.mapNotNull { it.subject as? DataRepairSubject.Blueprint }) {
            // Read as it is now: a deadline given its blueprint by an earlier finding counts as used.
            val obligation = step.all(Tables.obligations).firstOrNull { it.id == subject.obligationId }
            val blueprint = obligation?.let { blueprint(it, step, categories) }
                ?.takeIf { it.key == subject.blueprintKey }
            if (obligation != null && blueprint != null) step.update(given(obligation, blueprint))
        }
    }

    /** [obligation] with [blueprint] and its rule; the day the person has stays. */
    private fun given(obligation: Obligation, blueprint: ObligationBlueprint): Obligation {
        val rule = blueprint.recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None
        return obligation.withKeptRecurrence(obligation.keptRecurrence.replacingValue(rule))
            .copy(blueprintKey = blueprint.key)
    }

    /**
     * The blueprint a blueprint-less deadline still running is: of its category, the same kind and the
     * same title, and not already used by another deadline of the same section.
     */
    fun blueprint(
        obligation: Obligation,
        view: BinderView,
        categories: Map<String, CategoryTemplate>,
    ): ObligationBlueprint? {
        if (obligation.blueprintKey != null || obligation.isExample) return null
        if (obligation.status != ObligationStatus.ACTIVE && obligation.status != ObligationStatus.PAUSED) return null
        val section = obligation.asset?.let { view.row(Tables.assets, it) } ?: return null
        val template = categories[section.templateKey] ?: return null
        val title = normalized(obligation.title)
        val kind = ObligationKind.stored(obligation.kindRaw)
        val used = view.pointingAt(Tables.obligations, "asset", section.pk)
            .mapNotNullTo(mutableSetOf()) { view.row(Tables.obligations, it)?.blueprintKey }
        return template.keptBlueprints.items.firstOrNull {
            it.obligationKind == kind && normalized(it.title) == title && it.key !in used
        }
    }

    /** A title as compared: its folded words, one space apart (`SearchText.normalize`). */
    private fun normalized(title: String): String = RomanianText.words(title).joinToString(" ")
}
