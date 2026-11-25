package com.ar.dosarcusina.core.values

/**
 * The unit a reading, a number field or a counted recurrence is in, known by a stable key, as
 * the iOS app's `MeasurementUnit` (ios/DosarCuSina/Models/Values/MeasurementUnit.swift).
 *
 * The key is the unit's identity and what archives store (`km`, `h`, `kwh`, `m3`, …); [label]
 * is what a person sees and never takes part in a comparison. Reading accepts every form
 * written so far (the key, the label, the spellings earlier versions stored), ignoring case,
 * diacritics, wide forms and superscripts; a unit outside the catalog (a category of the
 * person's own, "ore motor") is kept as written, trimmed. Writing always writes the key.
 */
class MeasurementUnit private constructor(val key: String) {
    /** What a person sees after a number: "km", "kWh", "m³", "cafele"; a unit of the person's own as written. */
    val label: String
        get() = when (key) {
            "km" -> "km"
            "h" -> "h"
            "kwh" -> "kWh"
            "m3" -> "m³"
            "gcal" -> "Gcal"
            "kg" -> "kg"
            "mgdl" -> "mg/dL"
            "mmhg" -> "mmHg"
            "dpt" -> "dpt"
            "cm3" -> "cm³"
            "hp" -> "CP"
            "m2" -> "m²"
            // The Romanian labels, as the iOS app's String Catalog has them.
            "months" -> "luni"
            "shots" -> "cafele"
            else -> key
        }

    /** Whether the key is one of the catalog's, rather than the person's own unit. */
    val isCatalog: Boolean get() = CATALOG.contains(this)

    /** Every spelling of a catalog unit read as it, folded: the key, the label and what earlier versions wrote. */
    internal val spellings: Set<String>
        get() {
            val earlier = when (key) {
                // Capture wrote "mc" for gas and water; the number reader accepted "m3".
                "m3" -> listOf("m³", "mc", "m3")
                // The Romanian labels before keys, whatever language the app now speaks.
                "months" -> listOf("luni")
                "shots" -> listOf("cafele")
                else -> emptyList()
            }
            return (listOf(key, label) + earlier).map { fold(it) }.toSet()
        }

    override fun equals(other: Any?): Boolean = other is MeasurementUnit && other.key == key

    override fun hashCode(): Int = key.hashCode()

    override fun toString(): String = label

    companion object {
        val KILOMETRES: MeasurementUnit = MeasurementUnit("km")
        val ENGINE_HOURS: MeasurementUnit = MeasurementUnit("h")
        val KILOWATT_HOURS: MeasurementUnit = MeasurementUnit("kwh")
        val CUBIC_METRES: MeasurementUnit = MeasurementUnit("m3")
        val GIGACALORIES: MeasurementUnit = MeasurementUnit("gcal")
        val KILOGRAMS: MeasurementUnit = MeasurementUnit("kg")
        val MILLIGRAMS_PER_DECILITRE: MeasurementUnit = MeasurementUnit("mgdl")
        val MILLIMETRES_OF_MERCURY: MeasurementUnit = MeasurementUnit("mmhg")
        val DIOPTRES: MeasurementUnit = MeasurementUnit("dpt")
        val CUBIC_CENTIMETRES: MeasurementUnit = MeasurementUnit("cm3")
        val HORSEPOWER: MeasurementUnit = MeasurementUnit("hp")
        val SQUARE_METRES: MeasurementUnit = MeasurementUnit("m2")
        val MONTHS: MeasurementUnit = MeasurementUnit("months")

        /** Coffees made by an espresso machine. */
        val SHOTS: MeasurementUnit = MeasurementUnit("shots")

        /** Every unit the app knows. */
        val CATALOG: List<MeasurementUnit> = listOf(
            KILOMETRES, ENGINE_HOURS, KILOWATT_HOURS, CUBIC_METRES, GIGACALORIES, KILOGRAMS,
            MILLIGRAMS_PER_DECILITRE, MILLIMETRES_OF_MERCURY, DIOPTRES, CUBIC_CENTIMETRES, HORSEPOWER,
            SQUARE_METRES, MONTHS, SHOTS,
        )

        /** Units a meter index printed on a bill may carry after its number. */
        val METER_UNITS: List<MeasurementUnit> = listOf(CUBIC_METRES, KILOWATT_HOURS, GIGACALORIES, KILOGRAMS)

        /** Every folded spelling of the catalog's units, the first unit that has it. */
        private val bySpelling: Map<String, MeasurementUnit> by lazy {
            val table = LinkedHashMap<String, MeasurementUnit>()
            for (unit in CATALOG) for (spelling in unit.spellings) table.putIfAbsent(spelling, unit)
            table
        }

        /** Any stored or typed form: a key, a label, an earlier spelling, or a unit of one's own. Null for no text. */
        fun of(text: String?): MeasurementUnit? {
            if (text == null) return null
            val trimmed = TextRules.trimming(text, TextRules::isWhitespaceOrNewline)
            if (trimmed.isEmpty()) return null
            return bySpelling[fold(trimmed)] ?: MeasurementUnit(trimmed)
        }

        /** The key to store for text in any form: "" stays "" (no unit). */
        fun storedKey(text: String): String = of(text)?.key ?: ""

        /** Lowercase, no diacritics, superscript digits as digits. */
        internal fun fold(text: String): String = RomanianText.fold(text).replace("³", "3").replace("²", "2")
    }
}
