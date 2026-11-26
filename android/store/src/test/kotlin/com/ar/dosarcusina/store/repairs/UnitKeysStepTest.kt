package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.bucharest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Units an earlier version stored by their label are rewritten to their keys by themselves, once, and
 * only the unit is touched (the iOS app's `MeasurementUnitTests`, its repair part).
 */
class UnitKeysStepTest {
    private val long = noon("2025-06-01")
    private val binder = TestBinderStore()

    private fun context() = DataRepairContext(bucharest, binder.now, Catalog.builtIn, binder.locks)

    @Test
    fun theRepairRewritesStoredLabelsToKeysOnce() {
        val custom = binder.earlier { database ->
            database.templates().insert(
                CategoryTemplate(
                    key = "custom.boiler", name = "Centrală", isBuiltIn = false, updatedAt = long,
                    sectionsData = """[{"fields":[{"key":"boiler.index","label":"Index","type":"metric",""" +
                        """"unit":"mc"}],"key":"boiler","title":"Centrală"}]""",
                    blueprintsData = """[{"key":"boiler.check","kind":"maintenance","recurrence":""" +
                        """{"every":500,"type":"metric","unit":"m³"},"title":"Verificare"}]""",
                ),
            )
        }
        val boiler = binder.earlier { database ->
            database.assets().insert(Asset(name = "Centrală Apartament", templateKey = "custom.boiler"))
        }
        val deadline = binder.earlier { database ->
            database.obligations().insert(
                Obligation(
                    title = "Verificare", kindRaw = "maintenance", asset = boiler, updatedAt = long,
                    recurrenceData = """{"every":500,"fallbackEvery":1,"fallbackUnit":"year",""" +
                        """"type":"metric","unit":"mc"}""",
                ),
            )
        }
        val labels = listOf("m³", "mc", "kWh", "cafele", "")
        binder.earlier { database ->
            labels.forEachIndexed { index, label ->
                database.readings().insert(
                    MeasurementLog(
                        kindRaw = "gas", value = 100.0 + index, unit = label, asset = boiler, updatedAt = long,
                    ),
                )
            }
        }

        val changed = binder.unit.perform(ChangeOrigin.APP) { UnitKeysStep.runByItself(it, context()) }
        assertEquals(labels.size - 1 + 2, changed, "Four readings, the deadline and the category; no unit stays none")
        val snapshot = binder.snapshot()
        val units = snapshot.all(Tables.readings).sortedBy { it.value }.map { it.unit }
        assertEquals(listOf("m3", "m3", "kwh", "shots", ""), units)
        val rule = snapshot.row(Tables.obligations, deadline)!!
        assertTrue(""""unit":"m3"""" in rule.recurrenceData!!)
        assertTrue(""""fallbackUnit":"year"""" in rule.recurrenceData, "Everything else stays")
        val category = snapshot.row(Tables.templates, custom)!!
        assertTrue(""""unit":"m3"""" in category.sectionsData!!)
        assertTrue(""""unit":"m3"""" in category.blueprintsData!!)
        assertEquals(long, category.updatedAt, "Only how it is stored: no change time")

        val before = binder.database()
        val again = binder.unit.perform(ChangeOrigin.APP) { UnitKeysStep.runByItself(it, context()) }
        assertEquals(0, again, "A second run changes nothing")
        assertEquals(before, binder.database())
    }

    @Test
    fun theRepairRunsByItselfAndLeavesAnUnknownRecurrenceAsItWas() {
        val newer = """{"days":[1,3],"type":"weekdays","unit":"mc"}"""
        val deadline = binder.earlier { database ->
            database.obligations().insert(Obligation(title = "Altceva", kindRaw = "routine", recurrenceData = newer))
        }
        val log = binder.earlier { database ->
            database.readings().insert(MeasurementLog(kindRaw = "electricity", value = 1_200.0, unit = "kWh"))
        }
        val found = repairs(binder).detect()
        assertTrue(found.none { it.step == DataRepairStepId.UNIT_KEYS }, "It never asks")
        assertEquals("kwh", binder.stored(Tables.readings, log)!!.unit)
        val kept = binder.stored(Tables.obligations, deadline)!!.recurrenceData
        assertEquals(newer, kept, "A recurrence from a newer version is kept as stored")
    }

    @Test
    fun aBuiltInsUnitsAreTheCatalogs() {
        val builtIn = binder.earlier { database ->
            database.templates().insert(
                CategoryTemplate(
                    key = "vehicle", isBuiltIn = true,
                    sectionsData = """[{"fields":[{"key":"k","unit":"mc"}],"key":"s"}]""",
                ),
            )
        }
        binder.unit.perform(ChangeOrigin.APP) { UnitKeysStep.runByItself(it, context()) }
        val sections = binder.stored(Tables.templates, builtIn)!!.sectionsData!!
        assertTrue(""""unit":"mc"""" in sections, "The catalog upgrades it")
    }
}
