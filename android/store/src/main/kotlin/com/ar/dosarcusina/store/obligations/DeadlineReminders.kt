package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.BlueprintRules
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptReminders
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.schema.withKeptReminders

/**
 * The one rule for a deadline's reminders following what they come from, as the iOS app's
 * `DeadlineReminders` (ios/DosarCuSina/Services/Obligations/DeadlineReminders.swift): a deadline
 * made from a blueprint reminds as the blueprint says for its section's values
 * ([BlueprintRules.reminders]), and when a value that profile reads changes (a document's type, a
 * pet's species) it takes the new profile whole. One whose reminders the person set
 * ([Obligation.remindersCustomized]) keeps its own, with only the document's travel margin, which
 * is a fact about the document, not a preference.
 *
 * A section's edit reaches it ([follow], run by `AssetActions.update`); "Revino la cele obișnuite"
 * and the travel cut-off repair read [usual] and [expected] when the deadline actions bring them.
 * Nothing else writes a deadline's profile from its section.
 */
object DeadlineReminders {
    /** The reminders [obligation]'s blueprint gives for [values]; none when it isn't from [blueprint]. */
    fun usual(obligation: Obligation, blueprint: ObligationBlueprint?, values: FieldValues): ReminderProfile? {
        if (blueprint == null || obligation.blueprintKey != blueprint.key) return null
        return BlueprintRules.reminders(blueprint, values)
    }

    /**
     * The profile [obligation] follows for [values], or none when it isn't from [blueprint] or is done
     * or archived: its blueprint's whole, or the person's own with the document's travel margin.
     */
    fun expected(obligation: Obligation, blueprint: ObligationBlueprint?, values: FieldValues): ReminderProfile? {
        val status = ObligationStatus.stored(obligation.statusRaw)
        if (status != ObligationStatus.ACTIVE && status != ObligationStatus.PAUSED) return null
        val usual = usual(obligation, blueprint, values) ?: return null
        if (!obligation.remindersCustomized) return usual
        val own = obligation.reminders
        val margin = usual.travelMarginDays
        return ReminderProfile(own.leadDays, own.consequence, own.graceDays, own.followUpAfterLapse, margin)
    }

    /**
     * After the section in row [asset] had its values changed from [previous] to [values], in [step]:
     * each of its deadlines whose blueprint gives another profile for the new values takes it; one the
     * person set takes only the new travel margin. Values the profile doesn't read change nothing.
     * The deadlines that changed.
     */
    fun follow(
        step: Step,
        asset: Long,
        blueprints: List<ObligationBlueprint>,
        previous: FieldValues,
        values: FieldValues,
    ): List<Obligation> {
        val byKey = LinkedHashMap<String, ObligationBlueprint>()
        for (blueprint in blueprints) byKey.putIfAbsent(blueprint.key, blueprint)
        val changed = ArrayList<Obligation>()
        for (row in step.pointingAt(Tables.obligations, "asset", asset)) {
            val obligation = step.row(Tables.obligations, row) ?: continue
            val blueprint = obligation.blueprintKey?.let(byKey::get) ?: continue
            if (BlueprintRules.reminders(blueprint, previous) == BlueprintRules.reminders(blueprint, values)) continue
            val profile = expected(obligation, blueprint, values) ?: continue
            if (obligation.reminders == profile) continue
            val given = obligation.withKeptReminders(obligation.keptReminders.replacingValue(profile))
            step.update(given)
            changed += given
        }
        return changed
    }
}
