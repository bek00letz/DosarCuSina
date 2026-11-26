package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.readings.CounterReadings
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.readings.PlannedReading
import com.ar.dosarcusina.core.readings.ReadingBasis
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.readings.StoredReading
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MeasurementUnit
import java.math.BigDecimal
import java.time.ZoneId

/**
 * A utility subscription's meter, as the iOS app's `SubscriptionMeter`
 * (ios/DosarCuSina/Services/Subscriptions/SubscriptionMeter.swift): the index its bills print, kept as readings on
 * the subscription, since the meter belongs to that supply point (a home's gas and water are both in m³, and would
 * mix if they were kept on the home). What it measures and its unit come from the subscription's service
 * ([Service.meter]), never from the bill.
 *
 * A bill's index is recorded through the one reading path ([CounterReadings], the store's `HouseholdReadings`), as
 * [Reading.planned] plans it; never a second path.
 */
object SubscriptionMeter {
    /** The index a bill gives its subscription: the reading saving records. */
    data class Reading(
        val value: Double,
        val kind: MeasurementKind,
        val unit: MeasurementUnit,
        /** The bill's day: a document's reading is dated by the document. */
        val day: CalendarDay,
        /** How the bill says the index was taken (estimated, read); null when it doesn't say. */
        val basis: ReadingBasis? = null,
    ) {
        /**
         * Whether [stored] is this same reading: the same index in the same unit on the same day in [zone]. The one
         * rule that keeps a bill filed again from recording its index twice. (A reading taken away isn't one the store
         * hands here.)
         */
        fun isRecorded(stored: StoredReading, zone: ZoneId): Boolean =
            stored.unit == unit && stored.value == value && CalendarDay.of(stored.at, zone) == day

        /**
         * This reading as a step plans it on a subscription whose readings are [existing]: from the document, dated by
         * it at noon in [zone], with how the bill says it was taken. [replaces] is the reading the bill recorded
         * before,
         * which filing takes away first. The one plan the filing asks about and then records.
         */
        fun planned(existing: List<StoredReading>, zone: ZoneId, replaces: Set<Long> = emptySet()): PlannedReading =
            PlannedReading.plan(
                value = value, at = day.noon(zone), source = ReadingSource.DOCUMENT, unit = unit, existing = existing,
                kind = kind, basis = basis, replaces = replaces,
            )
    }

    /**
     * The reading a bill's [index] gives a subscription of [service], dated [day], taken as [basis] says (its stored
     * form: `estimated`, `read`). Null when the service has no meter or isn't known, or the index isn't a number.
     */
    fun reading(index: BigDecimal?, basis: String?, service: String?, day: CalendarDay): Reading? {
        val kind = ServiceKind.meterKind(service) ?: return null
        val unit = kind.defaultUnit ?: return null
        val value = index?.toDouble()?.takeIf { it.isFinite() && it >= 0 } ?: return null
        return Reading(value, kind, unit, day, ReadingBasis.stored(basis))
    }

    /** The newest index that counts on a subscription's meter. */
    data class Last(
        val value: Double,
        val unit: MeasurementUnit,
        val day: CalendarDay,
        /** Read off a document kept in the binder (a bill), rather than typed or imported. */
        val isFromDocument: Boolean,
        /** An estimate: the bill's estimated index, the last one so far. */
        val isEstimate: Boolean,
    )

    /**
     * The last index of a subscription's meter, from its [readings]: the last reading of the one cleaned series in its
     * [service]'s unit, its day in [zone]. [isFromDocument] says whether a stored reading has a document. Null without
     * a
     * meter or without readings.
     */
    fun last(
        service: String?,
        readings: List<StoredReading>,
        zone: ZoneId,
        isFromDocument: (StoredReading) -> Boolean,
    ): Last? {
        val unit = ServiceKind.meterKind(service)?.defaultUnit ?: return null
        val latest = CounterReadings.series(readings, unit).latest ?: return null
        val stored = readings.firstOrNull { it.unit == unit && it.at == latest.at && it.value == latest.metric }
        return Last(
            value = latest.metric, unit = unit, day = CalendarDay.of(latest.at, zone),
            isFromDocument = stored?.let(isFromDocument) ?: false, isEstimate = latest.isEstimate,
        )
    }
}
