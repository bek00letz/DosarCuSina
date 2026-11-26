package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.ServiceItem
import com.ar.dosarcusina.store.scratchStore
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.UUID

/**
 * A section's lock, with or without its category's record, a document's across every section it
 * belongs to, and whether anything of the binder is locked. The iOS app's
 * `LockedSectionsEverywhereTests`, below the screens. Every value is a placeholder.
 */
class BinderLocksTest {
    private val later = noon("2026-11-25")
    private val missing = "custom.0b6c6f43-0000-4000-8000-0000000000bb"

    private fun everyLockOff(locks: CategoryLocks, rows: List<CategoryTemplate>) {
        for (row in rows) locks.setLock(row, locked = false, lowering = confirmed(), now = later)
    }

    @Test
    fun aSectionWhoseCategoryHasntArrivedStaysLocked() {
        val locks = rules()
        val rows = builtIns()
        val cars = rows.single { it.key == VEHICLE }
        val section = Asset(name = "VW Golf 2018", templateKey = VEHICLE)
        assertFalse(locks.isSensitive(section, cars), "A car is open by default")

        // Its category of one's own is still on its way from another phone.
        val arriving = section.copy(templateKey = missing)
        assertTrue(locks.isSensitive(arriving, template = null), "No record yet: locked until it arrives")
        assertTrue(locks.isSensitive(arriving, among = rows.associateBy { it.key }))

        locks.choices.set(false, missing, later)
        assertFalse(locks.isSensitive(arriving, template = null), "This phone's own choice for the key still counts")
    }

    @Test
    fun theBinderCountsASectionWhoseCategoryHasntArrived() {
        val choices = SectionLocks(lockFile())
        val locks = rules(choices)
        val store = scratchStore(choices)
        val rows = builtIns()
        runBlocking {
            for (row in rows) store.database.templates().insert(row)
            store.database.assets().insert(Asset(name = "Caiet", templateKey = VEHICLE))
        }
        everyLockOff(locks, rows)
        val open = runBlocking { BinderLocks.read(store.database, locks) }
        assertFalse(open.anySectionLocked, "Every lock off: nothing of the binder is locked")

        runBlocking { store.database.assets().insert(Asset(name = "Caiet", templateKey = missing)) }
        val waiting = runBlocking { BinderLocks.read(store.database, locks) }
        assertTrue(waiting.anySectionLocked, "Locked until its category arrives, as on its own page")
        assertEquals(setOf(missing), waiting.lockedKeys)
        // De verificat: an item read as that category's shows as protected.
        assertEquals(setOf(missing), BinderLocks.of(rows, listOf(missing), locks).lockedKeys)

        choices.set(false, missing, later)
        assertFalse(runBlocking { BinderLocks.read(store.database, locks) }.anySectionLocked)
        store.close()
    }

    @Test
    fun twoCopiesOfOneCategoryAreLockedIfEitherIs() {
        val locks = rules()
        val cars = builtIns().single { it.key == VEHICLE }
        val lockedCopy = locks.setLock(cars, locked = true, lowering = null, now = later)
        locks.choices.set(false, VEHICLE, noon("2026-11-24"))
        val copies = listOf(cars, lockedCopy)
        assertEquals(mapOf(VEHICLE to true), locks.locked(copies), "The copy locked everywhere since wins")
        assertEquals(setOf(VEHICLE), BinderLocks.of(copies, emptyList(), locks).lockedKeys)
    }

    @Test
    fun aBinderThatCantBeReadHasSomethingLocked() {
        val locks = rules()
        val store = scratchStore()
        store.close()
        val unread = runBlocking { BinderLocks.read(store.database, locks) }
        assertTrue(unread.anySectionLocked)
        assertEquals(BinderLocks.unreadable, unread)
    }

    @Test
    fun aDeadlineIsLockedByItsSectionAndOneOfTheHouseholdByNothing() {
        val locks = rules()
        val rows = builtIns().associateBy { it.key }
        val passport = Asset(pk = 1, name = "Pașaport", templateKey = DOCUMENTS)
        val renewal = Obligation(pk = 1, title = "Reînnoire", asset = passport.pk)
        val chore = Obligation(pk = 2, title = "Gunoi")
        val sections = mapOf(passport.pk to passport)
        assertTrue(locks.isSensitive(renewal, sections, rows))
        assertFalse(locks.isSensitive(chore, sections, rows), "A deadline of the whole household has no lock")
    }

    @Test
    fun aDocumentOpensBehindEverySectionItBelongsTo() {
        val locks = rules()
        val templates = builtIns().associateBy { it.key }
        fun section(pk: Long, key: String) =
            Asset(pk = pk, id = UUID.fromString("00000000-0000-4000-8000-0000000000a$pk"), templateKey = key)
        val car = section(1, VEHICLE)
        val flat = section(2, HOME)
        val person = section(3, DOCUMENTS)
        val itp = Obligation(pk = 1, title = "ITP", asset = car.pk)
        val chore = Obligation(pk = 2, title = "Gunoi")
        val repair = HistoryEntry(pk = 1, title = "Reparație", asset = car.pk)
        val part = ServiceItem(pk = 1, name = "Filtru", entry = repair.pk)
        val reading = MeasurementLog(pk = 1, asset = person.pk)
        val sections = DocumentSections(
            assets = listOf(car, flat, person),
            obligations = listOf(itp, chore),
            entries = listOf(repair),
            items = listOf(part),
            readings = listOf(reading),
        )
        // Cars and homes open here, a person's documents locked as the catalog says.
        fun lockOf(paper: Attachment) = locks.lock(paper, sections, templates)

        // Filed on the deadline only: its section's lock.
        assertEquals(DocumentLock.Section(car.id), lockOf(Attachment(obligation = itp.pk)))
        // A record's paper in Istoric, with no section of its own; a part's; a reading's.
        assertEquals(DocumentLock.Section(car.id), lockOf(Attachment(historyEntry = repair.pk)))
        assertEquals(DocumentLock.Section(car.id), lockOf(Attachment(serviceItem = part.pk)))
        assertEquals(DocumentLock.Section(person.id), lockOf(Attachment(measurement = reading.pk)))

        // Two sections, one locked: the locked one decides; none locked: its own first.
        val both = Attachment(asset = flat.pk, obligation = itp.pk, measurement = reading.pk)
        assertEquals(listOf(flat.id, car.id, person.id), sections.of(both).map { it.id })
        assertEquals(DocumentLock.Section(person.id), lockOf(both))
        assertEquals(DocumentLock.Section(flat.id), lockOf(Attachment(asset = flat.pk, obligation = itp.pk)))
        val twice = Attachment(asset = car.pk, obligation = itp.pk)
        assertEquals(listOf(car.id), sections.of(twice).map { it.id }, "Each once")

        // The whole household's paper is open; one that names nothing fails closed.
        assertEquals(DocumentLock.Open, lockOf(Attachment(obligation = chore.pk)))
        assertEquals(DocumentLock.UnknownSection, lockOf(Attachment()))
        assertEquals(DocumentLock.UnknownSection, lockOf(Attachment(asset = 99)), "A section that can't be found")

        // Away from its page (search), the same lock, read from the whole binder's answer.
        val binder = BinderLocks.of(templates.values.toList(), listOf(VEHICLE, HOME, DOCUMENTS), locks)
        assertEquals(lockOf(both), binder.lock(both, sections))
        val ownOpenAnotherLocked = Attachment(asset = car.pk, measurement = reading.pk)
        assertTrue(binder.isLocked(ownOpenAnotherLocked, sections), "Its own section open, another locked")
        val everyOneOpen = Attachment(asset = flat.pk, obligation = itp.pk)
        assertFalse(binder.isLocked(everyOneOpen, sections), "Every section it belongs to open")
        assertFalse(binder.isLocked(Attachment(obligation = chore.pk), sections), "The whole household's paper")
        assertTrue(binder.isLocked(Attachment(), sections), "Naming nothing, locked while anything is")
    }
}
