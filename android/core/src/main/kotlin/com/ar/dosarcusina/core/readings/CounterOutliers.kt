package com.ar.dosarcusina.core.readings

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.abs
import kotlin.math.floor

/**
 * Counter readings an earlier version saved wrongly: 10 or more times off both their neighbours, or a
 * neighbour divided by a power of ten (457 next to 45724: the number lost its thousands), as the rule of
 * the iOS app's `CounterOutliersStep` (ios/DosarCuSina/Services/Repairs/DataRepairSteps.swift). Pure: the
 * repair list reads each counter's readings ([CounterReadings.counters]) and offers what this finds.
 */
object CounterOutliers {
    /** What a series says about one reading: corrected to a neighbour's value, or removed. */
    sealed interface Verdict {
        data class Correct(val to: Double) : Verdict

        data object Remove : Verdict
    }

    private const val TIMES_OFF = 10.0
    private const val LARGEST_DIVISOR = 1_000_000.0
    private const val CLOSE_ENOUGH = 0.05

    /**
     * The verdict for each reading of one counter, oldest first, by its place. A reading that lost its
     * digits is lower than the one before it (a counter only goes up), so a small first reading of a new
     * car next to a later, larger one is never offered.
     */
    fun verdicts(values: List<Double>): Map<Int, Verdict> {
        val found = LinkedHashMap<Int, Verdict>()
        for (index in values.indices) {
            val value = values[index]
            val neighbours = listOf(index - 1, index + 1).filter { it in values.indices }.map { values[it] }
            val breaksOrder = index > 0 && value < values[index - 1]
            val source = if (breaksOrder) neighbours.firstOrNull { lostDigits(value, it) } else null
            if (source != null) {
                found[index] = Verdict.Correct(source)
            } else if (isTenTimesOff(value, neighbours)) {
                found[index] = Verdict.Remove
            }
        }
        return found
    }

    private fun isTenTimesOff(value: Double, neighbours: List<Double>): Boolean =
        neighbours.size == 2 && neighbours.all { it > 0 } &&
            (neighbours.all { value >= it * TIMES_OFF } || neighbours.all { value * TIMES_OFF <= it })

    /** Whether [value] is [neighbour] with its last digits lost: 457 for 45724 (÷100). */
    fun lostDigits(value: Double, neighbour: Double): Boolean {
        if (value <= 0 || neighbour < value * TIMES_OFF) return false
        var divisor = TIMES_OFF
        while (divisor <= LARGEST_DIVISOR && neighbour / divisor >= 1) {
            val shrunk = neighbour / divisor
            val matches = value == floor(shrunk) || value == schoolRounded(shrunk) || abs(value - shrunk) < CLOSE_ENOUGH
            if (matches) return true
            divisor *= TIMES_OFF
        }
        return false
    }

    /** Swift's `rounded()`: half away from zero, where Kotlin's `round` rounds half to even. */
    private fun schoolRounded(value: Double): Double = BigDecimal(value).setScale(0, RoundingMode.HALF_UP).toDouble()
}
