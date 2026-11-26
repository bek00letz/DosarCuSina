package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.store.IosModel.Kind
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.withKeptFacts
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.EnumSource
import java.io.File
import java.math.BigDecimal
import java.util.UUID

/**
 * One undo for every step: each undoable step returns a receipt of exactly what it changed, and
 * undo puts the binder back as it was before, record by record (the iOS app's `UndoReceiptTests`).
 * The steps here are written with the step's own operations, as Phase 3's actions will be.
 */
class UndoReceiptTest {
    /** A household: a car with three deadlines, a home with rows and a repair with its invoice, two people, a firm. */
    class Household(val binder: TestBinderStore) {
        val unit: UnitOfWork get() = binder.unit
        lateinit var car: Asset
        lateinit var home: Asset
        lateinit var corina: Asset
        lateinit var ion: Asset
        lateinit var card: Asset
        lateinit var rca: Obligation
        lateinit var oil: Obligation
        lateinit var kit: Obligation
        lateinit var mechanic: Provider
        lateinit var repair: HistoryEntry
        lateinit var invoice: Attachment
        lateinit var page: AttachmentPage

        fun <R : Any> now(record: R): R = binder.stored(record)

        init {
            unit.perform(now = noon("2026-11-02")) { step ->
                car = step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle"))
                home = step.insert(
                    Asset(
                        name = "Apartament",
                        templateKey = "home",
                        photoData = step.keep(picture(7, 7, 7)),
                    ).withKeptFacts(
                        KeptList.made(
                            listOf(
                                CustomFact(UUID.randomUUID(), "Cod interfon", "12"),
                                CustomFact(UUID.randomUUID(), "Administrator", "Exemplu"),
                            ),
                            CustomFact.codec, CustomFact::id,
                        ),
                    ),
                )
                corina = step.insert(Asset(name = "Manole Corina", templateKey = "member"))
                ion = step.insert(Asset(name = "Popescu Ion", templateKey = "member"))
                card = step.insert(Asset(
                    name = "Carte de identitate – Manole Corina",
                    templateKey = "documents",
                    parent = corina.pk,
                ))
                rca = step.insert(Obligation(
                    title = "RCA",
                    kindRaw = "insurance",
                    dueDayISO = "2026-11-10",
                    snoozedUntilISO = "2026-11-03",
                    asset = car.pk,
                ))
                oil = step.insert(Obligation(
                    title = "Schimb ulei",
                    kindRaw = "maintenance",
                    dueDayISO = "2027-06-01",
                    asset = car.pk,
                ))
                kit = step.insert(Obligation(
                    title = "Trusă medicală",
                    kindRaw = "legal",
                    dueDayISO = "2026-12-01",
                    asset = car.pk,
                ))
                mechanic = step.insert(Provider(name = "Service Exemplu SRL", trades = listOf("mechanic")))
                repair = step.insert(HistoryEntry(
                    kindRaw = "repair",
                    title = "Robinet nou",
                    occurredAt = noon("2026-10-01"),
                    asset = home.pk,
                ))
                invoice = step.insert(Attachment(
                    title = "Factură robinet",
                    fileName = "factura.heic",
                    kindRaw = "invoice",
                    asset = home.pk,
                    historyEntry = repair.pk,
                ))
                page = step.insert(AttachmentPage(
                    index = 0,
                    imageData = step.keep(picture(5, 6, 7)),
                    attachment = invoice.pk,
                ))
            }
        }

        /** "Gata" on [deadline], as Phase 3's action will do it: its next cycle, a record of it and who did it. */
        fun complete(step: Step, deadline: Obligation, nextDue: String?, firm: Provider? = null): HistoryEntry {
            val current = requireNotNull(step.row(Tables.obligations, deadline.pk))
            val next = nextDue?.let { current.copy(dueDayISO = it, snoozedUntilISO = null) }
            step.update(next ?: current.copy(statusRaw = "done"))
            val entry = step.insert(
                HistoryEntry(
                    kindRaw = "completion",
                    title = current.title,
                    asset = current.asset,
                    obligation = current.pk,
                    cycleDueDayISO = current.dueDayISO,
                ),
            )
            if (firm != null) step.setLinked(Tables.entryProviders, entry.pk, listOf(firm.pk))
            return entry
        }

        /** A visit to the car, with a part, the kilometres and its invoice. */
        fun visit(step: Step, bytes: Int): HistoryEntry {
            val entry = step.insert(HistoryEntry(
                kindRaw = "visit",
                title = "Revizie",
                totalCostAmount = BigDecimal("690"),
                asset = car.pk,
            ))
            step.insert(ServiceItem(
                name = "Ulei motor",
                componentKey = "engine.oil",
                costAmount = BigDecimal("420"),
                entry = entry.pk,
            ))
            step.insert(MeasurementLog(kindRaw = "odometer", value = 101_000.0, asset = car.pk))
            step.insert(Attachment(
                fileName = "factura.pdf",
                contentType = "com.adobe.pdf",
                fileData = step.keep(picture(bytes, 1)),
                asset = car.pk,
                historyEntry = entry.pk,
            ))
            step.setLinked(Tables.entryProviders, entry.pk, listOf(mechanic.pk))
            return entry
        }
    }

    // Every kind of step

    enum class StepKind {
        COMPLETE_WITH_EVERYTHING, COMPLETE_A_ONE_OFF, SNOOZE, RESCHEDULE, RECORD_VISIT, MOVE_TO_ANOTHER_PERSON,
        MOVE_TO_A_NEW_PERSON, DELETE_A_FACT, ARCHIVE_A_DOCUMENT, REPLACE_A_PHOTO, PAUSE_A_DEADLINE, LINK_A_FIRM,
        DELETE_A_DEADLINE, DELETE_A_DOCUMENT_WITH_ITS_PAGES, DELETE_A_PERSONAL_DOCUMENT,
        DELETE_A_SECTION_WITH_ITS_HISTORY_AND_DOCUMENTS, DELETE_A_CAR_WITH_ITS_DEADLINES_VISITS_AND_READINGS,
        DELETE_A_PERSON_KEEPING_THEIR_DOCUMENTS, DELETE_A_PERSON_WITH_THEIR_DOCUMENTS, DELETE_A_FIRM,
        DELETE_A_CATEGORY_OF_ONES_OWN;

        /** What the household has before the step, beyond [Household]. */
        fun setUp(house: Household) {
            house.unit.perform(now = noon("2026-11-02")) { step ->
                when (this) {
                    DELETE_A_DEADLINE -> {
                        // Its completion stays in the car's history and its policy in the binder, without the link.
                        val done = house.complete(step, house.rca, "2027-11-10", house.mechanic)
                        val policy = step.insert(Attachment(
                            fileName = "polita.heic",
                            kindRaw = "policy",
                            asset = house.car.pk,
                            obligation = house.rca.pk,
                            historyEntry = done.pk,
                        ))
                        step.insert(AttachmentPage(
                            index = 0,
                            imageData = step.keep(picture(1, 2)),
                            attachment = policy.pk,
                        ))
                    }
                    DELETE_A_CAR_WITH_ITS_DEADLINES_VISITS_AND_READINGS -> house.visit(step, 8)
                    DELETE_A_FIRM -> {
                        // The firm looks after the car, did a visit with a part it supplied and issued its invoice.
                        val visit = house.visit(step, 4)
                        step.setLinked(Tables.providerAssets, house.mechanic.pk, listOf(house.car.pk))
                        for (
                            item in step.all(Tables.items).filter { it.entry == visit.pk }
                        ) step.update(item.copy(supplier = house.mechanic.pk))
                        for (
                            paper in step.all(Tables.attachments).filter { it.historyEntry == visit.pk }
                        ) step.update(paper.copy(provider = house.mechanic.pk))
                    }
                    DELETE_A_CATEGORY_OF_ONES_OWN -> step.insert(CategoryTemplate(key = "custom.tools", name = "Scule"))
                    else -> Unit
                }
            }
        }

        // One branch per kind of step.
        @Suppress("CyclomaticComplexMethod")
        fun run(house: Household): UndoReceipt = house.unit.performUndoable(now = noon("2026-11-03")) { step ->
            when (this) {
                COMPLETE_WITH_EVERYTHING -> {
                    val entry = house.complete(step, house.rca, "2027-11-10", house.mechanic)
                    step.update(requireNotNull(step.row(
                        Tables.history,
                        entry.pk,
                    )).copy(totalCostAmount = BigDecimal("1150"), note = "Plătit la ghișeu"))
                    step.insert(ServiceItem(name = "Carte verde", entry = entry.pk))
                    step.insert(MeasurementLog(kindRaw = "odometer", value = 101_000.0, asset = house.car.pk))
                }
                COMPLETE_A_ONE_OFF -> house.complete(step, house.kit, null)
                SNOOZE -> step.update(house.now(house.rca).copy(snoozedUntilISO = "2026-11-10"))
                RESCHEDULE -> step.update(house.now(house.rca).copy(dueDayISO = "2026-12-15"))
                RECORD_VISIT -> house.visit(step, 3)
                MOVE_TO_ANOTHER_PERSON -> step.update(house.now(house.card).copy(
                    parent = house.ion.pk,
                    name = "Carte de identitate – Popescu Ion",
                ))
                MOVE_TO_A_NEW_PERSON -> {
                    val ana = step.insert(Asset(name = "Manole Ana", templateKey = "member"))
                    val name = "Carte de identitate – Manole Ana"
                    step.update(house.now(house.card).copy(parent = ana.pk, name = name))
                }
                DELETE_A_FACT -> {
                    val home = house.now(house.home)
                    step.update(home.withKeptFacts(home.keptFacts.replacingItems(home.keptFacts.items.drop(1))))
                }
                ARCHIVE_A_DOCUMENT -> step.update(house.now(house.invoice).copy(isArchived = true))
                REPLACE_A_PHOTO -> step.update(house.now(house.home).copy(photoData = step.keep(picture(9, 9))))
                PAUSE_A_DEADLINE -> step.update(house.now(house.oil).copy(statusRaw = "paused"))
                LINK_A_FIRM -> step.setLinked(
                    Tables.providerAssets,
                    house.mechanic.pk,
                    listOf(house.car.pk, house.home.pk),
                )
                DELETE_A_DEADLINE -> step.delete(house.now(house.rca))
                DELETE_A_DOCUMENT_WITH_ITS_PAGES -> step.delete(house.now(house.invoice))
                DELETE_A_PERSONAL_DOCUMENT -> step.delete(house.now(house.card))
                DELETE_A_SECTION_WITH_ITS_HISTORY_AND_DOCUMENTS -> step.delete(house.now(house.home))
                DELETE_A_CAR_WITH_ITS_DEADLINES_VISITS_AND_READINGS -> step.delete(house.now(house.car))
                DELETE_A_PERSON_KEEPING_THEIR_DOCUMENTS -> step.delete(house.now(house.corina))
                DELETE_A_PERSON_WITH_THEIR_DOCUMENTS -> {
                    step.delete(house.now(house.card))
                    step.delete(house.now(house.corina))
                }
                DELETE_A_FIRM -> step.delete(house.now(house.mechanic))
                DELETE_A_CATEGORY_OF_ONES_OWN -> step.delete(requireNotNull(step.find(
                    Tables.templates,
                    "custom.tools",
                )))
            }
        }.receipt
    }

    @ParameterizedTest
    @EnumSource(StepKind::class)
    fun undoPutsBackExactlyTheStateBefore(kind: StepKind) {
        val house = Household(TestBinderStore())
        kind.setUp(house)
        val before = house.binder.database()

        val receipt = kind.run(house)
        val after = house.binder.database()
        assertTrue(differences(before, after).isNotEmpty(), "The step changed something")
        assertTrue(receipt.canUndo)
        assertTrue(
            receipt.touched.containsAll(differences(before, after).keys),
            "The receipt names every record the step changed",
        )
        // Pictures and files only by their digest, and a copy kept of exactly what the step took away.
        for (state in receipt.before.values + receipt.after.values) {
            val table = requireNotNull(Tables.named(state.ref.type))
            for (property in table.properties.filter { it.kind == StoredProperty.Kind.FILE }) {
                assertTrue(
                    state.values[property.name] is StoredValue.File,
                    "${state.ref}.${property.name} is known by its digest",
                )
            }
        }
        val taken = (filePlaces(before) - filePlaces(after)).map { it.third }.toSet()
        assertEquals(
            taken,
            receipt.files?.kept.orEmpty(),
            "The receipt keeps a copy of what the step took, and of nothing a record still has",
        )

        receipt.undo()
        val undone = house.binder.database()
        assertEquals(emptyMap<RecordRef, Set<String>>(), differences(before, undone), "Still different after undo")
        assertFalse(receipt.canUndo, "A receipt is used once")
        assertNull(receipt.files, "Once taken back, its copies go")
        val named = house.binder.snapshot().let { snapshot -> filePlaces(snapshot.states()).map { it.third }.toSet() }
        assertEquals(
            named,
            house.binder.store.files.folder.list().orEmpty().toSet(),
            "Every file a record names is back, and only those",
        )
    }

    // Undo takes back only what the step changed

    @Test
    fun anotherDeadlineCompletedSinceDoesNotStopTheUndoAndStaysDone() {
        val house = Household(TestBinderStore())
        val before = house.binder.database()
        val done = house.unit.performUndoable(now = noon("2026-11-03")) { step ->
            house.complete(step, house.rca, "2027-11-10")
        }
        val afterStep = house.binder.database()
        val kitDone = house.unit.perform(now = noon("2026-11-03")) { step -> house.complete(step, house.kit, null) }
        val afterWidget = house.binder.database()
        val byWidget = differences(afterStep, afterWidget).keys
        assertTrue(RecordRef.of(house.car) in byWidget, "The other completion is in the car's history too")

        done.receipt.undo()
        val undone = house.binder.database()
        assertEquals(byWidget, differences(before, undone).keys, "Only what the other step did is left")
        for (ref in byWidget - RecordRef.of(house.car)) assertEquals(
            afterWidget[ref],
            undone[ref],
            "$ref is as the other step left it",
        )
        assertEquals("done", house.now(house.kit).statusRaw, "The kit stays done")
        assertEquals(
            listOf(kitDone.pk),
            house.binder.snapshot().all(Tables.history).filter { it.obligation != null }.map { it.pk },
        )
    }

    @Test
    fun aNewerChangeToAnotherFieldStaysWithItsChangeTime() {
        val house = Household(TestBinderStore())
        val facts = house.now(house.home).keptFacts.items
        val receipt = house.unit.performUndoable(now = noon("2026-11-03")) { step ->
            val home = house.now(house.home)
            step.update(home.withKeptFacts(home.keptFacts.replacingItems(facts.drop(1))))
        }.receipt
        // Another screen writes the home's notes meanwhile.
        house.unit.perform(now = noon("2026-11-04")) { step ->
            step.update(house.now(house.home).copy(notes = "Cheia e la vecini"))
        }

        receipt.undo()
        val home = house.now(house.home)
        assertEquals(facts.map { it.label }, home.keptFacts.items.map { it.label }, "What the step changed is back")
        assertEquals("Cheia e la vecini", home.notes, "The newer change stays")
        assertEquals(noon("2026-11-04"), home.updatedAt, "And so does its change time")
    }

    @Test
    fun aNewerChangeToWhatTheStepChangedStopsTheUndoAndChangesNothing() {
        val house = Household(TestBinderStore())
        fun setFacts(facts: List<CustomFact>) = house.unit.performUndoable(now = noon("2026-11-03")) { step ->
            val home = house.now(house.home)
            step.update(home.withKeptFacts(home.keptFacts.replacingItems(facts)))
        }.receipt
        val receipt = setFacts(emptyList())
        setFacts(listOf(CustomFact(UUID.randomUUID(), "Cod poartă", "56")))
        val before = house.binder.database()

        assertThrows<UndoError.ChangedSince> { receipt.undo() }
        assertEquals(
            emptyMap<RecordRef,
            Set<String>>(),
            differences(before, house.binder.database()),
            "A refused undo changes nothing",
        )
        assertEquals(listOf("Cod poartă"), house.now(house.home).keptFacts.items.map { it.label })
        assertTrue(receipt.canUndo, "It can still be tried once the newer change is gone")
    }

    @Test
    fun undoRefusesWhenSomethingWasFiledSinceUnderARecordTheStepMade() {
        val house = Household(TestBinderStore())
        val moved = house.unit.performUndoable(now = noon("2026-11-03")) { step ->
            val ana = step.insert(Asset(name = "Manole Ana", templateKey = "member"))
            step.update(house.now(house.card).copy(parent = ana.pk))
            ana
        }
        house.unit.perform { step ->
            step.insert(Asset(name = "Pașaport – Manole Ana", templateKey = "documents", parent = moved.value.pk))
        }
        val before = house.binder.database()

        assertThrows<UndoError.ChangedSince> { moved.receipt.undo() }
        assertEquals(
            emptyMap<RecordRef,
            Set<String>>(),
            differences(before, house.binder.database()),
            "The passport and its person stay",
        )
    }

    @Test
    fun undoRefusesWhenTheSameRecordsChangedSince() {
        val house = Household(TestBinderStore())
        val done = house.unit.performUndoable(now = noon("2026-11-03")) { step ->
            house.complete(step, house.rca, "2027-11-10")
        }
        house.unit.perform { step -> step.update(house.now(house.rca).copy(dueDayISO = "2028-01-15")) }
        assertThrows<UndoError.ChangedSince> { done.receipt.undo() }
    }

    // Pictures and files

    @Test
    fun aDeletedDocumentsPicturesComeBackFromDisk() {
        val house = Household(TestBinderStore())
        val digest = picture(5, 6, 7).sha256
        val receipt = house.unit.performUndoable { step -> step.delete(house.now(house.invoice)) }.receipt
        val files = requireNotNull(receipt.files) { "What the delete took is kept" }
        assertTrue(digest in files.kept)
        assertTrue(File(files.folder, digest).isFile, "On disk")
        assertFalse(File(house.binder.store.files.folder, digest).exists(), "And no longer in the binder")
        assertEquals(
            StoredValue.File(digest),
            receipt.before[RecordRef.of(house.page)]?.values?.get("imageData"),
            "Known by its digest",
        )
        val folder = files.folder

        receipt.undo()
        val back = house.binder.snapshot().all(Tables.pages).single()
        assertEquals(digest, back.imageData, "The page's picture is back")
        assertTrue(File(house.binder.store.files.folder, digest).isFile)
        assertEquals(house.repair.pk, house.now(house.invoice).historyEntry)
        assertFalse(folder.exists(), "Once taken back, the copy goes")
    }

    @Test
    fun aReceiptKeepsNoCopyOfAPictureARecordStillHas() {
        val house = Household(TestBinderStore())
        val receipt = house.unit.performUndoable { step ->
            val home = house.now(house.home)
            step.update(home.withKeptFacts(home.keptFacts.replacingItems(emptyList())))
        }.receipt
        assertEquals(
            StoredValue.File(picture(7, 7, 7).sha256),
            receipt.before[RecordRef.of(house.home)]?.values?.get("photoData"),
        )
        assertNull(receipt.files, "Nothing is copied: the home still has its photo")
        receipt.undo()
        assertEquals(2, house.now(house.home).keptFacts.items.size)
    }

    @Test
    fun aReceiptLetGoOfKeepsNothingAndOffersNoUndo() {
        val house = Household(TestBinderStore())
        val receipt = house.unit.performUndoable { step -> step.delete(house.now(house.invoice)) }.receipt
        val folder = requireNotNull(receipt.files).folder
        receipt.discard()
        assertFalse(folder.exists())
        assertFalse(receipt.canUndo)
        assertThrows<UndoError.Unavailable> { receipt.undo() }
    }

    @Test
    fun whatAnEarlierRunKeptGoesAndACopyThatChangedIsNeverWrittenBack() {
        val root = scratchFolder("undo-files-")
        val earlier = File(root, "an-earlier-run").also { it.mkdirs() }
        val files = UndoFiles(root)
        val kept = picture(1, 2, 3)
        files.keep(kept)

        UndoFiles.removeLeftovers(root)
        assertFalse(earlier.exists(), "An earlier run's copies go")
        assertEquals(setOf(kept.sha256), files.files(setOf(kept.sha256))?.keys, "This run's stay")

        File(files.folder, kept.sha256).writeBytes(byteArrayOf(9))
        assertNull(files.files(setOf(kept.sha256)), "A copy that no longer matches is never written back")
        files.removeAll()
        assertFalse(files.folder.exists())
    }

    @Test
    fun aRecordReadsAsTheStoreKeepsItSoAnAmountOrAMomentAsWrittenNeverStopsAnUndo() {
        val house = Household(TestBinderStore())
        val before = house.binder.database()
        // 1150.00 is kept as 1150, a moment to the millisecond.
        val receipt = house.unit.performUndoable { step ->
            step.insert(
                HistoryEntry(
                    title = "Plată", totalCostAmount = BigDecimal("1150.00"),
                    occurredAt = java.time.Instant.parse("2026-11-03T10:00:00.123456789Z"), asset = house.car.pk,
                ),
            )
        }.receipt
        receipt.undo()
        assertEquals(emptyMap<RecordRef, Set<String>>(), differences(before, house.binder.database()))
    }

    // Steps and receipts

    @Test
    fun aStepThatChangedNothingOffersNoUndo() {
        val house = Household(TestBinderStore())
        val receipt = house.unit.performUndoable { step ->
            step.update(house.now(house.invoice).copy(isArchived = false))
        }.receipt
        assertFalse(receipt.canUndo)
    }

    @Test
    fun anActionInsideALargerStepIsUndoneWithIt() {
        val house = Household(TestBinderStore())
        val before = house.binder.database()
        val step = house.unit.performUndoable(now = noon("2026-11-03")) {
            house.unit.performUndoable { inner -> house.complete(inner, house.rca, "2027-11-10") }.receipt
        }
        assertSame(step.receipt, step.value, "The inner step's receipt is the whole step's")
        step.receipt.undo()
        assertEquals(emptyMap<RecordRef, Set<String>>(), differences(before, house.binder.database()))
    }

    // Every stored property is recorded

    @Test
    fun everyStoredPropertyOfEveryModelIsRecorded() {
        val ios = IosModel.all().associateBy { it.name }
        assertEquals(ios.keys, Tables.all.map { it.type }.toSet(), "Every model of the schema can be undone")
        for (table in Tables.all) {
            val model = ios.getValue(table.type)
            val kinds = table.properties.associate { property ->
                property.name to when (property.kind) {
                    StoredProperty.Kind.ATTRIBUTE, StoredProperty.Kind.FILE -> Kind.ATTRIBUTE
                    StoredProperty.Kind.TO_ONE -> Kind.TO_ONE
                    StoredProperty.Kind.TO_MANY -> Kind.TO_MANY
                    StoredProperty.Kind.LINKS -> Kind.LINKS
                }
            }
            assertEquals(model.properties, kinds, "${table.type} lists every stored property, named and kept as on iOS")
            assertEquals(
                model.properties.keys.toList(),
                table.properties.map { it.name },
                "${table.type}: in the iOS list's order",
            )
        }
        val schema = RoomSchema.committed().last()
        for (table in Tables.all) {
            val lists = setOf(StoredProperty.Kind.TO_MANY, StoredProperty.Kind.LINKS)
            val columns = table.properties.filter { it.kind !in lists }.map { it.name }.toSet()
            assertEquals(
                schema.tables.getValue(table.type).columns.keys - "pk",
                columns,
                "${table.type}: every column is recorded",
            )
            assertEquals(
                table.links.map { it.name }.toSet(),
                table.properties.filter { it.kind == StoredProperty.Kind.TO_ONE }.map { it.name }.toSet(),
            )
        }
    }
}
