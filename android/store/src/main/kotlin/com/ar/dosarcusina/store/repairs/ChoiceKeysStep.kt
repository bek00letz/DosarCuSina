package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.ChoiceKeys
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptValues

/**
 * Choice values stored as display text (from builds before option keys) become option keys, and a
 * single value an earlier version kept where a list is kept now (a person's citizenship) becomes a
 * list of one, as the iOS app's `ChoiceKeysStep`, by the one rule an import follows ([ChoiceKeys]).
 * What the person sees doesn't change, so it runs without asking.
 *
 * A section's fields are its category's, from the category's record, else the app's own definition
 * for a built-in whose record isn't here.
 */
object ChoiceKeysStep : DataRepairStep {
    override val id = DataRepairStepId.CHOICE_KEYS
    override val group = DataRepairGroup.CHOICE_KEYS
    override val runsByItself = true

    override fun runByItself(step: Step, context: DataRepairContext): Int {
        val categories = RepairReading.categories(step)
        val changed = step.all(Tables.assets).mapNotNull { asset ->
            val fields = categories[asset.templateKey]?.let(RepairReading::fields)
                ?: context.builtIns.definition(asset.templateKey)?.sections?.flatMap { it.fields }
            fields?.let { normalized(asset, it) }
        }
        changed.forEach(step::update)
        return changed.size
    }

    /** [asset] with its choices kept as keys, or null when they already are. */
    private fun normalized(asset: Asset, fields: List<FieldDefinition>): Asset? {
        val kept = asset.keptValues
        val normalized = ChoiceKeys.normalizing(kept.value, fields)
        return if (normalized == kept.value) null else asset.withKeptValues(kept.replacingValue(normalized))
    }
}
