package com.dosarcusina.cadence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class CadenceCalculatorTest {

    @Test
    fun testLeapYearIdentification() {
        assertTrue(CadenceCalculator.isLeapYear(2024))
        assertFalse(CadenceCalculator.isLeapYear(2025))
        assertFalse(CadenceCalculator.isLeapYear(2026))
        assertFalse(CadenceCalculator.isLeapYear(2027))
        assertTrue(CadenceCalculator.isLeapYear(2028))
        assertTrue(CadenceCalculator.isLeapYear(2000))
        assertFalse(CadenceCalculator.isLeapYear(1900))
        assertFalse(CadenceCalculator.isLeapYear(2100))
    }

    @Test
    fun testCalendarIntervalDays() {
        val cal = Calendar.getInstance().apply {
            set(2026, Calendar.MAY, 1, 10, 0, 0)
        }
        val nextDue = CadenceCalculator.calculateNextDueDate(cal.timeInMillis, 30)
        val resultCal = Calendar.getInstance().apply { timeInMillis = nextDue }

        assertEquals(2026, resultCal.get(Calendar.YEAR))
        assertEquals(Calendar.MAY, resultCal.get(Calendar.MONTH))
        assertEquals(31, resultCal.get(Calendar.DAY_OF_MONTH))
    }

    @Test
    fun testMonthRolloverClampingNonLeapYear() {
        // Jan 31, 2026 + 1 month -> Feb 28, 2026
        val cal = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 31, 10, 0, 0)
        }
        val nextDue = CadenceCalculator.addMonths(cal.timeInMillis, 1)
        val resultCal = Calendar.getInstance().apply { timeInMillis = nextDue }

        assertEquals(2026, resultCal.get(Calendar.YEAR))
        assertEquals(Calendar.FEBRUARY, resultCal.get(Calendar.MONTH))
        assertEquals(28, resultCal.get(Calendar.DAY_OF_MONTH))
    }

    @Test
    fun testMonthRolloverClampingLeapYear() {
        // Jan 31, 2024 (leap year) + 1 month -> Feb 29, 2024
        val cal = Calendar.getInstance().apply {
            set(2024, Calendar.JANUARY, 31, 10, 0, 0)
        }
        val nextDue = CadenceCalculator.addMonths(cal.timeInMillis, 1)
        val resultCal = Calendar.getInstance().apply { timeInMillis = nextDue }

        assertEquals(2024, resultCal.get(Calendar.YEAR))
        assertEquals(Calendar.FEBRUARY, resultCal.get(Calendar.MONTH))
        assertEquals(29, resultCal.get(Calendar.DAY_OF_MONTH))
    }

    @Test
    fun testLeapDayAnnualRolloverNonLeap() {
        // Feb 29, 2024 + 1 year -> Feb 28, 2025
        val cal = Calendar.getInstance().apply {
            set(2024, Calendar.FEBRUARY, 29, 10, 0, 0)
        }
        val nextDue = CadenceCalculator.addYears(cal.timeInMillis, 1)
        val resultCal = Calendar.getInstance().apply { timeInMillis = nextDue }

        assertEquals(2025, resultCal.get(Calendar.YEAR))
        assertEquals(Calendar.FEBRUARY, resultCal.get(Calendar.MONTH))
        assertEquals(28, resultCal.get(Calendar.DAY_OF_MONTH))
    }

    @Test
    fun testLeapDayAnnualRolloverToNextLeapYear() {
        // Feb 29, 2024 + 4 years -> Feb 29, 2028
        val cal = Calendar.getInstance().apply {
            set(2024, Calendar.FEBRUARY, 29, 10, 0, 0)
        }
        val nextDue = CadenceCalculator.addYears(cal.timeInMillis, 4)
        val resultCal = Calendar.getInstance().apply { timeInMillis = nextDue }

        assertEquals(2028, resultCal.get(Calendar.YEAR))
        assertEquals(Calendar.FEBRUARY, resultCal.get(Calendar.MONTH))
        assertEquals(29, resultCal.get(Calendar.DAY_OF_MONTH))
    }

    @Test
    fun testTelemetryBurnRateProjection() {
        val day0 = 1700000000000L
        val day40 = day0 + (40L * 86_400_000L)

        // 10,000 km at Day 0; 12,000 km at Day 40 -> 2,000 km in 40 days = 50 km/day
        // Target 15,000 km -> 3,000 km remaining / 50 km/day = 60 days
        val history = listOf(
            Pair(day0, 10000.0),
            Pair(day40, 12000.0)
        )

        val projected = CadenceCalculator.projectTelemetryDueDate(
            currentMetric = 12000.0,
            targetMetric = 15000.0,
            history = history,
            currentTimestamp = day40
        )

        val expected = day40 + (60L * 86_400_000L)
        assertEquals(expected, projected)
    }

    @Test
    fun testTelemetryTargetAlreadyExceeded() {
        val now = 1700000000000L
        val history = listOf(Pair(now - 86400000L, 10000.0), Pair(now, 15500.0))
        val projected = CadenceCalculator.projectTelemetryDueDate(
            currentMetric = 15500.0,
            targetMetric = 15000.0,
            history = history,
            currentTimestamp = now
        )
        // Should return immediate timestamp
        assertEquals(now, projected)
    }

    @Test
    fun testTelemetryZeroBurnRateReturnsNull() {
        val now = 1700000000000L
        val history = listOf(Pair(now - 86400000L, 10000.0), Pair(now, 10000.0))
        val projected = CadenceCalculator.projectTelemetryDueDate(
            currentMetric = 10000.0,
            targetMetric = 15000.0,
            history = history,
            currentTimestamp = now
        )
        assertNull(projected)
    }

    @Test
    fun testTelemetryOdometerRollbackAnomalyProtection() {
        val now = 1700000000000L
        // Reading regresses from 12,000 to 11,000 km (rollback anomaly)
        val history = listOf(
            Pair(now - 86400000L * 2, 10000.0),
            Pair(now - 86400000L, 12000.0),
            Pair(now, 11000.0)
        )
        val projected = CadenceCalculator.projectTelemetryDueDate(
            currentMetric = 11000.0,
            targetMetric = 15000.0,
            history = history,
            currentTimestamp = now
        )
        assertNull(projected)

        // With baseline fallback, it recovers gracefully using baseline rate
        val projectedWithBaseline = CadenceCalculator.projectTelemetryDueDate(
            currentMetric = 11000.0,
            targetMetric = 15000.0,
            history = history,
            baselineDailyRate = 40.0,
            currentTimestamp = now
        )
        // 4000 km remaining / 40 km/day = 100 days
        assertEquals(now + 100L * 86_400_000L, projectedWithBaseline)
    }

    @Test
    fun testTelemetryLongArithmeticOverflowProtection() {
        val now = 1700000000000L
        // Tiny burn rate that would overflow raw Long calculation without cap
        val history = listOf(
            Pair(now - 86400000L, 1000.0),
            Pair(now, 1000.00000001)
        )
        val projected = CadenceCalculator.projectTelemetryDueDate(
            currentMetric = 1000.0,
            targetMetric = 100000.0,
            history = history,
            currentTimestamp = now
        )
        // Must not crash or produce negative timestamps (overflow)
        assertTrue(projected != null && projected > now)
    }
}
