package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.readings.CounterOutliers
import com.ar.dosarcusina.core.text.PaymentCardNumbers
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.SwiftNumber
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.readings.kind
import com.ar.dosarcusina.store.readings.measurementUnit
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog

// The repairs of counter readings, as the iOS app's ios/DosarCuSina/Services/Repairs/DataRepairSteps.swift
// ("Counter readings"): each reads the readings counter by counter (HouseholdReadings.counters), so the
// first reading of a new meter or dashboard is never taken for a mistake.

/** A section's name as the list shows it: never with a card number it may hold. */
private fun shown(name: String): String = PaymentCardNumbers.redact(name)

/**
 * Counter readings 10 or more times off both their neighbours, or equal to a neighbour divided by a power
 * of ten (457 next to 45724: the number lost its thousands), as the iOS app's `CounterOutliersStep`. The
 * rule is the engine's ([CounterOutliers.verdicts]).
 */
object CounterOutliersStep : DataRepairStep {
    override val id = DataRepairStepId.COUNTER_OUTLIERS
    override val group = DataRepairGroup.COUNTERS

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val view = scan.view
        val found = ArrayList<DataRepairFinding>()
        for (asset in view.all(Tables.assets)) {
            if (asset.isExample) continue
            val readings = HouseholdReadings.readings(view, asset.pk)
            val units = readings.filter { it.kind.isCumulative }.map { it.measurementUnit }.distinct()
            for (unit in units) {
                for (counter in HouseholdReadings.counters(view, asset.pk, unit)) {
                    for ((index, verdict) in CounterOutliers.verdicts(counter.map { it.value }).toSortedMap()) {
                        val log = counter[index]
                        scan.flaggedReadings += log.id.toString()
                        scan.flaggedAssets += asset.id.toString()
                        found += DataRepairFinding(
                            id = DataRepairFinding.id(
                                id, RepairReading.key(log.id), SwiftNumber.description(log.value),
                            ),
                            step = id,
                            subject = DataRepairSubject.Reading(
                                logId = log.id,
                                value = log.value,
                                to = (verdict as? CounterOutliers.Verdict.Correct)?.to,
                                unit = unit,
                                section = shown(asset.name),
                                day = CalendarDay.of(log.recordedAt, scan.context.zone),
                            ),
                        )
                    }
                }
            }
        }
        return found
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val touched = findings.mapNotNull { it.subject as? DataRepairSubject.Reading }
            .mapNotNullTo(LinkedHashSet()) { repair(step, it) }
        for (asset in touched) HeroMetric.sync(step, asset)
    }

    /** Corrects or takes away the reading [subject] names; the row of its section, or null when it changed since. */
    private fun repair(step: Step, subject: DataRepairSubject.Reading): Long? {
        // Checked again: a reading changed since it was found stays as it is now.
        val log = step.find(Tables.readings, subject.logId.toString())?.takeIf { it.value == subject.value }
        val asset = log?.asset ?: return null
        val target = subject.to
        if (target == null) {
            HouseholdReadings.removeReading(step, log, asset)
            return asset
        }
        // The visit that logged the wrong number gets the right one too.
        entriesOf(step, asset)
            .filter { it.occurredAt == log.recordedAt && it.metricReading == subject.value }
            .forEach { step.update(it.copy(metricReading = target)) }
        step.update(log.copy(value = target))
        return asset
    }
}

/**
 * Visit readings that look like the visit form's old estimate: a round hundred above the next real
 * reading, as the iOS app's `EstimatedVisitReadingsStep`. The form used to save its guess when nobody
 * changed it.
 */
object EstimatedVisitReadingsStep : DataRepairStep {
    override val id = DataRepairStepId.ESTIMATED_VISIT_READINGS
    override val group = DataRepairGroup.ESTIMATES_KEPT_AS_READINGS

    private const val ROUND = 100.0

    /** The visit's reading, when it looks like an estimate: a whole hundred, and the next reading after it lower. */
    fun estimatedLog(view: BinderView, entry: HistoryEntry): MeasurementLog? {
        val reading = entry.metricReading ?: return null
        val asset = entry.asset ?: return null
        if (entry.obligation != null || reading <= 0 || reading % ROUND != 0.0) return null
        val logs = HouseholdReadings.readings(view, asset).filter { it.kind.isCumulative }
        val log = logs.firstOrNull { it.recordedAt == entry.occurredAt && it.value == reading } ?: return null
        // The next reading on the same counter: a new meter or dashboard after it is no sign.
        val counter = HouseholdReadings.counters(view, asset, log.measurementUnit)
            .firstOrNull { readings -> readings.any { it.pk == log.pk } }.orEmpty()
        val next = counter.filter { it.recordedAt > log.recordedAt }.minByOrNull { it.recordedAt } ?: return null
        return log.takeIf { next.value < reading }
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val view = scan.view
        return view.all(Tables.history).filterNot { it.isExample }.mapNotNull { entry -> finding(scan, entry) }
    }

    private fun finding(scan: DataRepairScan, entry: HistoryEntry): DataRepairFinding? {
        val view = scan.view
        val log = estimatedLog(view, entry)?.takeIf { it.id.toString() !in scan.flaggedReadings } ?: return null
        val asset = entry.asset?.let { view.row(Tables.assets, it) } ?: return null
        scan.flaggedReadings += log.id.toString()
        scan.flaggedAssets += asset.id.toString()
        return DataRepairFinding(
            id = DataRepairFinding.id(id, RepairReading.key(entry.id), SwiftNumber.description(log.value)),
            step = id,
            subject = DataRepairSubject.EstimatedVisitReading(
                entryId = entry.id,
                value = log.value,
                unit = log.measurementUnit,
                section = shown(asset.name),
                day = CalendarDay.of(entry.occurredAt, scan.context.zone),
            ),
        )
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        for (subject in findings.mapNotNull { it.subject as? DataRepairSubject.EstimatedVisitReading }) {
            val entry = step.find(Tables.history, subject.entryId.toString())
            val log = entry?.let { estimatedLog(step, it) }?.takeIf { it.value == subject.value }
            val asset = entry?.asset
            if (log != null && asset != null) {
                HouseholdReadings.removeReading(step, log, asset)
                HeroMetric.sync(step, asset)
            }
        }
    }
}

/**
 * A hero value (the kilometres on the section) that isn't what the readings say, after an earlier
 * version saved it wrongly: worked out from the readings again, as the iOS app's `HeroFromReadingsStep`.
 */
object HeroFromReadingsStep : DataRepairStep {
    override val id = DataRepairStepId.HERO_FROM_READINGS
    override val group = DataRepairGroup.COUNTERS

    /** What a finding writes for a hero field that shows nothing: the iOS app's `-1`. */
    private const val NOTHING_SHOWN = -1.0

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> =
        scan.view.all(Tables.assets).mapNotNull { asset ->
            if (asset.isExample || asset.id.toString() in scan.flaggedAssets) return@mapNotNull null
            val mismatch = HeroMetric.mismatch(scan.view, asset) ?: return@mapNotNull null
            DataRepairFinding(
                id = DataRepairFinding.id(
                    id,
                    RepairReading.key(asset.id),
                    SwiftNumber.description(mismatch.shown ?: NOTHING_SHOWN),
                    SwiftNumber.description(mismatch.current),
                ),
                step = id,
                subject = DataRepairSubject.Hero(
                    assetId = asset.id,
                    from = mismatch.shown,
                    to = mismatch.current,
                    unit = HeroMetric.unit(listOf(mismatch.field)),
                    section = shown(asset.name),
                ),
            )
        }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        for (subject in findings.mapNotNull { it.subject as? DataRepairSubject.Hero }) {
            val asset: Asset = step.find(Tables.assets, subject.assetId.toString()) ?: continue
            // Checked again: worked out only while the hero value and the readings are as they were found.
            val mismatch = HeroMetric.mismatch(step, asset)
            if (mismatch?.shown == subject.from && mismatch?.current == subject.to) HeroMetric.sync(step, asset.pk)
        }
    }
}

private fun entriesOf(step: Step, asset: Long): List<HistoryEntry> =
    step.pointingAt(Tables.history, "asset", asset).mapNotNull { step.row(Tables.history, it) }
