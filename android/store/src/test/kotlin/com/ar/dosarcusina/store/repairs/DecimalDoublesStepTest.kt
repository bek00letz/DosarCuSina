package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.keptValues
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Numbers an earlier iOS version kept a step off are put back on their short number by themselves, once, with no
 * change time: a reading, a record's counter and a section's number (the iOS app's `DecimalDoublesRepairTests`).
 * The rule's cases are the shared vectors' (`romanian-number-correction`).
 */
class DecimalDoublesStepTest {
    private val long = noon("2025-06-01")
    private val binder = TestBinderStore()

    private fun context() = DataRepairContext(bucharest, binder.now, Catalog.builtIn, binder.locks)

    @Test
    fun numbersKeptAStepOffArePutBackByThemselvesOnce() {
        val short = 1_234.567
        val off = Math.nextUp(short)
        binder.earlier { database ->
            database.templates().insert(
                CategoryTemplate(
                    key = "custom.boiler", name = "Centrală", isBuiltIn = false, updatedAt = long,
                    sectionsData = """[{"fields":[{"key":"boiler.index","label":"Index","role":"heroMetric",""" +
                        """"type":"metric","unit":"m3"},{"key":"boiler.year","label":"An","type":"year"}],""" +
                        """"key":"boiler","title":"Centrală"}]""",
                ),
            )
        }
        val boiler = binder.earlier { database ->
            database.assets().insert(
                Asset(name = "Centrală Apartament", templateKey = "custom.boiler", updatedAt = long).with(
                    "boiler.index" to FieldValue.Number(off), "boiler.year" to FieldValue.Number(2018.0),
                    "boiler.other" to FieldValue.Number(off),
                ),
            )
        }
        val reading = binder.earlier { database ->
            database.readings().insert(
                MeasurementLog(kindRaw = "gas", value = off, unit = "m3", asset = boiler, updatedAt = long),
            )
        }
        val kilometres = binder.earlier { database ->
            database.readings().insert(
                MeasurementLog(kindRaw = "odometer", value = 45_724.0, unit = "km", asset = boiler, updatedAt = long),
            )
        }
        val visit = binder.earlier { database ->
            database.history().insert(
                HistoryEntry(
                    kindRaw = "maintenance", title = "Revizie", metricReading = off, asset = boiler, updatedAt = long,
                ),
            )
        }

        val found = repairs(binder).detect()
        assertTrue(found.none { it.step == DataRepairStepId.DECIMAL_DOUBLES }, "It never asks")
        val snapshot = binder.snapshot()
        assertEquals(short, snapshot.row(Tables.readings, reading)!!.value)
        val counter = snapshot.row(Tables.history, visit)!!.metricReading
        assertEquals(short, counter, "The record's counter stays the reading's")
        assertEquals(45_724.0, snapshot.row(Tables.readings, kilometres)!!.value)
        val section = snapshot.row(Tables.assets, boiler)!!
        val values = section.keptValues.value
        assertEquals(FieldValue.Number(short), values["boiler.index"])
        assertEquals(FieldValue.Number(2018.0), values["boiler.year"])
        assertEquals(FieldValue.Number(off), values["boiler.other"], "A value no field of the category names stays")
        assertEquals(long, section.updatedAt, "Only how the number is stored: no change time")
        assertEquals(long, snapshot.row(Tables.readings, reading)!!.updatedAt)

        val before = binder.database()
        val again = binder.unit.perform(ChangeOrigin.APP) { DecimalDoublesStep.runByItself(it, context()) }
        assertEquals(0, again, "A second run changes nothing")
        assertEquals(before, binder.database())
    }
}
