package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.IosModel.Kind
import com.ar.dosarcusina.store.schema.BinderDatabase
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * The store has the iOS models' shape (database version 19), read from the iOS sources and from
 * Room's schema of the current version: one table per model under its name, one column per stored
 * property under its name, a table per link to many a model keeps itself, and nothing else but
 * each table's row. A property the iOS app adds fails here until the store has its column.
 */
class StoreShapeTest {
    private val models = IosModel.all()
    private val schema = RoomSchema.committed().last()

    /** The table of a link to many that [model] keeps itself, by the iOS relationship's name. */
    private fun linkTable(model: String, link: String) = "${model}_$link"

    @Test
    fun theCurrentVersionIsCommitted() {
        assertEquals(BinderDatabase.VERSION, schema.version, "Room's schema of the current version is in store/schemas")
    }

    @Test
    fun everyModelIsATable() {
        assertEquals(10, models.size, "RecordState.swift lists the ten models of iOS version 19")
        val linkTables = models.flatMap { model -> model.named(Kind.LINKS).map { linkTable(model.name, it) } }
        assertEquals((models.map { it.name } + linkTables).toSet(), schema.tables.keys)
    }

    @Test
    fun everyStoredPropertyHasItsColumn() {
        for (model in models) {
            val table = schema.tables.getValue(model.name)
            for (name in model.named(Kind.ATTRIBUTE) + model.named(Kind.TO_ONE)) {
                assertTrue(name in table.columns, "${model.name}.$name has a column")
            }
        }
    }

    @Test
    fun everyColumnIsAStoredProperty() {
        for (model in models) {
            val table = schema.tables.getValue(model.name)
            val stored = model.named(Kind.ATTRIBUTE) + model.named(Kind.TO_ONE)
            assertEquals(stored + "pk", table.columns.keys, "${model.name} keeps the iOS properties and its row")
            assertEquals(listOf("pk"), table.primaryKey)
        }
    }

    @Test
    fun aLinkToOneIsTheRowItPointsAt() {
        for (model in models) {
            val table = schema.tables.getValue(model.name)
            for (link in model.named(Kind.TO_ONE)) {
                val key = table.foreignKeys.singleOrNull { it.column == link }
                assertTrue(key != null, "${model.name}.$link is a link to a row")
                assertEquals("SET NULL", key?.onDelete, "${model.name}.$link lets go when what it points at goes")
            }
            assertEquals(model.named(Kind.TO_ONE), table.foreignKeys.map { it.column }.toSet())
        }
    }

    @Test
    fun aLinkToManyIsATableOfItsOwn() {
        for (model in models) {
            for (link in model.named(Kind.LINKS)) {
                val table = schema.tables.getValue(linkTable(model.name, link))
                assertEquals(setOf("pk", table.foreignKeys[0].column, table.foreignKeys[1].column), table.columns.keys)
                assertEquals(model.name, table.foreignKeys[0].table, "The first column is the side that keeps the link")
            }
        }
    }

    @Test
    fun noLinkDeletesWhatItPointsAt() {
        for (table in schema.tables.values) {
            assertTrue("CASCADE" !in table.createSql, "${table.name} deletes nothing it points at")
            assertTrue(table.foreignKeys.all { it.onDelete == "SET NULL" || it.onDelete == "NO ACTION" }, table.name)
        }
    }

    @Test
    fun everyColumnIsOptionalOrDefaulted() {
        for (table in schema.tables.values) {
            for (column in table.columns.values) {
                // A row's key is SQLite's, and a record's id is given by whoever makes it, as on iOS.
                if (column.name == "pk" || column.name == "id") continue
                val defaulted = !column.notNull || column.defaultValue != null
                assertTrue(defaulted, "${table.name}.${column.name} is optional or defaulted")
            }
        }
    }

    @Test
    fun nothingIsUnique() {
        for (table in schema.tables.values) assertEquals(emptyList<String>(), table.uniqueIndices, table.name)
    }

    @Test
    fun theHolderIdsAreTheIosOnes() {
        val source = File(iosSources, "Services/Persistence/ParentLinks.swift").readText()
        val declaration = Regex("""static let idNames: Set<String> = \[([^\]]*)]""")
        val names = requireNotNull(declaration.find(source)).groupValues[1]
        assertEquals(Regex("\"(\\w+)\"").findAll(names).map { it.groupValues[1] }.toSet(), ParentLinks.idNames)
        val held = mapOf(
            "Obligation" to "assetID", "Attachment" to "assetID", "HistoryEntry" to "assetID",
            "MeasurementLog" to "assetID", "ServiceItem" to "entryID", "AttachmentPage" to "attachmentID",
        )
        for ((model, id) in held) assertTrue(id in schema.tables.getValue(model).columns, "$model.$id")
    }

    @Test
    fun recordContentsHoldsWhatIosHolds() {
        val source = File(iosSources, "Services/Persistence/RecordContents.swift").readText()
        val owned = Regex("\"(\\w+)\": \\[([^\\]]*)]").findAll(source).associate { match ->
            match.groupValues[1] to Regex("\"(\\w+)\"").findAll(match.groupValues[2]).map { it.groupValues[1] }.toSet()
        }
        assertEquals(owned, RecordContents.owned)
    }

    @Test
    fun whatStaysOnThePhoneIsTheIosList() {
        val source = File(iosSources, "Services/Archive/DossierArchiveV3.swift").readText()
        val list = source.substringAfter("static let stayOnThePhone").substringBefore("]\n    static")
        val stays = Regex("\"(\\w+)\": \\[([^\\]]*)]").findAll(list).associate { match ->
            match.groupValues[1] to Regex("\"(\\w+)\"").findAll(match.groupValues[2]).map { it.groupValues[1] }.toSet()
        }
        assertEquals(stays, StayOnThePhone.properties)
        for ((model, names) in stays) {
            for (name in names) assertTrue(name in schema.tables.getValue(model).columns, "$model.$name is kept here")
        }
    }
}
