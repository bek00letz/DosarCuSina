package com.ar.dosarcusina.store

import androidx.room3.useReaderConnection
import androidx.room3.withReadTransaction
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.BinderDatabase
import kotlinx.coroutines.runBlocking
import java.util.TreeMap

/**
 * What one step of the unit of work changes, and the binder as the step sees it: the iOS app's
 * `ModelContext` inside `UnitOfWork.perform`. Only a unit of work makes one ([UnitOfWork.perform]),
 * and it is good only while its work runs.
 *
 * A step reads the binder as stored, each kind of record the first time it is asked for, with its
 * own changes laid over it: what it [insert]s, [update]s and [delete]s, the links to many it sets
 * ([setLinked]), the files it keeps ([keep]) and the lock each category it makes is made with
 * ([lockMadeWith]). Nothing reaches the database until the unit saves, all of it in one
 * transaction, so a step that fails leaves nothing behind; and since the unit holds the store's
 * write lock for the whole step, the binder under it doesn't change while it runs.
 *
 * A record is an immutable row; changing one is writing it again. A record a step makes gets its
 * row as it is made, so the next record can link to it at once. Deleting a record lets go of every
 * link to it, as the database's `ON DELETE SET NULL` does, so what the step sees is what will be
 * stored; a record goes with what it holds only through [delete] ([RecordContents]).
 */
// The step's whole surface: reading, writing, links, files and a new category's lock.
@Suppress("TooManyFunctions")
class Step internal constructor(
    private val database: BinderDatabase,
    private val files: StoreFiles,
) : BinderView {
    private var isOpen = true
    private val base = HashMap<Table<*>, TreeMap<Long, Any>>()
    private val current = HashMap<Table<*>, TreeMap<Long, Any>>()
    private val baseLinks = HashMap<ManyLink, Map<Long, List<Long>>>()
    private val currentLinks = HashMap<ManyLink, TreeMap<Long, List<Long>>>()
    private val nextRows = HashMap<Table<*>, Long>()
    private val locksAsked = HashMap<Long, Boolean>()

    /** Whether the step kept a file into the store, so the files no record names go when it ends. */
    internal var keptFiles = false
        private set

    /** Counts the step's writes, so what is worked out from the binder as it stands is worked out again. */
    private var version = 0L
    private val inverse = HashMap<Pair<ToOne<*>, Boolean>, Pair<Long, Map<Long, List<Long>>>>()

    /** The binder as stored, before anything this step changes: what change times and undo compare with. */
    val stored: BinderView = object : BinderView {
        override fun <R : Any> all(table: Table<R>): List<R> = baseOf(table).values.map(::cast)

        override fun <R : Any> row(table: Table<R>, row: Long): R? = baseOf(table)[row]?.let(::cast)

        override fun linked(link: ManyLink, owner: Long): List<Long> = baseLinksOf(link)[owner].orEmpty()

        override fun <R : Any> pointingAt(table: Table<R>, linkName: String, row: Long): List<Long> =
            index(table, linkName, stored = true)[row].orEmpty()

        override fun linkedTo(link: ManyLink, row: Long): List<Long> =
            baseLinksOf(link).filterValues { row in it }.keys.toList()
    }

    // Reading

    override fun <R : Any> all(table: Table<R>): List<R> = rowsOf(table).values.map(::cast)

    override fun <R : Any> row(table: Table<R>, row: Long): R? = rowsOf(table)[row]?.let(::cast)

    /** The record of [table] with [key] ([Table.keyOf]: its id, a category's key), the first in row order. */
    fun <R : Any> find(table: Table<R>, key: String): R? = all(table).firstOrNull { table.keyOf(it) == key }

    override fun linked(link: ManyLink, owner: Long): List<Long> = linksOf(link)[owner].orEmpty()

    override fun <R : Any> pointingAt(table: Table<R>, linkName: String, row: Long): List<Long> =
        index(table, linkName, stored = false)[row].orEmpty()

    override fun linkedTo(link: ManyLink, row: Long): List<Long> =
        linksOf(link).filterValues { row in it }.keys.toList()

    // Writing

    /** Makes [record], which has no row yet, and gives it with the row it is kept in. */
    fun <R : Any> insert(record: R): R {
        val table = Tables.of(record)
        require(table.rowOf(record) == 0L) { "A new ${table.type} has no row yet" }
        val made = table.withRow(record, nextRow(table))
        rowsOf(table)[table.rowOf(made)] = made
        changed()
        return made
    }

    /** Writes [record] over the one in its row, which must be there. */
    fun <R : Any> update(record: R) {
        val table = Tables.of(record)
        val rows = rowsOf(table)
        val row = table.rowOf(record)
        require(row in rows) { "No ${table.type} in row $row" }
        if (rows[row] == record) return
        rows[row] = record
        changed()
    }

    /** Deletes [record] and everything it holds: the one way a record is deleted ([RecordContents.delete]). */
    fun delete(record: Any) = RecordContents.delete(this, record)

    /** Links [owner] to [targets] through [link], in this order, instead of whatever it linked to. */
    fun setLinked(link: ManyLink, owner: Long, targets: List<Long>) {
        val links = linksOf(link)
        val wanted = targets.distinct()
        if (links[owner].orEmpty() == wanted) return
        if (wanted.isEmpty()) links.remove(owner) else links[owner] = wanted
        changed()
    }

    /** Keeps [file] in the store, a piece at a time, and gives its digest: the value of the column that names it. */
    fun keep(file: StoredFile): String {
        keptFiles = true
        return files.keep(file)
    }

    /**
     * Says whether [template], which this step made, is made locked: kept as this phone's choice
     * before the step saves ([DeviceLocks.madeWith]), so no category is saved open that was made
     * locked, and the step saves nothing when it can't be kept.
     */
    fun lockMadeWith(template: CategoryTemplate, locked: Boolean) {
        check(isOpen) { "A step is good only while its work runs" }
        require(Tables.templates.rowOf(template) != 0L && stored.row(Tables.templates, template.pk) == null) {
            "Only a category this step makes is made with a lock"
        }
        locksAsked[template.pk] = locked
    }

    /** The lock each category the step made was made with, by row. */
    internal val madeLocked: Map<Long, Boolean> get() = locksAsked

    /**
     * Deletes [record]'s row alone, letting go of every link to it, as the database does: a list
     * kept of its own loses it, a link to one is cleared. What it holds stays; the app's deletions
     * go through [delete].
     */
    internal fun remove(record: Any) {
        val table = Tables.of(record)
        val row = table.rowOf(record)
        requireNotNull(rowsOf(table).remove(row)) { "No ${table.type} in row $row" }
        for (other in Tables.all) {
            for (link in other.links) {
                if (link.target !== table) continue
                @Suppress("UNCHECKED_CAST")
                val typed = link as ToOne<Any>
                val rows = rowsOf(other)
                for ((key, held) in rows.entries.toList()) {
                    if (typed.get(held) == row) rows[key] = typed.set(held, null)
                }
            }
        }
        for (link in Tables.manyLinks) {
            val links = linksOf(link)
            if (link.owner === table) links.remove(row)
            if (link.target === table) {
                for ((owner, targets) in links.entries.toList()) {
                    if (row !in targets) continue
                    val left = targets - row
                    if (left.isEmpty()) links.remove(owner) else links[owner] = left
                }
            }
        }
        changed()
    }

    /** Brings back, in [row], a record a step deleted: blank, for undo to write every property of. */
    internal fun <R : Any> bringBack(table: Table<R>, row: Long): R {
        val rows = rowsOf(table)
        require(row !in rows) { "${table.type} $row is there" }
        val record = table.withRow(table.blank(), row)
        rows[row] = record
        changed()
        return record
    }

    // What the unit of work reads

    /** The rows of [table] the step changed: made, written again or deleted. */
    internal fun <R : Any> changes(table: Table<R>): Changes<R> {
        val before = base[table] ?: return Changes()
        val after = current[table] ?: return Changes()
        return Changes(
            made = after.filterKeys { it !in before }.values.map(::cast),
            written = after.filter { (row, record) -> row in before && before[row] != record }.values.map(::cast),
            deleted = before.filterKeys { it !in after }.values.map(::cast),
        )
    }

    /** The owners whose links to many the step changed. */
    internal fun changedOwners(link: ManyLink): Set<Long> {
        val before = baseLinks[link] ?: return emptySet()
        val after = currentLinks[link] ?: return emptySet()
        return (before.keys + after.keys).filterTo(mutableSetOf()) { before[it] != after[it] }
    }

    /** What the step changed in one kind of record. */
    internal class Changes<R>(
        val made: List<R> = emptyList(),
        val written: List<R> = emptyList(),
        val deleted: List<R> = emptyList(),
    ) {
        val isEmpty: Boolean get() = made.isEmpty() && written.isEmpty() && deleted.isEmpty()

        /** What the step made or wrote again: what it saves. */
        val saved: List<R> get() = made + written
    }

    /** Whether the step changes anything at all. */
    internal val hasChanges: Boolean
        get() = Tables.all.any { !changes(it).isEmpty } || Tables.manyLinks.any { changedOwners(it).isNotEmpty() }

    /** Writes everything the step changed, inside the unit's write transaction. */
    internal suspend fun write() {
        for (table in Tables.all) writeRows(table)
        for (link in Tables.manyLinks) {
            val after = currentLinks[link] ?: continue
            for (owner in changedOwners(link)) {
                if (owner in baseLinks.getValue(link)) link.deleteOf(database, owner)
                for (target in after[owner].orEmpty()) link.insert(database, owner, target)
            }
        }
    }

    private suspend fun <R : Any> writeRows(table: Table<R>) {
        val changes = changes(table)
        val rows = table.rows(database)
        for (record in changes.deleted) rows.delete(record)
        for (record in changes.made) {
            val row = rows.insert(record)
            check(row == table.rowOf(record)) { "${table.type} was kept in row $row, not ${table.rowOf(record)}" }
        }
        for (record in changes.written) rows.update(record)
    }

    /** Ends the step: nothing reads or writes through it any more. */
    internal fun close() {
        isOpen = false
    }

    // Loading

    private fun <R : Any> baseOf(table: Table<R>): TreeMap<Long, Any> {
        check(isOpen) { "A step is good only while its work runs" }
        return base.getOrPut(table) {
            val rows = runBlocking { database.withReadTransaction { table.readAll(database) } }
            TreeMap<Long, Any>().apply { for (row in rows) put(table.rowOf(row), row) }
        }
    }

    private fun <R : Any> rowsOf(table: Table<R>): TreeMap<Long, Any> {
        val stored = baseOf(table)
        return current.getOrPut(table) { TreeMap(stored) }
    }

    private fun baseLinksOf(link: ManyLink): Map<Long, List<Long>> {
        check(isOpen) { "A step is good only while its work runs" }
        return baseLinks.getOrPut(link) {
            val pairs = runBlocking { database.withReadTransaction { link.readAll(database) } }
            pairs.groupBy({ it.first }, { it.second }).mapValues { (_, targets) -> targets.distinct() }
        }
    }

    private fun linksOf(link: ManyLink): TreeMap<Long, List<Long>> {
        val stored = baseLinksOf(link)
        return currentLinks.getOrPut(link) { TreeMap(stored) }
    }

    /** The next row of [table]: after every row it ever had, as SQLite gives them, so none is given twice. */
    private fun nextRow(table: Table<*>): Long {
        val next = nextRows[table] ?: maxOf(sequence(table), baseOf(table).lastEntry()?.key ?: 0L) + 1
        nextRows[table] = next + 1
        return next
    }

    private fun sequence(table: Table<*>): Long = runBlocking {
        database.useReaderConnection { connection ->
            connection.usePrepared("SELECT seq FROM sqlite_sequence WHERE name = ?") { statement ->
                statement.bindText(1, table.type)
                if (statement.step()) statement.getLong(0) else 0L
            }
        }
    }

    /** The rows of [table] by the row their link [linkName] points at, in the step's binder or as stored. */
    private fun <R : Any> index(table: Table<R>, linkName: String, stored: Boolean): Map<Long, List<Long>> {
        val link = table.links.first { it.name == linkName }
        val key = link to stored
        val at = if (stored) -1L else version
        inverse[key]?.let { (built, index) -> if (built == at) return index }
        val rows = if (stored) this.stored.all(table) else all(table)
        val index = rows.mapNotNull { record -> link.get(record)?.let { it to table.rowOf(record) } }
            .groupBy({ it.first }, { it.second })
        inverse[key] = at to index
        return index
    }

    private fun changed() {
        check(isOpen) { "A step is good only while its work runs" }
        version += 1
    }

    @Suppress("UNCHECKED_CAST")
    private fun <R> cast(record: Any): R = record as R
}
