package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.store.BinderStore
import com.ar.dosarcusina.store.scratchFolder
import com.ar.dosarcusina.store.schema.CategoryTemplate
import kotlinx.coroutines.runBlocking
import java.io.File
import java.time.Instant

/** The person's answer, as the tests give it: confirmed, unless told to refuse. Counts each time it asks. */
class TestConfirmation(var confirms: Boolean = true) : LockLowering.Confirmation() {
    var asked = 0
        private set

    override suspend fun confirmed(reason: String): Boolean {
        asked += 1
        return confirms
    }
}

/** A lowering the person just confirmed. */
fun confirmed(): LockLowering = runBlocking { requireNotNull(TestConfirmation().confirmLowering("Test")) }

/** A noon of the day [day] (`2026-11-20`), in UTC. */
fun noon(day: String): Instant = Instant.parse("${day}T12:00:00Z")

/** Where a store in a new folder keeps its locks. */
fun lockFile(): File = SectionLocks.fileForStore(File(scratchFolder("locks-"), BinderStore.DATABASE_NAME))

/** The rules over [choices], with the real catalog. */
fun rules(choices: SectionLocks = SectionLocks(file = null)): CategoryLocks = CategoryLocks(choices, Catalog.builtIn)

/** Every built-in category as the catalog installs it. */
fun builtIns(): List<CategoryTemplate> =
    Catalog.builtIn.all.map { CategoryTemplate(key = it.key, name = it.name, isBuiltIn = true) }

/** A category of one's own, as a placeholder. */
fun ownCategory(key: String = "custom.0b6c6f43-0000-4000-8000-00000000c0de"): CategoryTemplate =
    CategoryTemplate(key = key, name = "Caiet", isBuiltIn = false)

const val VEHICLE = "vehicle"
const val HOME = "home"
const val DOCUMENTS = "documents"
const val HEALTH = "health"
