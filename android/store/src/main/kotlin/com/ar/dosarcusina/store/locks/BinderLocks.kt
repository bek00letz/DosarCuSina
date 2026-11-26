package com.ar.dosarcusina.store.locks

import androidx.room3.withReadTransaction
import com.ar.dosarcusina.store.schema.BinderDatabase
import com.ar.dosarcusina.store.schema.CategoryTemplate
import kotlin.coroutines.cancellation.CancellationException

/**
 * Which categories are locked on this phone across the whole binder: the one answer
 * ([CategoryLocks.isSensitive]) asked for every category whose record is here and for every category
 * a section names whose record isn't here yet, so a section that arrives before its category counts
 * as locked, as it reads on its own page. The iOS app's `BinderLocks`.
 *
 * Whatever asks whether anything of the binder is locked reads this, never the category records
 * alone: the app-switcher cover, the confirmation before a backup, Settings' row for the locks and
 * De verificat.
 */
class BinderLocks private constructor(
    /** The keys of the categories locked on this phone. */
    val lockedKeys: Set<String>,
    /** The binder couldn't be read: something of it may be locked (locks fail closed). */
    private val unread: Boolean,
) {
    /**
     * Whether anything of the binder may be locked on this phone: a category's lock is on, a section
     * whose category hasn't arrived reads as locked, or the binder couldn't be read.
     */
    val anySectionLocked: Boolean get() = unread || lockedKeys.isNotEmpty()

    override fun equals(other: Any?): Boolean =
        other is BinderLocks && other.lockedKeys == lockedKeys && other.unread == unread

    override fun hashCode(): Int = lockedKeys.hashCode() * HASH_MULTIPLIER + unread.hashCode()

    override fun toString(): String = "BinderLocks(lockedKeys=$lockedKeys, unread=$unread)"

    companion object {
        private const val HASH_MULTIPLIER = 31

        /**
         * From the categories' records and the keys the sections (or anything else asked about, such
         * as an item waiting in De verificat) name. Two copies of one category, before they are
         * joined, are locked if either is.
         */
        fun of(templates: List<CategoryTemplate>, naming: Iterable<String>, locks: CategoryLocks): BinderLocks {
            val byRecord = locks.locked(templates)
            val named = naming.toSet().filter { it !in byRecord && locks.isSensitive(it, template = null) }
            return BinderLocks(byRecord.filterValues { it }.keys + named, unread = false)
        }

        /** An answer in which something is locked: what a binder that can't be read gives. */
        val unreadable: BinderLocks = BinderLocks(emptySet(), unread = true)

        /**
         * The binder in [database]: its categories and the categories its sections name. A store that
         * can't be read gives an answer in which something is locked.
         */
        // Whatever stops the read, the answer fails closed.
        @Suppress("TooGenericExceptionCaught")
        suspend fun read(database: BinderDatabase, locks: CategoryLocks): BinderLocks = try {
            database.withReadTransaction {
                of(database.templates().all(), database.assets().templateKeys(), locks)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            unreadable
        }
    }
}
