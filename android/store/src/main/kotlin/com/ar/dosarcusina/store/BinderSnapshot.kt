package com.ar.dosarcusina.store

import androidx.room3.withReadTransaction
import com.ar.dosarcusina.store.schema.BinderDatabase
import java.util.TreeMap

/**
 * The whole binder as stored at one moment, read in one read transaction: what a backup reads and
 * what a test compares. Reading only; every write goes through a [Step].
 */
class BinderSnapshot private constructor(
    private val tables: Map<Table<*>, TreeMap<Long, Any>>,
    private val links: Map<ManyLink, Map<Long, List<Long>>>,
) : BinderView {
    override fun <R : Any> all(table: Table<R>): List<R> = tables.getValue(table).values.map(::cast)

    override fun <R : Any> row(table: Table<R>, row: Long): R? = tables.getValue(table)[row]?.let(::cast)

    override fun linked(link: ManyLink, owner: Long): List<Long> = links.getValue(link)[owner].orEmpty()

    override fun linkedTo(link: ManyLink, row: Long): List<Long> =
        links.getValue(link).filterValues { row in it }.keys.toList()

    /** Every record's state, by its ref: the binder as undo and its tests compare it. */
    fun states(): Map<RecordRef, RecordState> =
        Tables.all.flatMap { table -> states(table) }.associateBy { it.ref }

    private fun <R : Any> states(table: Table<R>): List<RecordState> =
        all(table).map { RecordState.capture(table, it, this) }

    @Suppress("UNCHECKED_CAST")
    private fun <R> cast(record: Any): R = record as R

    companion object {
        /** The binder as [database] holds it now. */
        suspend fun read(database: BinderDatabase): BinderSnapshot = database.withReadTransaction {
            val tables = Tables.all.associateWith { table ->
                TreeMap<Long, Any>().apply { for (row in table.readAll(database)) put(rowOf(table, row), row) }
            }
            val links = Tables.manyLinks.associateWith { link ->
                link.readAll(database).groupBy({ it.first }, { it.second })
                    .mapValues { (_, targets) -> targets.distinct() }
            }
            BinderSnapshot(tables, links)
        }

        @Suppress("UNCHECKED_CAST")
        private fun rowOf(table: Table<*>, record: Any): Long = (table as Table<Any>).rowOf(record)
    }
}
