package com.ar.dosarcusina.store

import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import java.io.File

/** The iOS app's sources, where the tests read the models' shape. */
val iosSources: File get() = File(System.getProperty("dosar.ios") ?: "../../ios/DosarCuSina")

/** Room's committed schemas of the database, one file per version. */
val schemaFolder: File
    get() = File(System.getProperty("dosar.schemas") ?: "schemas", "com.ar.dosarcusina.store.schema.BinderDatabase")

/**
 * The iOS models' stored properties, as their `storedProperties` lists declare them
 * (ios/DosarCuSina/Services/Persistence/RecordState.swift): every attribute and relationship of
 * every model, which the iOS tests keep complete (`UndoReceiptTests`). Read from the source, so a
 * property the iOS app adds fails the Android tests until the store has it.
 */
data class IosModel(val name: String, val properties: Map<String, Kind>) {
    enum class Kind { ATTRIBUTE, TO_ONE, TO_MANY, LINKS }

    fun named(kind: Kind): Set<String> = properties.filterValues { it == kind }.keys

    companion object {
        fun all(): List<IosModel> {
            val source = File(iosSources, "Services/Persistence/RecordState.swift").readText()
            val extension = Regex("""extension (\w+): UndoableRecord \{(.*?)\n}""", RegexOption.DOT_MATCHES_ALL)
            val blocks = extension.findAll(source)
            val property = Regex("""\.(attribute|toOne|toMany|links)\("(\w+)"""")
            return blocks.map { block ->
                val properties = property.findAll(block.groupValues[2]).associate { match ->
                    val kind = when (match.groupValues[1]) {
                        "attribute" -> Kind.ATTRIBUTE
                        "toOne" -> Kind.TO_ONE
                        "toMany" -> Kind.TO_MANY
                        else -> Kind.LINKS
                    }
                    match.groupValues[2] to kind
                }
                IosModel(block.groupValues[1], properties)
            }.toList()
        }
    }
}

/** One table of a Room schema file. */
data class RoomTable(
    val name: String,
    val createSql: String,
    val columns: Map<String, Column>,
    val primaryKey: List<String>,
    val uniqueIndices: List<String>,
    val foreignKeys: List<ForeignKey>,
    /** The statements that make its indices, `${'$'}{TABLE_NAME}` for its name. */
    val indexSql: List<String>,
) {
    data class Column(val name: String, val notNull: Boolean, val defaultValue: String?)

    data class ForeignKey(val table: String, val column: String, val onDelete: String)
}

/** A committed Room schema of the database: its version, its identity and its tables. */
data class RoomSchema(
    val version: Int,
    val identityHash: String,
    val tables: Map<String, RoomTable>,
    val setupQueries: List<String>,
) {
    companion object {
        fun read(file: File): RoomSchema {
            val database = (MachineText.parse(file.readText()) as JsonObject).obj("database")
            val tables = database.list("entities").map { it as JsonObject }.map(::table)
            return RoomSchema(
                version = database.int("version"),
                identityHash = database.string("identityHash"),
                tables = tables.associateBy { it.name },
                setupQueries = database.list("setupQueries").map { (it as JsonPrimitive).content },
            )
        }

        /** Every committed version, oldest first. */
        fun committed(): List<RoomSchema> =
            schemaFolder.listFiles { file -> file.extension == "json" }.orEmpty().map(::read).sortedBy { it.version }

        private fun table(entity: JsonObject) = RoomTable(
            name = entity.string("tableName"),
            createSql = entity.string("createSql"),
            columns = entity.list("fields").map { it as JsonObject }.associate { field ->
                val name = field.string("columnName")
                val default = (field["defaultValue"] as? JsonPrimitive)?.content
                name to RoomTable.Column(name, field.bool("notNull"), default)
            },
            primaryKey = entity.obj("primaryKey").list("columnNames").map { (it as JsonPrimitive).content },
            uniqueIndices = entity.listOrEmpty("indices").map { it as JsonObject }
                .filter { it.bool("unique") }.map { it.string("name") },
            indexSql = entity.listOrEmpty("indices").map { (it as JsonObject).string("createSql") },
            foreignKeys = entity.listOrEmpty("foreignKeys").map { it as JsonObject }.flatMap { key ->
                key.list("columns").map {
                    RoomTable.ForeignKey(key.string("table"), (it as JsonPrimitive).content, key.string("onDelete"))
                }
            },
        )

        private fun JsonObject.obj(name: String) = getValue(name) as JsonObject

        private fun JsonObject.list(name: String) = getValue(name) as JsonArray

        private fun JsonObject.listOrEmpty(name: String) = (get(name) as? JsonArray).orEmpty()

        private fun JsonObject.string(name: String) = (getValue(name) as JsonPrimitive).content

        private fun JsonObject.int(name: String) = requireNotNull((getValue(name) as JsonPrimitive).intOrNull)

        private fun JsonObject.bool(name: String) = (get(name) as? JsonPrimitive)?.booleanOrNull ?: false
    }
}
