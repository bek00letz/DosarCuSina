package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.StoredMoment
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * One rule for when a record last changed, kept by the unit of work as it saves, for every kind of
 * record, and whose change a step is decides the times it gives (the iOS app's `ChangeTimesTests`
 * and `ChangeOriginTests`).
 */
class ChangeTimesTest {
    private val long = noon("2025-06-01")
    private val today = noon("2026-11-10")

    @Test
    fun aChangeGivesANewTime() {
        val records = Records.make(long)
        records.unit.perform(now = today) { step ->
            step.update(records.storedCar.copy(notes = "Cauciucuri de iarnă."))
            step.update(records.storedVisit.copy(note = "Cu filtrul de aer."))
            step.update(records.storedItem.copy(notes = "Original."))
            step.update(records.storedReading.copy(notes = "De pe bord."))
            step.update(records.storedDocument.copy(title = "Factură revizie"))
        }
        assertEquals(today, records.storedCar.updatedAt)
        assertEquals(today, records.storedVisit.updatedAt)
        assertEquals(today, records.storedItem.updatedAt)
        assertEquals(today, records.storedReading.updatedAt)
        assertEquals(today, records.storedDocument.updatedAt)
    }

    @Test
    fun beingLinkedToIsNoChange() {
        val records = Records.make(long)
        val second = records.unit.perform(now = today) { step ->
            step.insert(Attachment(
                fileName = "frane.pdf",
                contentType = "com.adobe.pdf",
                historyEntry = records.visit.pk,
            ))
            step.insert(HistoryEntry(kindRaw = "repair", title = "Frâne", asset = records.car.pk))
        }
        assertEquals(long, records.storedCar.updatedAt)
        assertEquals(
            long,
            records.storedVisit.updatedAt,
            "A visit that gets a document keeps its time: the document keeps the link",
        )
        assertEquals(today, records.binder.stored(second).updatedAt, "What is made new has the time it was made")
    }

    @Test
    fun aPageChangesItsDocument() {
        val records = Records.make(long)
        records.unit.perform(now = today) { step ->
            step.update(records.storedPage.copy(imageData = step.keep(picture(9))))
        }
        assertEquals(today, records.storedDocument.updatedAt)

        backToLong(records)
        val back = records.unit.perform(now = today) { step ->
            step.insert(AttachmentPage(index = 1, imageData = step.keep(picture(4)), attachment = records.document.pk))
        }
        assertEquals(today, records.storedDocument.updatedAt, "A page added")

        backToLong(records)
        records.unit.perform(now = today) { step -> step.delete(records.binder.stored(back)) }
        assertEquals(today, records.storedDocument.updatedAt, "A page taken away")
    }

    private fun backToLong(records: Records) {
        records.unit.performPrivate { step -> step.update(records.storedDocument.copy(updatedAt = long)) }
    }

    @Test
    fun aStepsOwnTimeWins() {
        val records = Records.make(long)
        val own = noon("2026-11-02")
        records.unit.perform(now = own) { step -> step.update(records.storedVisit.copy(note = "Corectat.")) }
        assertEquals(own, records.storedVisit.updatedAt)
    }

    @Test
    fun aHandWrittenTimeIsReplaced() {
        val records = Records.make(long)
        records.unit.perform(now = noon("2026-11-02")) { step ->
            step.update(records.storedVisit.copy(note = "Corectat.", updatedAt = noon("2020-01-01")))
        }
        assertEquals(noon("2026-11-02"), records.storedVisit.updatedAt)
    }

    @Test
    fun theSameValueIsNoChange() {
        val records = Records.make(long)
        records.unit.perform(now = today) { step ->
            step.update(records.storedVisit.copy(note = records.storedVisit.note))
            step.update(records.storedReading.copy(value = records.storedReading.value))
        }
        assertEquals(long, records.storedVisit.updatedAt)
        assertEquals(long, records.storedReading.updatedAt)
    }

    @Test
    fun aUnitOfWorkKeepsChangeTimes() {
        val records = Records.make(long)
        records.unit.perform(now = today) { step ->
            step.update(records.storedItem.copy(notes = "Schimbat."))
            step.update(records.storedReading.copy(value = 100_500.0))
        }
        assertEquals(today, records.storedItem.updatedAt)
        assertEquals(today, records.storedReading.updatedAt)
        assertEquals(long, records.storedVisit.updatedAt)
    }

    @Test
    fun undoPutsChangeTimesBack() {
        val records = Records.make(long)
        val receipt = records.unit.performUndoable(now = today) { step ->
            step.update(records.storedVisit.copy(title = "Revizie anuală"))
            step.update(records.storedPage.copy(imageData = step.keep(picture(8))))
        }.receipt
        assertEquals(today, records.storedVisit.updatedAt)
        assertEquals(today, records.storedDocument.updatedAt)
        receipt.undo()
        assertEquals(long, records.storedVisit.updatedAt)
        assertEquals(long, records.storedDocument.updatedAt)
        assertEquals("Revizie", records.storedVisit.title)
    }

    @Test
    fun unknownIsOlderThanAnyChange() {
        assertEquals(java.time.Instant.parse("0001-01-01T00:00:00Z"), ChangeTime.UNKNOWN)
        assertEquals(ChangeTime.UNKNOWN, StoredMoment.kept(ChangeTime.UNKNOWN), "The store keeps it as it is")
        assertTrue(HistoryEntry().updatedAt > ChangeTime.UNKNOWN, "A new record has the time it was made")
    }

    // Whose change it is

    @Test
    fun aStepsClockIsItsTimeOpenedOrJoined() {
        val records = Records.make(long)
        val later = noon("2026-11-20")
        // A unit opened without a clock takes the first a step inside it gives.
        records.unit.perform { step ->
            step.update(records.storedItem.copy(notes = "Schimbat."))
            records.unit.perform(now = later) { }
        }
        assertEquals(later, records.storedItem.updatedAt)

        records.binder.now = noon("2026-11-21")
        records.unit.perform { step -> step.update(records.storedVisit.copy(note = "Fără ceas.")) }
        assertEquals(noon("2026-11-21"), records.storedVisit.updatedAt, "Without one, the moment it saves")
    }

    @Test
    fun anAppMadeStepDoesntStamp() {
        val records = Records.make(long)
        val made = records.unit.perform(ChangeOrigin.APP, now = today) { step ->
            step.update(records.storedVisit.copy(note = "Scris altfel."))
            step.update(records.storedPage.copy(imageData = step.keep(picture(5))))
            step.insert(HistoryEntry(kindRaw = "note", title = "Notă", asset = records.car.pk))
        }
        assertEquals(long, records.storedVisit.updatedAt)
        assertEquals(
            long,
            records.storedDocument.updatedAt,
            "A page the app changed is no change of the document either",
        )
        assertEquals(today, records.binder.stored(made).updatedAt)
    }

    @Test
    fun anAppMadeStepInsideThePersonsIsPartOfIt() {
        val records = Records.make(long)
        records.unit.perform(now = today) {
            records.unit.perform(ChangeOrigin.APP) { step ->
                step.update(records.storedVisit.copy(note = "Din editare."))
            }
        }
        assertEquals(today, records.storedVisit.updatedAt)
    }

    @Test
    fun aBackupsWriterKeepsTheTimesItCarries() {
        val records = Records.make(long)
        records.unit.performPrivate { step ->
            step.update(records.storedVisit.copy(note = "Din copie.", updatedAt = noon("2025-07-01")))
            step.insert(HistoryEntry(title = "Din copie", asset = records.car.pk, updatedAt = noon("2025-08-01")))
        }
        assertEquals(noon("2025-07-01"), records.storedVisit.updatedAt)
        val made = records.binder.snapshot().all(Tables.history).single { it.title == "Din copie" }
        assertEquals(noon("2025-08-01"), made.updatedAt)
    }

    // Built-in categories

    private fun phone(): TestBinderStore = TestBinderStore().also { LaunchData(it.unit).prepare(today) }

    @Test
    fun installedBuiltInsHaveNoChange() {
        val phone = phone()
        val templates = phone.snapshot().all(Tables.templates)
        assertEquals(Catalog.builtIn.all.map { it.key }.toSet(), templates.map { it.key }.toSet())
        for (template in templates) assertEquals(ChangeTime.UNKNOWN, template.updatedAt, template.key)
    }

    @Test
    fun aCatalogUpgradeIsNoChange() {
        val phone = phone()
        val documents = phone.snapshot().all(Tables.templates).first { it.key == "documents" }
        val version = documents.builtInVersion
        // Installed by an earlier catalog, its order chosen long ago.
        phone.unit.performPrivate { step ->
            step.update(documents.copy(
                builtInVersion = version - 1,
                summary = "Definiția de altădată",
                updatedAt = long,
            ))
        }
        assertTrue(LaunchData(phone.unit).installBuiltIns(today))
        val upgraded = phone.stored(documents)
        assertEquals(version, upgraded.builtInVersion, "Upgraded")
        assertEquals(long, upgraded.updatedAt, "Its change time is the person's last choice, not the update")
    }

    @Test
    fun onlyThePersonsChoicesCount() {
        val phone = phone()
        val pets = phone.snapshot().all(Tables.templates).first { it.key == "pet" }
        phone.unit.perform(now = today) { step -> step.update(pets.copy(summary = "Altă descriere")) }
        assertEquals(
            ChangeTime.UNKNOWN,
            phone.stored(pets).updatedAt,
            "What the catalog defines is no choice of the person's",
        )
        phone.unit.perform(now = today) { step -> step.update(phone.stored(pets).copy(isOnHome = !pets.isOnHome)) }
        assertEquals(today, phone.stored(pets).updatedAt)
    }

    @Test
    fun aCategoryOfOnesOwnIsTheirs() {
        val phone = TestBinderStore()
        val boats = phone.unit.perform(now = today) { step ->
            step.insert(com.ar.dosarcusina.store.schema.CategoryTemplate(key = "custom.boats", name = "Bărci"))
        }
        assertEquals(today, phone.stored(boats).updatedAt)
        phone.unit.perform(now = noon("2026-11-12")) { step ->
            step.update(phone.stored(boats).copy(summary = "Pe lac"))
        }
        assertEquals(noon("2026-11-12"), phone.stored(boats).updatedAt)
    }
}
