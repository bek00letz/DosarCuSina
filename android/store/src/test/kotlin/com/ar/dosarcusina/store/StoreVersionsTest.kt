package com.ar.dosarcusina.store

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.ar.dosarcusina.store.schema.BinderDatabase
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files

/**
 * Every committed version of the database opens as the current one, with what it held: a database
 * made exactly as each version's schema says (store/schemas), holding one record of each model
 * written with nothing but its id, is opened by the store, which brings it to the current version
 * through its migrations and checks its shape against the current one (Room refuses a database
 * whose shape isn't the one it knows).
 */
class StoreVersionsTest {
    private val models = listOf(
        "Asset", "Obligation", "HistoryEntry", "ServiceItem", "MeasurementLog", "Attachment",
        "AttachmentPage", "Provider", "IssuerLesson",
    )

    @Test
    fun everyVersionIsCommittedFromTheFirst() {
        assertEquals((1..BinderDatabase.VERSION).toList(), RoomSchema.committed().map { it.version })
    }

    @Test
    fun everyCommittedVersionOpens() {
        for (schema in RoomSchema.committed()) {
            val folder = Files.createTempDirectory(storeScratch.toPath(), "version-${schema.version}-").toFile()
            val file = File(folder, "binder.sqlite")
            make(schema, file)
            val database = BinderStore.database(file.path, DatabaseBuilders.JVM)
            try {
                runBlocking {
                    val keys = database.templates().all().map { it.key }
                    assertEquals(listOf("boats"), keys, "version ${schema.version}")
                    assertEquals(1, database.assets().all().size)
                    assertEquals(1, database.obligations().all().size)
                    assertEquals(1, database.history().all().size)
                    assertEquals(1, database.items().all().size)
                    assertEquals(1, database.readings().all().size)
                    assertEquals(1, database.attachments().all().size)
                    assertEquals(1, database.pages().all().size)
                    assertEquals(1, database.providers().all().size)
                    assertEquals(1, database.lessons().all().size)
                    // A record written with nothing but its id reads with the iOS models' defaults.
                    val deadline = database.obligations().all().single()
                    assertEquals(listOf(30, 7, 0), deadline.reminderLeadDays)
                    assertEquals("comfort", deadline.consequenceRaw)
                    assertEquals("routine", deadline.kindRaw)
                    assertTrue(database.templates().all().single().isOnHome)
                }
            } finally {
                database.close()
            }
        }
    }

    /** A database of [schema]'s version, as that version made it, with one record of each model. */
    private fun make(schema: RoomSchema, file: File) {
        val connection = BundledSQLiteDriver().open(file.path)
        connection.use {
            for (table in schema.tables.values) {
                it.execSQL(table.createSql.replace("\${TABLE_NAME}", table.name))
                for (index in table.indexSql) it.execSQL(index.replace("\${TABLE_NAME}", table.name))
            }
            schema.setupQueries.forEach(it::execSQL)
            it.execSQL("PRAGMA user_version = ${schema.version}")
            it.execSQL("INSERT INTO CategoryTemplate (`key`) VALUES ('boats')")
            for ((index, model) in models.withIndex()) {
                it.execSQL("INSERT INTO `$model` (id) VALUES ('00000000-0000-4000-8000-00000000000${index + 1}')")
            }
        }
    }
}
