package com.dosarcusina.cadence

import java.util.Calendar
import kotlin.math.roundToLong

/**
 * Cadence and telemetry projection engine matching iOS CadenceCalculator.
 */
object CadenceCalculator {

    fun isLeapYear(year: Int): Boolean {
        return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    fun calculateNextDueDate(fromDate: Long, cadenceDays: Int): Long {
        if (cadenceDays <= 0) return fromDate

        // Annual / Biannual heuristics matching iOS CadenceCalculator
        if (cadenceDays == 365 || cadenceDays == 366) {
            return addYears(fromDate, 1)
        }
        if (cadenceDays == 730 || cadenceDays == 731) {
            return addYears(fromDate, 2)
        }

        val cal = Calendar.getInstance().apply {
            timeInMillis = fromDate
            add(Calendar.DAY_OF_YEAR, cadenceDays)
        }
        return cal.timeInMillis
    }

    fun addMonths(fromDate: Long, months: Int): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = fromDate
            add(Calendar.MONTH, months)
        }
        return cal.timeInMillis
    }

    fun addYears(fromDate: Long, years: Int): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = fromDate
            add(Calendar.YEAR, years)
        }
        return cal.timeInMillis
    }

    /**
     * Projects due date based on telemetry history.
     * Protects against negative rates (odometer rollbacks), zero progression, and Long arithmetic overflow.
     */
    fun projectTelemetryDueDate(
        currentMetric: Double,
        targetMetric: Double,
        history: List<Pair<Long, Double>>,
        baselineDailyRate: Double? = null,
        currentTimestamp: Long = System.currentTimeMillis()
    ): Long? {
        val remainingMetric = targetMetric - currentMetric
        if (remainingMetric <= 0) {
            return currentTimestamp
        }

        var calculatedRate: Double? = null

        if (history.size >= 2) {
            val sorted = history.sortedBy { it.first }

            // Check for negative progression / rollback anomaly across all consecutive readings
            var hasRollback = false
            for (i in 1 until sorted.size) {
                if (sorted[i].second < sorted[i - 1].second) {
                    hasRollback = true
                    break
                }
            }

            if (!hasRollback) {
                val first = sorted.first()
                val last = sorted.last()

                val deltaMetric = last.second - first.second
                val deltaDays = (last.first - first.first) / (1000.0 * 60 * 60 * 24)

                if (deltaDays > 0.001 && deltaMetric > 0.0) {
                    calculatedRate = deltaMetric / deltaDays
                }
            }
        }

        val effectiveRate = if (calculatedRate != null && calculatedRate > 0.0) {
            calculatedRate
        } else if (baselineDailyRate != null && baselineDailyRate > 0.0) {
            baselineDailyRate
        } else {
            return null
        }

        val rawEstimatedDays = remainingMetric / effectiveRate
        val maxHorizonDays = 36500L // 100 years maximum horizon; prevents Long arithmetic overflow
        val estimatedDays = if (rawEstimatedDays.isNaN() || rawEstimatedDays.isInfinite() || rawEstimatedDays > maxHorizonDays) {
            maxHorizonDays
        } else {
            maxOf(1L, rawEstimatedDays.roundToLong())
        }

        return currentTimestamp + (estimatedDays * 86_400_000L)
    }
}
