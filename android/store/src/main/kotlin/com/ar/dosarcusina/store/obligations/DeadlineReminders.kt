package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.remindersFor
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptBlueprints
import com.ar.dosarcusina.store.schema.keptReminders
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.schema.withKeptReminders

/**
 * The one rule for a deadline's reminders following what they come from, as the iOS app's
 * `DeadlineReminders` (ios/DosarCuSina/Services/Obligations/DeadlineReminders.swift).
 *
 * A deadline made from a blueprint reminds as the blueprint says for its section's values
 * ([remindersFor]): a passport three months before its travel cut-off, an identity card 90 and 30 days
 * before it expires. When a value that profile depends on changes (a document's type, a pet's species),
 * the deadline takes the new profile whole: its leads, consequence, grace, follow-up and travel margin.
 *
 * A deadline whose reminders the person set themselves ([Obligation.remindersCustomized]) keeps its leads,
 * consequence, grace and follow-up, but its travel margin still follows the document: the cut-off is a fact
 * about the document, not a preference.
 *
 * A section's edit reaches it through `AssetActions.update` ([follow]); the repair list's travel cut-off
 * step finds deadlines saved before it and gives them the same profile ([refresh]), with the owner's OK.
 * „Revino la cele obișnuite” gives a customised deadline its [usual] reminders back. Nothing else writes
 * a deadline's profile from its section.
 */
object DeadlineReminders {
    /** The reminders [obligation]'s [blueprint] gives for [values]; null when it isn't from that blueprint. */
    fun usual(obligation: Obligation, blueprint: ObligationBlueprint?, values: FieldValues): ReminderProfile? {
        if (blueprint == null || obligation.blueprintKey != blueprint.key) return null
        return blueprint.remindersFor(values)
    }

    /**
     * The reminders [obligation]'s blueprint gives for its section's current values, its category read
     * from [view]; null for a deadline not made from a blueprint, or whose category is gone.
     */
    fun usual(view: BinderView, obligation: Obligation): ReminderProfile? {
        val asset = obligation.asset?.let { view.row(Tables.assets, it) } ?: return null
        return usual(obligation, DeadlineCategory.blueprint(view, obligation), asset.keptValues.value)
    }

    /**
     * The usual reminders, when „Revino la cele obișnuite” has something to give back: the person set
     * this deadline's reminders and they differ from what its document gives.
     */
    fun restorable(view: BinderView, obligation: Obligation): ReminderProfile? {
        if (!obligation.remindersCustomized) return null
        return usual(view, obligation)?.takeIf { it != obligation.reminders }
    }

    /**
     * Whether [profile] is the person's own for [obligation]: anything but its usual reminders. Setting
     * exactly the usual ones back by hand lets it follow its document again. A deadline not made from a
     * blueprint has no usual ones, so whatever is set is the person's.
     */
    fun isCustomized(view: BinderView, profile: ReminderProfile, obligation: Obligation): Boolean =
        usual(view, obligation)?.let { it != profile } ?: true

    /**
     * The profile [obligation] follows for [values], or null when it isn't from [blueprint] or is done or
     * archived: its blueprint's profile whole, or for a deadline whose reminders the person set, their own
     * with the document's travel margin.
     */
    fun expected(obligation: Obligation, blueprint: ObligationBlueprint?, values: FieldValues): ReminderProfile? {
        if (obligation.status != ObligationStatus.ACTIVE && obligation.status != ObligationStatus.PAUSED) return null
        val usual = usual(obligation, blueprint, values) ?: return null
        if (!obligation.remindersCustomized) return usual
        return obligation.reminders.withTravelMarginDays(usual.travelMarginDays)
    }

    /**
     * After [asset]'s values changed from [previous] to its current ones, in [step]: each of its deadlines
     * whose blueprint gives another profile for the new values takes it; one whose reminders the person
     * set takes only the new travel margin. Values the profile doesn't read change nothing. Gives the
     * deadlines that changed, as written.
     */
    fun follow(
        step: Step,
        asset: Asset,
        blueprints: List<ObligationBlueprint>,
        previous: FieldValues,
    ): List<Obligation> {
        val section = step.row(Tables.assets, asset.pk) ?: return emptyList()
        val values = section.keptValues.value
        val byKey = LinkedHashMap<String, ObligationBlueprint>()
        for (blueprint in blueprints) byKey.putIfAbsent(blueprint.key, blueprint)
        val deadlines = step.pointingAt(Tables.obligations, "asset", section.pk)
            .mapNotNull { step.row(Tables.obligations, it) }
        return deadlines.mapNotNull { obligation ->
            val blueprint = obligation.blueprintKey?.let(byKey::get)
                ?.takeIf { it.remindersFor(previous) != it.remindersFor(values) }
            blueprint?.let { expected(obligation, it, values) }?.let { give(step, it, obligation) }
        }
    }

    /**
     * Gives [obligation] the profile it follows for its section's values ([expected]), in [step]; false
     * when it already has it or follows nothing. The repair list runs it as the app's own step, so the
     * deadline keeps its change time.
     */
    fun refresh(step: Step, obligation: Obligation, blueprints: List<ObligationBlueprint>): Boolean {
        val current = step.row(Tables.obligations, obligation.pk) ?: return false
        val asset = current.asset?.let { step.row(Tables.assets, it) } ?: return false
        val blueprint = blueprints.firstOrNull { it.key == current.blueprintKey }
        val profile = expected(current, blueprint, asset.keptValues.value) ?: return false
        return give(step, profile, current) != null
    }

    /** [obligation] with [profile], written in [step]; null when it already has it. */
    private fun give(step: Step, profile: ReminderProfile, obligation: Obligation): Obligation? {
        if (obligation.reminders == profile) return null
        val written = obligation.withKeptReminders(obligation.keptReminders.replacingValue(profile))
        step.update(written)
        return written
    }

    /** The category's blueprints as stored, for a step that has the category's record. */
    fun blueprintsOf(view: BinderView, asset: Asset): List<ObligationBlueprint> =
        view.all(Tables.templates).firstOrNull { it.key == asset.templateKey }?.keptBlueprints?.items.orEmpty()
}
