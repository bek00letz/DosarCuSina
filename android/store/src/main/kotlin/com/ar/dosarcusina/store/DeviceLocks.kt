package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.locks.BinderLocks
import com.ar.dosarcusina.store.schema.CategoryTemplate
import java.time.Instant

/**
 * Which categories are locked on this phone, kept beside the store and never in it: what the
 * store's own steps (the archive's target, the unit of work, the repair list) ask of the locks. The one
 * implementation is [com.ar.dosarcusina.store.locks.CategoryLocks], over this phone's choices
 * ([com.ar.dosarcusina.store.locks.SectionLocks]); nothing here can open a lock.
 */
interface DeviceLocks {
    /**
     * Whether each of [templates] is locked on this phone now, by key: the one answer
     * (`CategoryTemplate.isSensitive`). Two copies of one category, before they are joined, are
     * locked if either is.
     */
    fun locked(templates: List<CategoryTemplate>): Map<String, Boolean>

    /**
     * Which categories are locked across the binder ([BinderLocks]): those of [templates]' records, and
     * every category [naming] names whose record isn't here, by the one answer.
     */
    fun binder(templates: List<CategoryTemplate>, naming: Iterable<String>): BinderLocks

    /**
     * Locks [template] on this phone, as chosen at [now], and gives its row as it is to be saved:
     * with when it was locked everywhere (`lockedEverywhereAt`) when it was open here, so the lock
     * travels. Throws when the choice can't be kept; then nothing changed.
     */
    fun lock(template: CategoryTemplate, now: Instant): CategoryTemplate

    /**
     * Keeps the lock a new category is made with as this phone's choice, unless this phone already
     * chose for its key, and gives its row as it is to be saved (one of the person's own made locked
     * is locked on every phone). Called before the save that makes it, so no category is saved open
     * that was made locked; throws when the choice can't be kept, and then the save mustn't happen.
     */
    fun madeWith(template: CategoryTemplate, locked: Boolean, now: Instant): CategoryTemplate
}
