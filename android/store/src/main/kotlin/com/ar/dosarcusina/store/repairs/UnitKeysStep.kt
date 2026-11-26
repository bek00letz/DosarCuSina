package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.CategoryTemplate
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Before units had keys, a reading, a deadline counted in a unit and a category of the person's own
 * stored the unit's label ("m³", "mc", "kWh", "cafele"). They are rewritten to the unit's key
 * ([MeasurementUnit]), as the iOS app's `UnitKeysStep`. The unit and the number stay the same, so it
 * runs without asking. Built-in categories get keys when the catalog upgrades them.
 *
 * Only the unit is touched: a stored recurrence or category is rewritten in place ([StoredUnitKeys]),
 * never read into this build's types and written back, so nothing a newer build wrote is lost.
 */
object UnitKeysStep : DataRepairStep {
    override val id = DataRepairStepId.UNIT_KEYS
    override val group = DataRepairGroup.UNITS
    override val runsByItself = true

    override fun runByItself(step: Step, context: DataRepairContext): Int {
        val readings = step.all(Tables.readings).mapNotNull { log ->
            MeasurementUnit.storedKey(log.unit).takeIf { it != log.unit }?.let { log.copy(unit = it) }
        }
        val deadlines = step.all(Tables.obligations).mapNotNull { obligation ->
            StoredUnitKeys.recurrence(obligation.recurrenceData)?.let { obligation.copy(recurrenceData = it) }
        }
        val categories = step.all(Tables.templates).filterNot { it.isBuiltIn }.mapNotNull(::withKeys)
        val changed: List<Any> = readings + deadlines + categories
        changed.forEach(step::update)
        return changed.size
    }

    /** A category of one's own with its fields' and deadlines' units as keys, or null when they are. */
    private fun withKeys(template: CategoryTemplate): CategoryTemplate? {
        val sections = StoredUnitKeys.sections(template.sectionsData)
        val blueprints = StoredUnitKeys.blueprints(template.blueprintsData)
        if (sections == null && blueprints == null) return null
        return template.copy(
            sectionsData = sections ?: template.sectionsData,
            blueprintsData = blueprints ?: template.blueprintsData,
        )
    }
}

/**
 * Rewrites the units inside stored JSON to their keys, leaving everything else as it was, as the iOS
 * app's `StoredUnitKeys`. Each gives null when nothing changes (or the text can't be read), so a second
 * run changes nothing.
 */
object StoredUnitKeys {
    private const val UNIT = "unit"
    private const val METRIC = "metric"

    /** A recurrence (`{"type": "metric", "unit": "m³", …}`). */
    fun recurrence(text: String?): String? {
        val rule = read(text) as? JsonObject ?: return null
        return rewriteRecurrence(rule)?.let(MachineText::json)
    }

    /** A category's sections: each field's `unit`. */
    fun sections(text: String?): String? {
        val sections = read(text) as? JsonArray ?: return null
        var changed = false
        val rewritten = sections.map { section ->
            val fields = (section as? JsonObject)?.get("fields") as? JsonArray ?: return@map section
            val each = fields.map { field ->
                (field as? JsonObject)?.let(::rewriteUnit)?.also { changed = true } ?: field
            }
            JsonObject(section + ("fields" to JsonArray(each)))
        }
        return if (changed) MachineText.json(JsonArray(rewritten)) else null
    }

    /** A category's deadlines: each metric recurrence's `unit`. */
    fun blueprints(text: String?): String? {
        val blueprints = read(text) as? JsonArray ?: return null
        var changed = false
        val rewritten = blueprints.map { blueprint ->
            val recurrence = (blueprint as? JsonObject)?.get("recurrence") as? JsonObject ?: return@map blueprint
            val rule = rewriteRecurrence(recurrence) ?: return@map blueprint
            changed = true
            JsonObject(blueprint + ("recurrence" to rule))
        }
        return if (changed) MachineText.json(JsonArray(rewritten)) else null
    }

    private fun rewriteRecurrence(rule: JsonObject): JsonObject? {
        val type = rule["type"] as? JsonPrimitive
        if (type == null || !type.isString || type.content != METRIC) return null
        return rewriteUnit(rule)
    }

    private fun rewriteUnit(holder: JsonObject): JsonObject? {
        val text = (holder[UNIT] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        val key = MeasurementUnit.storedKey(text)
        if (key.isEmpty() || key == text) return null
        return JsonObject(holder + (UNIT to JsonPrimitive(key)))
    }

    private fun read(text: String?): JsonElement? = text?.let(MachineText::parseOrNull)
}
