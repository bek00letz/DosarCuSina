package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.providers.ProviderActions
import com.ar.dosarcusina.store.providers.ProviderTrade
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.ServiceItem
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlinx.coroutines.runBlocking

/**
 * The repairs that waited on sections and firms: plants offered to the household's only home,
 * records whose section was deleted on another device kept in „Recuperate”, and firms kept twice
 * joined into one. The iOS app's `BoxGroupingTests` (plants kept before), `ParentLinksTests`
 * (lost records) and `DataRepairTests` (firms kept twice). Every value is a placeholder.
 */
class SectionRepairStepsTest {
    private val today = noon("2026-11-10")
    private val binder = TestBinderStore(now = today).also { it.launch.installBuiltIns(today) }

    private fun add(name: String, key: String, isExample: Boolean = false): Asset = binder.unit.perform { step ->
        step.insert(Asset(name = name, templateKey = key, isExample = isExample))
    }

    private fun found(step: DataRepairStepId): List<DataRepairFinding> =
        repairs(binder).detect().filter { it.step == step }

    // Plants kept before they could stand in a home

    @Test
    fun plantsOnTheirOwnAreOfferedToTheOnlyHomeAndMovedOnceApproved() {
        val flat = add("Apartament Exemplu", BuiltInTemplates.Key.HOME)
        val fern = add("Ferigă", BuiltInTemplates.Key.PLANTS)
        val basil = add("Busuioc", BuiltInTemplates.Key.PLANTS)
        add("Plantă exemplu", BuiltInTemplates.Key.PLANTS, isExample = true)
        val findings = found(DataRepairStepId.SECTIONS_INTO_THEIR_HOME)
        assertEquals(2, findings.size, "One for each plant of the person's own, examples left as they are")
        assertTrue(findings.all { it.isFixable })
        val forFern = findings.single { (it.subject as DataRepairSubject.IntoHome).section == "Ferigă" }
        assertEquals(
            DataRepairSubject.IntoHome(fern.id, flat.id, Role.HOME, "Ferigă", "Apartament Exemplu", "Plante"),
            forFern.subject,
        )
        val changed = binder.stored(fern).updatedAt
        repairs(binder).apply(listOf(forFern))
        assertEquals(flat.pk, binder.stored(fern).parent)
        assertNull(binder.stored(basil).parent, "Only what was approved")
        assertEquals(changed, binder.stored(fern).updatedAt, "The app's own step gives no change time")
        assertEquals(listOf("Busuioc"), found(DataRepairStepId.SECTIONS_INTO_THEIR_HOME).map {
            (it.subject as DataRepairSubject.IntoHome).section
        })
        assertTrue(repairs(binder).detect().any { DataRepairs.isSuggestion(it) }, "A suggestion, never a correction")
    }

    @Test
    fun withSeveralHomesTheRepairOnlySaysHowAndWithNoneSaysNothing() {
        val fern = add("Ferigă", BuiltInTemplates.Key.PLANTS)
        assertEquals(emptyList<DataRepairFinding>(), found(DataRepairStepId.SECTIONS_INTO_THEIR_HOME))
        add("Apartament Exemplu", BuiltInTemplates.Key.HOME)
        add("Casa de la țară", BuiltInTemplates.Key.HOME)
        val findings = found(DataRepairStepId.SECTIONS_INTO_THEIR_HOME)
        assertEquals(1, findings.size)
        assertFalse(findings.single().isFixable, "Which home is the person's to say")
        assertEquals("sections-into-their-home:plants:several", findings.single().id)
        repairs(binder).apply(findings)
        assertNull(binder.stored(fern).parent)
    }

    // Records whose section was deleted on another device

    /** A car's deadline, document, visit with its part, and reading; the car's deletion comes from another device. */
    private fun carDeletedElsewhere() {
        val car = add("VW Golf 2018", BuiltInTemplates.Key.VEHICLE)
        binder.unit.perform { step ->
            step.insert(Obligation(title = "ITP", dueDayISO = "2027-03-01", asset = car.pk))
            step.insert(Attachment(title = "Polița RCA", asset = car.pk))
            val visit = step.insert(HistoryEntry(kindRaw = "visit", title = "Revizie", asset = car.pk))
            step.insert(ServiceItem(name = "Filtru ulei", entry = visit.pk))
            step.insert(MeasurementLog(kindRaw = "odometer", value = 145_000.0, unit = "km", asset = car.pk))
        }
        // The database lets go by itself, as another device's deletion arrives.
        runBlocking { binder.store.database.assets().delete(binder.stored(car)) }
    }

    @Test
    fun whatLostItsSectionIsKeptInRecuperate() {
        carDeletedElsewhere()
        val findings = found(DataRepairStepId.LOST_RECORDS)
        assertEquals(4, findings.size, "A deadline, a document, a visit and a reading; never a part")
        assertEquals(
            listOf(LostRecordsStep.Kind.DEADLINE, LostRecordsStep.Kind.DOCUMENT, LostRecordsStep.Kind.HISTORY,
                LostRecordsStep.Kind.READING),
            findings.map { (it.subject as DataRepairSubject.LostRecord).kind },
        )
        repairs(binder).apply(findings)
        val recovered = Catalog.builtIn.ownCategories.recovered
        val view = binder.snapshot()
        val section = view.all(Tables.assets).single { it.id == recovered.sectionID }
        assertEquals(recovered.key, section.templateKey)
        assertEquals("Recuperate", section.name)
        assertEquals(1, view.all(Tables.obligations).count { it.asset == section.pk })
        assertEquals(1, view.all(Tables.attachments).count { it.asset == section.pk })
        assertEquals(1, view.all(Tables.history).count { it.asset == section.pk })
        assertEquals(1, view.all(Tables.readings).count { it.asset == section.pk })
        val category = view.all(Tables.templates).single { it.key == recovered.key }
        assertFalse(category.isBuiltIn)
        assertEquals(listOf("upcoming", "documents", "history"), category.pocketsRaw)
        assertEquals(emptyList<DataRepairFinding>(), found(DataRepairStepId.LOST_RECORDS))
    }

    // Firms kept twice

    @Test
    fun firmsKeptTwiceAreJoinedWithWhatEachHolds() {
        val first = ProviderActions(binder.unit, now = { noon("2026-11-01") })
        val later = ProviderActions(binder.unit, now = { noon("2026-11-02") })
        val car = add("VW Golf 2018", BuiltInTemplates.Key.VEHICLE)
        val kept = first.create("Service Exemplu SRL", listOf(ProviderTrade.MECHANIC))
        val copy = later.create(
            "SERVICE EXEMPLU SRL", listOf(ProviderTrade.TYRE_SHOP), phone = "0700 000 001", linkedTo = listOf(car),
        )
        val item = binder.unit.perform { step ->
            val visit = step.insert(HistoryEntry(kindRaw = "visit", title = "Revizie", asset = car.pk))
            step.setLinked(Tables.entryProviders, visit.pk, listOf(copy.pk))
            step.insert(ServiceItem(name = "Anvelope", entry = visit.pk, supplier = copy.pk))
        }
        applyTwice(binder, DataRepairStepId.DUPLICATE_PROVIDERS) {
            val view = binder.snapshot()
            val firms = view.all(Tables.providers)
            assertEquals(listOf(kept.id), firms.map { it.id })
            val firm = firms.single()
            assertEquals("0700000001", firm.phone, "A detail it lacked comes from the copy")
            assertEquals(listOf("mechanic", "tyreShop"), firm.trades)
            assertEquals(listOf(car.pk), view.linked(Tables.providerAssets, firm.pk))
            assertEquals(firm.pk, view.row(Tables.items, item.pk)?.supplier)
            val visit = view.all(Tables.history).single()
            assertEquals(listOf(firm.pk), view.linked(Tables.entryProviders, visit.pk))
        }
    }
}
