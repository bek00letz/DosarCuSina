package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/**
 * The example household ("Explore with examples"), as the iOS app declares it once
 * (`ExampleHousehold.standard`, ios/DosarCuSina/Services/Examples/ExampleHousehold.swift): the steps
 * its loader takes, in order, exported by the iOS tests to `shared/catalog/examples/household.json`
 * (`ExampleHouseholdExportTests`), copied into this module's resources as it is built, and read here.
 * Android never declares a household of its own: the store's loader makes each step through its
 * actions (`store.examples.ExampleDataService`). Its names and values are the household's made-up
 * data, not the app's words.
 */
class ExampleHousehold(val steps: List<ExampleStep>) {
    companion object {
        /** The household this build carries, read once. */
        val builtIn: ExampleHousehold by lazy { read(Catalog.resource(Catalog.File.EXAMPLES)) }

        /** The household [text] declares; a [CatalogError] when it can't be read whole. */
        fun read(text: String): ExampleHousehold {
            val file = MachineText.parseOrNull(text)?.obj(Catalog.File.EXAMPLES.fileName)
                ?: throw CatalogError("examples/household.json isn't JSON")
            return ExampleHousehold(file.list("steps").mapIndexed { index, step -> ExampleStep.read(step, index) })
        }
    }
}

/** One thing the example loader makes, through one action, as the iOS `ExampleHousehold.Step`. */
sealed interface ExampleStep {
    /** A section, made as adding one makes it; later steps know it by [ref]. */
    data class Section(
        val ref: String,
        val category: String,
        val name: String,
        val values: Map<String, ExampleValue>,
        /** The first day of each deadline the example gives, by its blueprint, in days from today. */
        val firstDue: Map<String, Int>,
        /** The ref of the section it is filed under. */
        val parent: String?,
    ) : ExampleStep

    /** A person or firm, linked to the sections [linkedTo] names. [trades] are their stored keys. */
    data class Firm(
        val ref: String,
        val name: String,
        val trades: List<String>,
        val phone: String?,
        val linkedTo: List<String>,
        val rating: Int?,
        val wouldCallAgain: Boolean?,
    ) : ExampleStep

    /** A record of [section]'s history, of the kind stored as [kind], [daysFromNow] days from now. */
    data class Record(
        val section: String,
        val kind: String,
        val title: String,
        val daysFromNow: Int,
        val metricReading: Double?,
        val totalCost: Money?,
        val items: List<ExampleItem>,
        /** The refs of the firms who did it. */
        val firms: List<String>,
        val rating: Int?,
    ) : ExampleStep

    /** A completion from before the binder knew [section]'s deadline [deadline] (a blueprint key). */
    data class PastCompletion(
        val section: String,
        val deadline: String,
        val daysFromNow: Int,
        val cost: Money?,
    ) : ExampleStep

    /** A reading of [section], of the kind stored as [kind]. */
    data class Reading(
        val section: String,
        val kind: String,
        val name: String?,
        val value: Double,
        val daysFromNow: Int,
    ) : ExampleStep

    companion object {
        /** The step at [index]: one key naming its kind, holding it. */
        fun read(element: JsonElement, index: Int): ExampleStep {
            val step = element.obj("steps[$index]")
            val kind = step.keys.singleOrNull() ?: throw CatalogError("steps[$index] isn't one step")
            val fields = step.objectAt(kind)
            return when (kind) {
                "section" -> section(fields)
                "firm" -> firm(fields)
                "record" -> record(fields)
                "pastCompletion" -> PastCompletion(
                    fields.string("section"), fields.string("deadline"), fields.int("daysFromNow"),
                    fields.money("cost"),
                )
                "reading" -> Reading(
                    fields.string("section"), fields.string("kind"), fields.optional("name")?.text("name"),
                    fields.double("value"), fields.int("daysFromNow"),
                )
                else -> throw CatalogError("steps[$index] is a $kind, which this build doesn't make")
            }
        }

        private fun section(fields: JsonObject) = Section(
            ref = fields.string("ref"),
            category = fields.string("category"),
            name = fields.string("name"),
            values = fields.objectAt("values").mapValues { (key, value) -> ExampleValue.read(value, key) },
            firstDue = fields.objectAt("firstDue").let { due -> due.mapValues { (key, _) -> due.int(key) } },
            parent = fields.optional("parent")?.text("parent"),
        )

        private fun firm(fields: JsonObject) = Firm(
            ref = fields.string("ref"),
            name = fields.string("name"),
            trades = fields.list("trades").map { it.text("trades") },
            phone = fields.optional("phone")?.text("phone"),
            linkedTo = fields.list("linkedTo").map { it.text("linkedTo") },
            rating = fields.optional("rating")?.let { fields.int("rating") },
            wouldCallAgain = fields.optional("wouldCallAgain")?.let {
                (it as? JsonPrimitive)?.takeIf { value -> !value.isString }?.booleanOrNull
                    ?: throw CatalogError("wouldCallAgain isn't true or false")
            },
        )

        private fun record(fields: JsonObject) = Record(
            section = fields.string("section"),
            kind = fields.string("kind"),
            title = fields.string("title"),
            daysFromNow = fields.int("daysFromNow"),
            metricReading = fields.optional("metricReading")?.let { fields.double("metricReading") },
            totalCost = fields.money("totalCost"),
            items = fields.list("items").map { item ->
                val line = item.obj("items")
                ExampleItem(
                    line.string("name"), line.optional("partBrandOrCode")?.text("partBrandOrCode"),
                    line.money("cost"),
                )
            },
            firms = fields.list("firms").map { it.text("firms") },
            rating = fields.optional("rating")?.let { fields.int("rating") },
        )
    }
}

/** One line of a record: what was done or bought, the part's brand or code, and what it cost. */
data class ExampleItem(val name: String, val partBrandOrCode: String?, val cost: Money?)

/** A value of a section's field, as the iOS `ExampleHousehold.Value`. */
sealed interface ExampleValue {
    /** A value as a section keeps it. */
    data class Kept(val value: FieldValue) : ExampleValue

    /** The day this many days from the day the examples load (negative: before it). */
    data class DayFromToday(val days: Int) : ExampleValue

    /** The value a section keeps, on [today]. */
    fun on(today: CalendarDay): FieldValue = when (this) {
        is Kept -> value
        is DayFromToday -> FieldValue.Day(today.addingDays(days))
    }

    companion object {
        /** The value of field [key]: a kept value, or `{"type": "dayFromToday", "days": n}`. */
        fun read(element: JsonElement, key: String): ExampleValue {
            val fields = element.obj(key)
            if (fields["type"]?.text("$key.type") == DAY_FROM_TODAY) return DayFromToday(fields.int("days"))
            return Kept(FieldValue.read(element) ?: throw CatalogError("$key's value can't be read by this build"))
        }

        private const val DAY_FROM_TODAY = "dayFromToday"
    }
}

private fun JsonObject.optional(name: String): JsonElement? = this[name]?.takeUnless { it is JsonNull }

private fun JsonObject.objectAt(name: String): JsonObject =
    this[name]?.obj(name) ?: throw CatalogError("$name is missing")

private fun JsonObject.double(name: String): Double =
    (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
        ?: throw CatalogError("$name isn't a number")

private fun JsonObject.money(name: String): Money? =
    optional(name)?.let { Money.fromJson(it) ?: throw CatalogError("$name isn't an amount") }
