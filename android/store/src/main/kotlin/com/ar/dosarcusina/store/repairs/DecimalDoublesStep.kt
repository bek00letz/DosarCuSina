package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.NumberKind
import com.ar.dosarcusina.core.values.RomanianNumber
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptValues

/**
 * Numbers an earlier iOS version kept a step off, put back on the short number they stand for, as the iOS app's
 * `DecimalDoublesStep`. Its `NSDecimalNumber.doubleValue` could miss the nearest Double by a step or two: a water
 * index printed 0,011 was kept as 0.011000000000000001, and reaches this app in a backup. By the one rule
 * ([RomanianNumber.correction]), with the decimals of the kind each was read as:
 *
 * - a reading's value and its second value, by its unit ([NumberKind.forField]);
 * - a record's counter ([com.ar.dosarcusina.store.schema.HistoryEntry.metricReading]), by the unit its section's
 *   counter is in ([HeroMetric.unit]);
 * - a section's numbers, by their field ([numberKind]); a value whose field the category doesn't list stays.
 *
 * A deadline's counted due is a sum, not a number read, and a category's counted interval is whole: both stay.
 * What anyone sees stays the same, so it runs without asking, as the app's own step: no change time.
 */
object DecimalDoublesStep : DataRepairStep {
    override val id = DataRepairStepId.DECIMAL_DOUBLES
    override val group = DataRepairGroup.DECIMAL_DOUBLES
    override val runsByItself = true

    /** The kind a field's number is read as (the iOS app's `FieldFormatter.numberKind(of:unit:)`). */
    fun numberKind(field: FieldDefinition): NumberKind =
        if (field.type == YEAR) NumberKind.COUNT else NumberKind.forField(MeasurementUnit.of(field.unit))

    override fun runByItself(step: Step, context: DataRepairContext): Int {
        val readings = step.all(Tables.readings).mapNotNull(::corrected)
        val categories = RepairReading.categories(step)
        val fieldsByAsset = HashMap<Long, List<FieldDefinition>?>()
        fun fields(asset: Asset): List<FieldDefinition>? = fieldsByAsset.getOrPut(asset.pk) {
            categories[asset.templateKey]?.let(RepairReading::fields)
                ?: context.builtIns.definition(asset.templateKey)?.sections?.flatMap { it.fields }
        }
        val entries = step.all(Tables.history).mapNotNull { entry ->
            val reading = entry.metricReading ?: return@mapNotNull null
            val fieldsOf = entry.asset?.let { step.row(Tables.assets, it) }?.let(::fields).orEmpty()
            val kind = NumberKind.forField(HeroMetric.unit(fieldsOf))
            RomanianNumber.correction(reading, kind)?.let { entry.copy(metricReading = it) }
        }
        val assets = step.all(Tables.assets).mapNotNull { asset -> fields(asset)?.let { corrected(asset, it) } }
        val changed: List<Any> = readings + entries + assets
        changed.forEach(step::update)
        return changed.size
    }

    /** [log] with its numbers put back, or null when they stand. */
    private fun corrected(log: MeasurementLog): MeasurementLog? {
        val kind = NumberKind.forField(MeasurementUnit.of(log.unit))
        val value = RomanianNumber.correction(log.value, kind)
        val second = log.secondaryValue?.let { RomanianNumber.correction(it, kind) }
        if (value == null && second == null) return null
        return log.copy(value = value ?: log.value, secondaryValue = second ?: log.secondaryValue)
    }

    /** [asset] with its numbers put back by their fields, or null when they stand. */
    private fun corrected(asset: Asset, fields: List<FieldDefinition>): Asset? {
        val kept = asset.keptValues
        val corrections = kept.value.storage.mapNotNull { (key, stored) ->
            corrected(key, stored, fields)?.let { key to it }
        }
        if (corrections.isEmpty()) return null
        val values = corrections.fold(kept.value) { values, (key, value) -> values.with(key, FieldValue.Number(value)) }
        return asset.withKeptValues(kept.replacingValue(values))
    }

    /** The number [stored] under [key] is put back on, by its field among [fields]; null when it stands. */
    private fun corrected(key: String, stored: FieldValue, fields: List<FieldDefinition>): Double? {
        val number = (stored as? FieldValue.Number)?.value
        val field = fields.firstOrNull { it.key == key }
        return if (number == null || field == null) null else RomanianNumber.correction(number, numberKind(field))
    }

    private const val YEAR = "year"
}
