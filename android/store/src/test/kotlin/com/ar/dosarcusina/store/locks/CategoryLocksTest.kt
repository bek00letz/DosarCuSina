package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.schema.CategoryTemplate
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * A category's lock: the one answer, locking that travels and opening that stays, turning a lock off
 * only with the person's confirmation, and the locks sent up once. The iOS app's
 * `SectionLocksTests`, `LocksTravelTests` and `LocksHoldTests`, below the screens. Every value is a
 * placeholder.
 */
class CategoryLocksTest {
    private val earlier = noon("2026-11-20")
    private val later = noon("2026-11-25")

    private fun CategoryLocks.template(key: String, rows: List<CategoryTemplate>) = rows.single { it.key == key }

    @Test
    fun theLockIsNotInTheStore() {
        val columns = CategoryTemplate::class.java.declaredFields.map { it.name }
        assertFalse("isSensitive" in columns, "Sync never carries whether a category is open here")
        assertTrue("lockedEverywhereAt" in columns, "Only when it was last locked anywhere")
    }

    @Test
    fun aFirstRunLocksActeAndSanatateAsTheCatalogSays() {
        val locks = rules()
        val locked = builtIns().filter(locks::isSensitive).map { it.key }.toSet()
        assertEquals(Catalog.builtIn.all.filter { it.isSensitiveByDefault }.map { it.key }.toSet(), locked)
        assertEquals(setOf(DOCUMENTS, HEALTH), locked)
        assertFalse(locks.isSensitive(ownCategory()), "One of one's own is made with its lock")
    }

    @Test
    fun aCategoryWhoseRecordIsntHereIsLockedUnlessThisPhoneOrTheCatalogSaysOtherwise() {
        val locks = rules()
        val key = "custom.0b6c6f43-0000-4000-8000-0000000000aa"
        assertTrue(locks.isSensitive(key, template = null), "No record yet: locked until it arrives")
        assertFalse(locks.isSensitive(VEHICLE, template = null), "A built-in follows the catalog")
        assertTrue(locks.isSensitive(DOCUMENTS, template = null))
        assertTrue(locks.isSensitive("custom.unknown", among = emptyMap()))

        locks.choices.set(false, key, later)
        assertFalse(locks.isSensitive(key, template = null), "This phone's own choice for the key still counts")
    }

    @Test
    fun lockingACategoryLocksItEverywhereAndOpeningOpensItHereOnly() {
        val locks = rules(SectionLocks(lockFile()))
        val made = locks.madeWith(ownCategory(), locked = false, now = earlier)
        assertNull(made.lockedEverywhereAt, "Made open: nothing to send")

        val lockedRow = locks.setLock(made, locked = true, lowering = null, now = later)
        assertEquals(later, lockedRow.lockedEverywhereAt, "Locking it is written on its record, which sync carries")
        assertTrue(locks.isSensitive(lockedRow))

        val opened = locks.setLock(lockedRow, locked = false, lowering = confirmed(), now = noon("2026-11-26"))
        assertFalse(locks.isSensitive(opened), "Open on this phone")
        assertSame(lockedRow, opened, "Opening changes no row: no phone opens a section on another")

        val again = locks.setLock(opened, locked = true, lowering = null, now = noon("2026-11-27"))
        assertEquals(noon("2026-11-27"), again.lockedEverywhereAt, "Locked again: the newest lock travels")
        assertSame(again, locks.lock(again, noon("2026-11-28")), "A lock already on stays on this phone")
    }

    @Test
    fun twoPhonesLockEachForItself() {
        val here = rules(SectionLocks(lockFile()))
        val there = rules(SectionLocks(lockFile()))
        val cars = builtIns().single { it.key == VEHICLE }
        here.setLock(cars, locked = true, lowering = null, now = later)
        assertFalse(there.isSensitive(cars), "Until the record with its lock arrives there")
        val documents = builtIns().single { it.key == DOCUMENTS }
        there.setLock(documents, locked = false, lowering = confirmed(), now = later)
        assertTrue(here.isSensitive(documents))
    }

    @Test
    fun aLockFromAnotherPhoneArrivesWithItsRecord() {
        val here = rules(SectionLocks(lockFile()))
        val there = rules(SectionLocks(lockFile()))
        val cars = builtIns().single { it.key == VEHICLE }
        val locked = there.setLock(cars, locked = true, lowering = null, now = earlier)
        assertTrue(here.isSensitive(locked), "The record sync brings locks it here too")
        val opened = here.setLock(locked, locked = false, lowering = confirmed(), now = later)
        assertFalse(here.isSensitive(opened))
        assertTrue(there.isSensitive(opened), "Opened here, it stays locked there")
        // A change from the other phone to anything else of the record changes nothing here.
        assertFalse(here.isSensitive(opened.copy(homeOrder = 12, isOnHome = false)))
    }

    @Test
    fun aCategoryOfOnesOwnMadeLockedIsLockedEverywhere() {
        val choices = SectionLocks(lockFile())
        val locks = rules(choices)
        val made = locks.madeWith(ownCategory(), locked = true, now = later)
        assertEquals(later, made.lockedEverywhereAt)
        assertTrue(locks.isSensitive(made))
        assertTrue(rules(SectionLocks(choices.file)).isSensitive(made), "Kept before the save, beside the store")

        // A built-in's lock is the catalog's, the same everywhere already.
        val documents = locks.madeWith(builtIns().single { it.key == DOCUMENTS }, locked = true, now = later)
        assertNull(documents.lockedEverywhereAt)
    }

    @Test
    fun aCategoryMadeAgainKeepsTheLockThisPhoneChose() {
        val locks = rules(SectionLocks(lockFile()))
        val cars = builtIns().single { it.key == VEHICLE }
        locks.setLock(cars, locked = true, lowering = null, now = later)
        // Installed again after „Începe din nou”: the catalog's lock doesn't open it.
        val installed = locks.madeWith(cars.copy(lockedEverywhereAt = null), locked = false, now = noon("2026-11-26"))
        assertTrue(locks.isSensitive(installed))
    }

    @Test
    fun aSectionLockGoesOffOnlyWithTheConfirmationAndOnWithout() {
        val locks = rules(SectionLocks(lockFile()))
        val acte = builtIns().single { it.key == DOCUMENTS }
        assertThrows<LockLowering.Needed> { locks.setLock(acte, locked = false, lowering = null, now = later) }
        assertTrue(locks.isSensitive(acte), "Every way of turning it off asks")
        assertNull(locks.choices.lockedHere(DOCUMENTS), "Nothing was written")

        val opened = locks.setLock(acte, locked = false, lowering = confirmed(), now = later)
        assertFalse(locks.isSensitive(opened))
        val lockedAgain = locks.setLock(opened, locked = true, lowering = null, now = noon("2026-11-26"))
        assertTrue(locks.isSensitive(lockedAgain), "Turning one on needs nothing")
        // Opening one already open asks nothing.
        locks.setLock(builtIns().single { it.key == HOME }, locked = false, lowering = null, now = later)
    }

    @Test
    fun turningALockOffAsksEveryTime() {
        val confirmation = TestConfirmation()
        runBlocking {
            assertNotNull(confirmation.confirmLowering("Test"))
            assertNotNull(confirmation.confirmLowering("Test"))
            assertEquals(2, confirmation.asked, "Asked each time")
            confirmation.confirms = false
            assertNull(confirmation.confirmLowering("Test"), "Cancelled or failed: no lowering")
        }
        assertEquals(3, confirmation.asked)
    }

    @Test
    fun lockingIsToldToWhatFollowsIt() {
        val locks = rules(SectionLocks(lockFile()))
        val cars = builtIns().single { it.key == VEHICLE }
        val before = locks.choices.generation.value
        val lockedRow = locks.setLock(cars, locked = true, lowering = null, now = later)
        assertEquals(before + 1, locks.choices.generation.value)
        locks.setLock(lockedRow, locked = false, lowering = confirmed(), now = noon("2026-11-26"))
        assertEquals(before + 2, locks.choices.generation.value)
    }

    @Test
    fun aStoreWhoseLocksCantBeReadOpensWithEveryCategoryLocked() {
        val file = lockFile()
        file.writeText("{")
        val locks = rules(SectionLocks(file))
        val notebook = ownCategory()
        val rows = builtIns() + notebook
        assertTrue(locks.choices.needsChoosingAgain)
        for (row in rows) assertTrue(locks.isSensitive(row), "Every category stays locked, built-ins too: ${row.key}")
        val cars = locks.template(VEHICLE, rows)
        assertThrows<LockLowering.Needed> { locks.setLock(cars, locked = false, lowering = null, now = later) }
        assertThrows<LockLowering.Needed> { locks.keepLocksAsTheyAre(rows, lowering = null, now = later) }
        assertTrue(locks.choices.needsChoosingAgain)

        locks.keepLocksAsTheyAre(rows, lowering = confirmed(), now = later)
        assertFalse(locks.choices.needsChoosingAgain)
        for (row in rows) assertTrue(locks.isSensitive(row), "Kept on, as the list showed it: ${row.key}")
        // Then each one opens again with the confirmation.
        val opened = locks.setLock(cars, locked = false, lowering = confirmed(), now = noon("2026-11-26"))
        assertFalse(locks.isSensitive(opened))
        val arrives = ownCategory("custom.0b6c6f43-0000-4000-8000-0000000000bb")
        assertFalse(locks.isSensitive(arrives), "Once chosen again, a new one from another phone starts open")
    }

    @Test
    fun eachPhoneSendsUpTheLocksItHadOnce() {
        val choices = SectionLocks(lockFile())
        val locked = ownCategory()
        val open = ownCategory("custom.0b6c6f43-0000-4000-8000-0000000000bb")
        val withoutTime = ownCategory("custom.0b6c6f43-0000-4000-8000-0000000000cc")
        // Locks chosen before locking travelled: on this phone only, one with when, one without.
        choices.set(true, locked.key, earlier)
        choices.adopt(mapOf(withoutTime.key to true))

        val sent = LockPublishing.toSend(listOf(locked, open, withoutTime), choices, later)
        assertEquals(listOf(locked.key, withoutTime.key), sent.map { it.key }, "An open category sends nothing")
        assertEquals(earlier, sent[0].lockedEverywhereAt, "When this phone locked it")
        assertEquals(later, sent[1].lockedEverywhereAt, "Now, when that isn't known")
        assertEquals(emptyList<CategoryTemplate>(), LockPublishing.toSend(sent + open, choices, later), "Once")
    }
}
