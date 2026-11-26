package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.history.MaintenanceLog
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.history.HistoryRecords
import com.ar.dosarcusina.store.history.HistoryWording
import com.ar.dosarcusina.store.history.VisitRecord
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.providers.ProviderTrade
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.math.BigDecimal

/**
 * The repairs that waited on the history: documents moved with their old links, visits saved without their
 * invoice, the same visit logged twice and labour kept as a part, each found, changed only with the owner's
 * OK and found no more once applied. The iOS app's `CaptureRepairTests` (stale links, visits without their
 * invoice), `VisitRepairTests` and `LabourPartsRepairTests`. Every value is a placeholder.
 */
class VisitRepairStepsTest {
    private val today = noon("2026-11-10")
    private val binder = TestBinderStore(now = today).also { it.launch.installBuiltIns(today) }

    private fun car(): Asset = binder.unit.perform { step ->
        step.insert(Asset(name = "VW Golf 2018", templateKey = BuiltInTemplates.Key.VEHICLE))
    }

    private fun firm(name: String): Provider = binder.unit.perform { step ->
        step.insert(Provider(name = name, trades = listOf(ProviderTrade.MECHANIC.raw)))
    }

    private fun found(step: DataRepairStepId): List<DataRepairFinding> =
        repairs(binder).detect().filter { it.step == step }

    private fun visits(car: Asset): List<HistoryEntry> =
        HistoryRecords.of(binder.snapshot(), binder.stored(car)).filter { it.cycleDueDayISO == null }

    /** A visit as an earlier version logged it from a photo of its invoice. */
    @Suppress("LongParameterList") // A visit's parts, as the iOS test's helper takes them.
    private fun oldVisit(
        car: Asset,
        day: String,
        total: Int?,
        firm: Provider?,
        number: String? = null,
        parts: List<String> = emptyList(),
        odometer: Double? = null,
        paperFiled: String? = null,
    ): HistoryEntry = binder.unit.performPrivate { step ->
        val entry = step.insert(
            HistoryEntry(
                kindRaw = HistoryKind.MAINTENANCE.raw, title = "Revizie", occurredAt = noon(day),
                totalCostAmount = total?.let { BigDecimal(it) }, totalCostCurrency = total?.let { "RON" },
                reference = number, metricReading = odometer, asset = car.pk,
            ),
        )
        if (firm != null) step.setLinked(Tables.entryProviders, entry.pk, listOf(firm.pk))
        for (part in parts) step.insert(ServiceItem(name = part, entry = entry.pk))
        if (odometer != null) {
            step.insert(
                MeasurementLog(
                    kindRaw = "odometer", value = odometer, unit = "km", recordedAt = noon(day), asset = car.pk,
                ),
            )
        }
        if (paperFiled != null) {
            step.insert(
                Attachment(
                    fileName = "Factură.heic", contentType = "public.heic", kindRaw = "invoice",
                    createdAt = noon(paperFiled), historyEntry = entry.pk, asset = car.pk,
                ),
            )
        }
        entry
    }

    // The same visit twice

    @Test
    fun theSameVisitLoggedTwiceIsJoinedOnlyWithTheOwnersOk() {
        val golf = car()
        val service = firm("Service Exemplu SRL")
        val first = oldVisit(golf, "2026-05-30", 480, service, parts = listOf("Ulei", "Filtru de aer"),
            odometer = 48_000.0, paperFiled = "2026-05-30")
        val second = oldVisit(golf, "2026-05-30", 480, service, number = "SRV 0000001",
            parts = listOf("Ulei", "Plăcuțe de frână"), odometer = 48_000.0, paperFiled = "2026-06-04")
        oldVisit(golf, "2026-05-30", 150, service, paperFiled = "2026-05-30")
        val view = binder.snapshot()
        val older = HistoryRecords.papers(view, first).single()
        val newer = HistoryRecords.papers(view, second).single()

        val findings = found(DataRepairStepId.SAME_VISIT_TWICE)
        assertEquals(1, findings.size, "Another total is another invoice")
        assertEquals(
            DataRepairSubject.SameVisit(second.id, listOf(first.id), CalendarDay(2026, 5, 30), "VW Golf 2018"),
            findings.single().subject,
            "The one whose paper came last stays",
        )
        assertEquals(3, visits(golf).size, "Nothing changes before the OK")

        repairs(binder).apply(findings)
        assertEquals(2, visits(golf).size)
        assertTrue(visits(golf).any { it.id == second.id })
        val kept = binder.stored(second)
        assertEquals("SRV 0000001", kept.reference)
        val items = HistoryRecords.items(binder.snapshot(), kept)
        assertEquals(setOf("Ulei", "Plăcuțe de frână", "Filtru de aer"), items.map { it.name }.toSet(), "Each part")
        assertEquals(3, items.size)
        assertEquals(listOf(48_000.0), binder.snapshot().all(Tables.readings).map { it.value }, "One reading")
        assertEquals(48_000.0, kept.metricReading)
        val newest = binder.stored(newer)
        val oldest = binder.stored(older)
        assertTrue(newest.historyEntry == kept.pk && !newest.isArchived, "The newest paper is the visit's copy")
        assertTrue(oldest.historyEntry == kept.pk && oldest.isArchived && oldest.supersededBy == newest.pk,
            "The first paper stays with the visit, archived beside it")
        assertTrue(found(DataRepairStepId.SAME_VISIT_TWICE).isEmpty(), "Found nothing once applied: idempotent")
    }

    @Test
    fun theReadingOfTheVisitThatGoesMovesToTheOneThatStays() {
        val golf = car()
        val service = firm("Service Exemplu SRL")
        oldVisit(golf, "2026-05-30", 480, service, odometer = 48_000.0, paperFiled = "2026-05-30")
        val second = oldVisit(golf, "2026-05-30", 480, null, paperFiled = "2026-06-04")
        repairs(binder).apply(found(DataRepairStepId.SAME_VISIT_TWICE))
        assertEquals(listOf(second.id), visits(golf).map { it.id })
        val kept = binder.stored(second)
        assertEquals(48_000.0, kept.metricReading, "It takes the kilometres the other visit read")
        val firms = HistoryRecords.providerNames(binder.snapshot(), kept)
        assertEquals(listOf("Service Exemplu SRL"), firms, "And its firm")
        val log = binder.snapshot().all(Tables.readings).single()
        assertTrue(HouseholdReadings.isReading(log, kept), "The reading is the visit's own")
    }

    @Test
    fun visitsThatAreNotTheSameInvoiceAreLeftAlone() {
        val golf = car()
        val service = firm("Service Exemplu SRL")
        val tyres = firm("Vulcanizare Exemplu SRL")
        oldVisit(golf, "2026-05-30", 480, service, paperFiled = "2026-05-30")
        oldVisit(golf, "2026-05-30", 480, tyres, paperFiled = "2026-05-30")
        oldVisit(golf, "2026-05-30", 480, service)
        oldVisit(golf, "2026-05-31", 480, service, paperFiled = "2026-05-31")
        oldVisit(golf, "2025-05-30", 300, service, number = "SRV 0000001", paperFiled = "2025-05-30")
        oldVisit(golf, "2026-04-30", 310, service, number = "SRV 0000001", paperFiled = "2026-04-30")
        assertTrue(found(DataRepairStepId.SAME_VISIT_TWICE).isEmpty(),
            "Another firm, a visit typed by hand, another day, a number that started again: never offered")
    }

    @Test
    fun aVisitNoLongerLoggedTwiceChangesNothing() {
        val golf = car()
        val service = firm("Service Exemplu SRL")
        oldVisit(golf, "2026-05-30", 480, service, paperFiled = "2026-05-30")
        val extra = oldVisit(golf, "2026-05-30", 480, service, paperFiled = "2026-06-04")
        val findings = found(DataRepairStepId.SAME_VISIT_TWICE)
        assertEquals(1, findings.size)
        HistoryActions(binder.unit, Words).delete(extra)
        repairs(binder).apply(findings)
        assertEquals(1, visits(golf).size, "The finding no longer holds, so it changes nothing")
    }

    // Labour kept as a part

    /** A visit as an earlier version saved it: every line a part, labour's too (`custom.<slug>`). */
    private fun labourVisit(): Pair<Asset, HistoryEntry> {
        val golf = car()
        val entry = binder.unit.performPrivate { step ->
            val entry = step.insert(
                HistoryEntry(kindRaw = HistoryKind.MAINTENANCE.raw, title = "Revizie", occurredAt = noon("2026-05-30"),
                    asset = golf.pk),
            )
            val lines = listOf(
                Triple("Plăcuțe frână față", "brakes.padsFront", 380), Triple("Odorizant", "custom.odorizant", 20),
                Triple("Manoperă", "custom.manopera", 200), Triple("Mână de lucru", "custom.mana-de-lucru", 150),
            )
            for ((name, key, cost) in lines) {
                val item = ServiceItem(name = name, componentKey = key, costAmount = BigDecimal(cost), entry = entry.pk)
                step.insert(item)
            }
            entry
        }
        return golf to entry
    }

    private fun items(entry: HistoryEntry): List<ServiceItem> = HistoryRecords.items(binder.snapshot(), entry)

    private fun tracked(golf: Asset): List<String> =
        MaintenanceLog.trackedComponents(HistoryRecords.snapshots(binder.snapshot(), binder.stored(golf)))

    @Test
    fun labourKeptAsAPartIsOfferedAndKeptAsTheVisitsLabourOnceApproved() {
        val (golf, entry) = labourVisit()
        val costs = items(entry).map { requireNotNull(it.costAmount) }.toSet()
        val findings = found(DataRepairStepId.LABOUR_PARTS)
        assertEquals(2, findings.size, "„Manoperă” and „Mână de lucru”, never a part")
        assertTrue(findings.all { it.isFixable } && !DataRepairs.isSuggestion(findings.first()), "A correction")
        val subjects = findings.map { it.subject as DataRepairSubject.LabourPart }
        assertTrue(subjects.any { it.place == "VW Golf 2018" && it.line == "Manoperă" })
        assertTrue("custom.manopera" in tracked(golf), "Before: listed as a part")

        fun check() {
            val labour = items(entry).filter { it.name == "Manoperă" || it.name == "Mână de lucru" }
            assertEquals(2, labour.size)
            assertTrue(labour.all { it.componentKey == null && it.costAmount == null && it.laborCostAmount != null })
            val now = items(entry).map { requireNotNull(it.costAmount ?: it.laborCostAmount) }.toSet()
            assertEquals(costs, now, "What the visit cost stays the same")
            val own = items(entry).single { it.name == "Odorizant" }
            assertEquals("custom.odorizant", own.componentKey, "A part of one's own stays")
            assertEquals("brakes.padsFront", items(entry).single { it.name == "Plăcuțe frână față" }.componentKey)
            assertFalse("custom.manopera" in tracked(golf) || "custom.mana-de-lucru" in tracked(golf))
        }
        repairs(binder).apply(findings)
        check()
        assertTrue(found(DataRepairStepId.LABOUR_PARTS).isEmpty(), "Found nothing once applied")
        repairs(binder).apply(findings)
        check()
    }

    @Test
    fun labourStaysAsItIsUntilTheOwnerApproves() {
        val (_, entry) = labourVisit()
        repairs(binder).detect()
        assertEquals("custom.manopera", items(entry).single { it.name == "Manoperă" }.componentKey)
        assertFalse(DataRepairs.step(DataRepairStepId.LABOUR_PARTS).runsByItself)
    }

    // A visit saved without its invoice

    @Test
    fun aVisitSavedWithoutItsInvoiceIsMatchedWithTheOneThatFitsAndLinkedOnlyWhenApproved() {
        val golf = car()
        val invoice = binder.unit.performPrivate { step ->
            step.insert(
                Attachment(
                    fileName = "factura.heic", contentType = "public.heic", kindRaw = "invoice",
                    documentDayISO = StoredDay.text(CalendarDay(2026, 11, 8)), asset = golf.pk,
                ),
            )
        }
        val visit = HistoryActions(binder.unit, Words).recordVisit(golf, VisitRecord()).value
        val findings = found(DataRepairStepId.VISITS_WITHOUT_INVOICE)
        assertEquals(1, findings.size)
        val subject = findings.single().subject as DataRepairSubject.VisitInvoice
        assertEquals(visit.id to invoice.id, subject.visitId to subject.invoiceId)
        assertNull(binder.stored(invoice).historyEntry, "Finding changes nothing")
        repairs(binder).apply(findings)
        assertEquals(visit.pk, binder.stored(invoice).historyEntry)
        repairs(binder).apply(findings)
        assertTrue(found(DataRepairStepId.VISITS_WITHOUT_INVOICE).isEmpty())
    }

    // Documents moved with their old links

    @Test
    fun documentsMovedWithTheirOldLinksAreFoundAndRepairedOnlyWhenApproved() {
        val golf = car()
        val home = binder.unit.perform { step ->
            step.insert(Asset(name = "Apartament Exemplu", templateKey = BuiltInTemplates.Key.HOME))
        }
        val moved = binder.unit.performPrivate { step ->
            val boiler = step.insert(Obligation(title = "Verificare centrală", asset = home.pk))
            // As the old move left it: in the car, still the home's deadline's.
            step.insert(
                Attachment(fileName = "a.heic", contentType = "public.heic", obligation = boiler.pk, asset = golf.pk),
            )
        }
        val findings = found(DataRepairStepId.STALE_DOCUMENT_LINKS)
        assertEquals(listOf(moved.id), findings.map { (it.subject as DataRepairSubject.StaleLinks).attachmentId })
        assertTrue(binder.stored(moved).obligation != null, "Finding changes nothing")
        repairs(binder).apply(findings)
        assertNull(binder.stored(moved).obligation)
        assertEquals(golf.pk, binder.stored(moved).asset)
        repairs(binder).apply(findings)
        assertTrue(found(DataRepairStepId.STALE_DOCUMENT_LINKS).isEmpty())
    }

    @Test
    fun theStepsStandWhereTheIosRegistryHasThem() {
        val ids = DataRepairs.steps.map { it.id }
        assertTrue(ids.indexOf(DataRepairStepId.SAME_VISIT_TWICE) > ids.indexOf(DataRepairStepId.SAME_BILL_TWICE))
        val labour = ids.indexOf(DataRepairStepId.LABOUR_PARTS)
        assertEquals(ids.indexOf(DataRepairStepId.PERSONAL_LESSON_LABELS) + 1, labour)
        assertEquals("same-visit-twice", DataRepairStepId.SAME_VISIT_TWICE.raw)
        assertEquals("labour-parts", DataRepairStepId.LABOUR_PARTS.raw)
        assertTrue(DataRepairs.steps.none { it is WaitingStep && it.id == DataRepairStepId.VISITS_WITHOUT_INVOICE })
    }

    /** The words a record's title is written with, for a visit with nothing listed. */
    private object Words : HistoryWording {
        override fun entryTitle(kind: VisitKind?): String = "Vizită"

        override fun manyJobs(count: Int): String = "Revizie: $count lucrări"
    }
}
