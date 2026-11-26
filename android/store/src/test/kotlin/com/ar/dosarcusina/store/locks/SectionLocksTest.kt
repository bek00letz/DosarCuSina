package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.store.BinderStore
import com.ar.dosarcusina.store.DatabaseBuilders
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File
import java.io.IOException

/**
 * This phone's lock choices, beside the store, each with when it was made: the rule, the files, and
 * locks that stay on when they can't be read. The iOS app's `LocksTravelTests` and `LocksHoldTests`,
 * the parts below the screens. Every value is a placeholder.
 */
class SectionLocksTest {
    private val earlier = noon("2026-11-20")
    private val later = noon("2026-11-25")
    private val notebook = "custom.0b6c6f43-0000-4000-8000-00000000c0de"
    private val fromAnotherPhone = "custom.0b6c6f43-0000-4000-8000-0000000000aa"
    private val defaults = rules().lockedByDefault

    private fun locked(locks: SectionLocks, key: String): Boolean = locks.isLocked(key, byDefault = key in defaults)

    // The rule

    @Test
    fun aLockMadeElsewhereLocksUnlessThisPhoneOpenedItSince() {
        val locks = SectionLocks(file = null)
        val key = "custom.exemplu"
        assertFalse(locks.isLocked(key, byDefault = false), "Never locked anywhere, never chosen here")
        assertTrue(locks.isLocked(key, false, earlier), "Locked on another phone: locked here, a new one included")

        locks.set(false, key, later)
        assertFalse(locks.isLocked(key, false, earlier), "Opened here since: open here")
        assertTrue(locks.isLocked(key, false, noon("2026-11-26")), "Locked again elsewhere since: locked here again")

        locks.set(true, key, later)
        assertTrue(locks.isLocked(key, false, null), "Locked here stays locked here")
    }

    @Test
    fun whenEachChoiceWasMadeIsKeptBesideTheChoices() {
        val file = lockFile()
        SectionLocks(file).set(false, "custom.exemplu", later)

        val reopened = SectionLocks(file)
        assertFalse(reopened.isLocked("custom.exemplu", false, earlier), "Its time came back with it")
        assertEquals(later, reopened.lockedHere("custom.exemplu")?.at)
        assertTrue(
            SectionLocks.timesFile(file).name.startsWith(file.name),
            "Named after the choices, so „Începe din nou” leaves both",
        )

        assertTrue(SectionLocks.timesFile(file).delete())
        assertTrue(
            SectionLocks(file).isLocked("custom.exemplu", false, earlier),
            "A choice whose time is lost is older than any lock made elsewhere: locked",
        )
    }

    @Test
    fun theLocksLiveBesideTheDatabaseOneForEachStore() {
        val folder = lockFile().parentFile
        val database = File(folder, BinderStore.DATABASE_NAME)
        assertEquals(File(folder, "binder.sqlite.section-locks.json"), SectionLocks.fileForStore(database))
        assertSame(SectionLocks.of(database), SectionLocks.of(File(folder, "./" + BinderStore.DATABASE_NAME)))
        BinderStore.open(folder, DatabaseBuilders.JVM).use { store ->
            assertSame(SectionLocks.of(database), store.locks, "Everything that opens the store shares them")
            store.locks.set(true, VEHICLE, later)
        }
        assertTrue(SectionLocks.fileForStore(database).isFile)
        assertEquals(mapOf(VEHICLE to true), SectionLocks(SectionLocks.fileForStore(database)).all)
    }

    // Locks that can't be read stay on

    @Test
    fun aLockFileThatCantBeReadKeepsEveryLockOnAndIsNeverWrittenOver() {
        val file = lockFile()
        val unreadable = "{\"vehicle\": tr".toByteArray()
        file.writeBytes(unreadable)

        val locks = SectionLocks(file)
        assertTrue(locks.needsChoosingAgain)
        for (key in listOf(notebook, DOCUMENTS, VEHICLE, HOME, fromAnotherPhone)) {
            assertTrue(locked(locks, key), "Every category is locked until the locks are chosen again: $key")
        }

        // A change sets the unread file aside and starts a new one that remembers the wait.
        locks.set(true, VEHICLE, later)
        locks.set(false, HOME, later)
        assertTrue(locked(locks, HOME), "Nothing opens while the locks wait")
        val setAside = file.parentFile.list().orEmpty().filter { ".unread-" in it }
        assertEquals(1, setAside.size)
        assertArrayEquals(unreadable, File(file.parentFile, setAside.single()).readBytes(), "Kept as it was")
        val reopened = SectionLocks(file)
        assertTrue(reopened.needsChoosingAgain, "Still waiting after a relaunch")
        for (key in listOf(notebook, VEHICLE, HOME)) assertTrue(locked(reopened, key))
        assertNull(reopened.all[SectionLocks.WAIT_KEY], "The wait isn't a category")

        // Kept: every lock stays on, and the wait ends.
        reopened.chooseAgain(mapOf(notebook to true, VEHICLE to true, DOCUMENTS to true, HOME to true), later)
        val chosen = SectionLocks(file)
        assertFalse(chosen.needsChoosingAgain)
        for (key in listOf(notebook, VEHICLE, DOCUMENTS, HOME)) assertTrue(locked(chosen, key))
        assertFalse(locked(chosen, fromAnotherPhone), "A category from another phone starts open again")
    }

    @Test
    fun aFileOfTheWrongShapeCantBeRead() {
        for (text in listOf("[true]", "{\"vehicle\": \"false\"}", "{\"vehicle\": 0}", "")) {
            val file = lockFile()
            file.writeText(text)
            assertTrue(SectionLocks(file).needsChoosingAgain, "„$text” is no file of choices: every lock stays on")
        }
    }

    @Test
    fun aLockFileThatReadsLaterIsReadAgain() {
        val file = lockFile()
        file.writeText("not yet")
        val locks = SectionLocks(file)
        assertTrue(locks.needsChoosingAgain)

        file.writeText("{\"vehicle\":true,\"documents\":false}")
        val before = locks.generation.value
        locks.readAgainIfUnread()
        assertFalse(locks.needsChoosingAgain)
        assertTrue(locked(locks, VEHICLE))
        assertFalse(locked(locks, DOCUMENTS))
        assertFalse(locked(locks, notebook))
        assertEquals(before + 1, locks.generation.value, "Told to what follows the locks")
    }

    @Test
    fun aChoiceThatCantBeKeptSaysSoAndChangesNothing() {
        val file = lockFile()
        val locks = SectionLocks(file)
        assertTrue(file.parentFile.setWritable(false))
        try {
            assertThrows<IOException> { locks.set(true, VEHICLE, later) }
        } finally {
            file.parentFile.setWritable(true)
        }
        assertFalse(locked(locks, VEHICLE), "Nothing shows as locked that isn't kept")
        assertEquals(0L, locks.generation.value)
    }

    @Test
    fun locksAnOlderBuildMovedAsideKeepEveryCategoryLocked() {
        val file = lockFile()
        File(file.parentFile, "unreadable-20261101T120000-${file.name}")
            .writeText("{\"vehicle\":true,\"home\":false,\"$notebook\":true}")

        val locks = SectionLocks(file)
        assertTrue(locks.needsChoosingAgain)
        for (key in listOf(VEHICLE, HOME, notebook, DOCUMENTS, fromAnotherPhone)) {
            assertTrue(locked(locks, key), "Every category is locked until chosen again: $key")
        }
    }

    @Test
    fun locksSetAsideWithNoneWrittenAfterThemKeepEveryCategoryLocked() {
        val file = lockFile()
        File(file.parentFile, "${file.name}.unread-0b6c6f43-0000-4000-8000-000000000001").writeText("{")

        val locks = SectionLocks(file)
        assertTrue(locks.needsChoosingAgain)
        assertTrue(locked(locks, VEHICLE))
    }

    @Test
    fun aLockFolderThatCantBeListedKeepsEveryCategoryLocked() {
        val file = lockFile()
        val folder = file.parentFile
        assertTrue(folder.setReadable(false, false), "The folder can be made unreadable")
        try {
            // Where the folder can still be listed (a test run with every right), there is nothing to check.
            assumeTrue(folder.list() == null)
            val locks = SectionLocks(file)
            assertTrue(locks.needsChoosingAgain, "A folder that can't be listed can't say it holds no lock set aside")
            assertTrue(locked(locks, VEHICLE))
        } finally {
            folder.setReadable(true, false)
        }
    }

    @Test
    fun aLockFolderNotMadeYetHoldsNothingSetAside() {
        val file = File(File(lockFile().parentFile, "not-made-yet"), BinderStore.DATABASE_NAME)
        val locks = SectionLocks(SectionLocks.fileForStore(file))
        assertFalse(locks.needsChoosingAgain)
        assertFalse(locked(locks, VEHICLE))
    }

    @Test
    fun aStoreInMemoryHasLocksOfItsOwn() {
        val here = SectionLocks(file = null)
        val there = SectionLocks(file = null)
        here.set(true, VEHICLE, later)
        assertTrue(locked(here, VEHICLE))
        assertFalse(locked(there, VEHICLE), "Each phone locks for itself")
        assertFalse(here.needsChoosingAgain)
    }

    @Test
    fun adoptingKeepsWhatThisPhoneChoseAndGivesNoTime() {
        val locks = SectionLocks(lockFile())
        locks.set(false, VEHICLE, later)
        locks.adopt(mapOf(VEHICLE to true, HOME to true, SectionLocks.WAIT_KEY to true))
        assertEquals(mapOf(VEHICLE to false, HOME to true), locks.all)
        assertEquals(SectionLocks.Choice(true, null), locks.lockedHere(HOME), "Older than any lock made elsewhere")
        assertFalse(locks.needsChoosingAgain)
    }
}
