package com.ar.dosarcusina.core.readings

import com.ar.dosarcusina.core.values.MeasurementUnit

/**
 * What a measurement reads, as the iOS app's `MeasurementKind`
 * (ios/DosarCuSina/Models/Schema/RecordModels.swift). [raw] is part of the `.dosar` contract.
 */
enum class MeasurementKind(val raw: String) {
    ELECTRICITY("electricity"),
    GAS("gas"),
    COLD_WATER("coldWater"),
    HOT_WATER("hotWater"),
    THERMAL_ENERGY("thermalEnergy"),
    BIOMARKER("biomarker"),
    BLOOD_PRESSURE("bloodPressure"),
    BODY_WEIGHT("bodyWeight"),
    DIOPTERS("diopters"),
    ODOMETER("odometer"),
    ENGINE_HOURS("engineHours"),
    CYCLES("cycles"),
    CUSTOM("custom"),
    ;

    /** The unit a reading of this kind is in when nothing says otherwise; null when it has none. */
    val defaultUnit: MeasurementUnit?
        get() = when (this) {
            ELECTRICITY -> MeasurementUnit.KILOWATT_HOURS
            GAS, COLD_WATER, HOT_WATER -> MeasurementUnit.CUBIC_METRES
            THERMAL_ENERGY -> MeasurementUnit.GIGACALORIES
            BIOMARKER -> MeasurementUnit.MILLIGRAMS_PER_DECILITRE
            BLOOD_PRESSURE -> MeasurementUnit.MILLIMETRES_OF_MERCURY
            BODY_WEIGHT -> MeasurementUnit.KILOGRAMS
            DIOPTERS -> MeasurementUnit.DIOPTRES
            ODOMETER -> MeasurementUnit.KILOMETRES
            ENGINE_HOURS -> MeasurementUnit.ENGINE_HOURS
            CYCLES, CUSTOM -> null
        }

    /** Readings that only go up, so a smaller value is a typo or a reset. */
    val isCumulative: Boolean
        get() = when (this) {
            ELECTRICITY, GAS, COLD_WATER, HOT_WATER, THERMAL_ENERGY, ODOMETER, ENGINE_HOURS, CYCLES -> true
            BIOMARKER, BLOOD_PRESSURE, BODY_WEIGHT, DIOPTERS, CUSTOM -> false
        }

    /**
     * A utility's meter, whose bills may print an index the provider estimated between two readings
     * ("index estimat"), corrected later by a real one. A lower reading on such a counter is most often
     * that correction, so the question a lower reading asks offers "Era o estimare"
     * ([LowerReadingAnswer.WAS_ESTIMATE]). A car's dashboard or an engine's hours are always read.
     */
    val mayBeEstimated: Boolean
        get() = when (this) {
            ELECTRICITY, GAS, COLD_WATER, HOT_WATER, THERMAL_ENERGY -> true
            ODOMETER, ENGINE_HOURS, CYCLES, BIOMARKER, BLOOD_PRESSURE, BODY_WEIGHT, DIOPTERS, CUSTOM -> false
        }

    companion object {
        private val byRaw = entries.associateBy { it.raw }

        /** The kind stored as [raw]; one a newer build wrote that this one doesn't know reads as [CUSTOM]. */
        fun stored(raw: String): MeasurementKind = byRaw[raw] ?: CUSTOM

        /** The usual kind for a unit, used when a reading comes from a category's field. */
        fun forUnit(unit: MeasurementUnit?): MeasurementKind = when (unit) {
            MeasurementUnit.KILOMETRES -> ODOMETER
            MeasurementUnit.KILOGRAMS -> BODY_WEIGHT
            MeasurementUnit.ENGINE_HOURS -> ENGINE_HOURS
            MeasurementUnit.KILOWATT_HOURS -> ELECTRICITY
            else -> CYCLES
        }
    }
}

/**
 * Whether a reading was read off the counter or is an estimate of it, as the iOS app's `ReadingBasis`.
 * Stored on the reading ([raw] is part of the `.dosar` contract); none when nothing says.
 */
enum class ReadingBasis(val raw: String) {
    /**
     * Read off the counter: by the person, by the distributor, or a self-reading a bill prints, and the
     * index of a regularisation bill, which corrects the estimates before it.
     */
    READ("read"),

    /**
     * An estimate of the counter: the index a bill prints as estimated, or one the person said was
     * ("Era o estimare"). It counts only until a later reading of its counter is lower.
     */
    ESTIMATED("estimated"),
    ;

    companion object {
        /** The basis stored as [raw]; null for none, or for a key a newer build wrote (kept as it was until set). */
        fun stored(raw: String?): ReadingBasis? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Where a counter reading comes from, for the step that records it, as the iOS app's `ReadingSource`.
 * Not stored itself: what is stored is how the reading was taken ([ReadingBasis]).
 */
enum class ReadingSource {
    /** Read off the counter by the person: the edit form, the visit form, "Gata". */
    PERSON,

    /** Printed on a document (an invoice's "Km bord", a bill's index), dated by the document. */
    DOCUMENT,

    /** Worked out from the pace so far. Only ever a placeholder in a field: never stored. */
    ESTIMATE,
}
