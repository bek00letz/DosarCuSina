package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.TestBinder
import com.ar.dosarcusina.archive.TestBinders
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.binder.Removed
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.locks.CategoryLocks
import com.ar.dosarcusina.store.locks.SectionLocks
import com.ar.dosarcusina.store.schema.StoredMoment
import java.io.File
import java.nio.file.Files

/** Where the store's tests keep their files: build/store-tests, emptied at the start of each run. */
val storeScratch: File
    get() = File(System.getProperty("dosar.storeScratch") ?: "build/store-tests").also { it.mkdirs() }

/** A new folder of its own under [storeScratch]. */
fun scratchFolder(prefix: String): File = Files.createTempDirectory(storeScratch.toPath(), prefix).toFile()

/** A new store in memory, with a folder of its own for its files and its locks kept in memory. */
fun scratchStore(locks: SectionLocks = SectionLocks(file = null)): BinderStore =
    BinderStore.inMemory(scratchFolder("files-"), locks)

/** The importer's tests' binders on the Room store (META-INF/services): :archive's tests run on it here. */
class RoomTestBinders : TestBinders {
    override fun make(initial: Binder): TestBinder = RoomTestBinder(initial)
}

/**
 * A Room store holding [initial] (written into it as an import would), for one of the importer's
 * tests, with this phone's locks in a file of their own ([lockFolder]), read by the real rules.
 */
class RoomTestBinder(initial: Binder) : TestBinder {
    /** Where this phone's lock choices are kept. */
    val lockFolder: File = scratchFolder("locks-")
    val sectionLocks = SectionLocks(SectionLocks.fileForStore(File(lockFolder, BinderStore.DATABASE_NAME)))
    val store = scratchStore(sectionLocks)
    val locks = CategoryLocks(sectionLocks, Catalog.builtIn)
    val target = RoomArchiveTarget(store, locks)

    override var applied = 0
        private set

    override var failsNextWrite = false

    init {
        target.beforeLocks = {
            if (failsNextWrite) {
                failsNextWrite = false
                error("The store failed half way")
            }
        }
        if (initial != Binder()) target.apply(BinderChanges(initial, Removed(), initial.locks))
        // A binder that starts with a category opened here: this phone's choice, as made before.
        for ((key, locked) in initial.locks) if (!locked) sectionLocks.set(false, key, StoredMoment.now())
    }

    override val binder: Binder get() = target.snapshot()

    override fun snapshot(): Binder = target.snapshot()

    override fun apply(changes: BinderChanges) {
        target.apply(changes)
        applied += 1
    }
}
