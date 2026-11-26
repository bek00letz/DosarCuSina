package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.StoredMoment
import java.time.Instant

/**
 * Whether a category's sections are behind the person's confirmation on this phone, and the one way
 * to lock or open one: the iOS app's `CategoryTemplate.isSensitive` and `setLock`,
 * `CategoryTemplate.isSensitive(key:template:in:)`, `SectionLocks.lockedWhileUnknown` and
 * `TemplateStore.keepLocksAsTheyAre`, over this phone's choices ([choices]) and the app's catalog
 * ([builtIns], `Catalog.builtIn`).
 *
 * A row is never told whether it is locked: it carries only when it was last locked anywhere
 * (`lockedEverywhereAt`), and whatever changes a lock gives back the row to save, which the
 * caller's step saves. Opening a category needs a [LockLowering]; locking one needs none.
 */
class CategoryLocks(
    /** This phone's choices, beside the store. */
    val choices: SectionLocks,
    /** The app's built-in categories, for which of them the catalog locks. */
    private val builtIns: BuiltIns,
) {
    /** The built-in categories locked until this phone decides otherwise (Acte and Sănătate). */
    val lockedByDefault: Set<String> = builtIns.all.filter { it.isSensitiveByDefault }.map { it.key }.toSet()

    /**
     * Whether a category this phone has no record of yet is locked here, until its record arrives
     * (sync bringing it, an import): a built-in as the catalog says, any other locked, since it can't
     * be told whether it was. Locks fail closed.
     */
    fun lockedWhileUnknown(key: String): Boolean = builtIns.definition(key)?.isSensitiveByDefault ?: true

    /**
     * Whether the sections of [template] are locked on this phone: as it was locked anywhere and as
     * this phone chose ([SectionLocks.isLocked]), else as the catalog says for a built-in; one of the
     * person's own was made with its lock as this phone's choice ([madeWith]). While this phone's
     * locks couldn't be read, every category is locked.
     */
    fun isSensitive(template: CategoryTemplate): Boolean {
        val byDefault = template.isBuiltIn && template.key in lockedByDefault
        return choices.isLocked(template.key, byDefault, template.lockedEverywhereAt)
    }

    /**
     * Whether the sections of the category [key] are locked on this phone: the one answer for every
     * screen and every surface, whether or not the category's record is here. With its record
     * ([template]), the record's lock; without it, this phone's choice for the key, else
     * [lockedWhileUnknown], so a section whose category hasn't arrived yet is never shown or sent
     * outside as open. Never read a missing record as open.
     */
    fun isSensitive(key: String, template: CategoryTemplate?): Boolean =
        template?.let(::isSensitive) ?: choices.isLocked(key, lockedWhileUnknown(key))

    /** The same answer, from the categories by key. */
    fun isSensitive(key: String, among: Map<String, CategoryTemplate>): Boolean = isSensitive(key, among[key])

    /** Whether each of [templates] is locked here, by key; two copies of one are locked if either is. */
    fun locked(templates: List<CategoryTemplate>): Map<String, Boolean> =
        templates.groupBy { it.key }.mapValues { (_, copies) -> copies.any(::isSensitive) }

    /**
     * Locks or opens [template] on this phone, as chosen at [now], and gives its row to save.
     * Opening one that is locked now takes the person's confirmation, every time ([lowering]);
     * without it, it throws [LockLowering.Needed] and nothing changes. Throws too when the choice
     * can't be kept.
     *
     * Locking one that is open here locks it on every phone too: the row comes back with when
     * (`lockedEverywhereAt`), which the caller's step saves and sync carries. Opening one, or keeping
     * a lock that is already on, stays on this phone and changes no row.
     */
    fun setLock(template: CategoryTemplate, locked: Boolean, lowering: LockLowering?, now: Instant): CategoryTemplate {
        val wasLocked = isSensitive(template)
        if (!locked && wasLocked && lowering == null) throw LockLowering.Needed()
        choices.set(locked, template.key, now)
        return if (locked && !wasLocked) template.copy(lockedEverywhereAt = StoredMoment.kept(now)) else template
    }

    /** Locks [template] here, as chosen at [now] ([setLock]): locking needs no confirmation. */
    fun lock(template: CategoryTemplate, now: Instant): CategoryTemplate =
        setLock(template, locked = true, lowering = null, now = now)

    /**
     * Keeps the lock a new category is made with as this phone's choice, unless this phone already
     * chose for its key, before the save that makes it; gives its row to save.
     */
    fun madeWith(template: CategoryTemplate, locked: Boolean, now: Instant): CategoryTemplate {
        choices.adopt(mapOf(template.key to locked))
        // One of the person's own made locked is locked on every phone; a built-in's lock is the
        // catalog's, the same everywhere already.
        val travels = locked && !template.isBuiltIn && template.lockedEverywhereAt == null
        return if (travels) template.copy(lockedEverywhereAt = StoredMoment.kept(now)) else template
    }

    /**
     * Ends the wait after this phone's locks couldn't be read ([SectionLocks.needsChoosingAgain]):
     * every category of [templates] keeps the lock it shows now (on, for every one), as this phone's
     * choice, and a category of one's own that arrives from another phone starts open again. That
     * opens what would have been locked, so it takes the person's confirmation ([lowering]); without
     * it, it throws [LockLowering.Needed] and nothing changes.
     */
    fun keepLocksAsTheyAre(templates: List<CategoryTemplate>, lowering: LockLowering?, now: Instant) {
        if (lowering == null) throw LockLowering.Needed()
        choices.chooseAgain(locked(templates), now)
    }
}
