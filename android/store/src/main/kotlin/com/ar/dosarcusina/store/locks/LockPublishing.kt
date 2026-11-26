package com.ar.dosarcusina.store.locks

import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.StoredMoment
import java.time.Instant

/**
 * Sends up the locks this phone chose that never travelled: each category this phone keeps locked
 * by its own choice, whose record says it was never locked anywhere, gets when this phone locked it,
 * or [now] when that isn't known (`lockedEverywhereAt`). Then every other phone, a new one included,
 * keeps it locked until it is opened there ([SectionLocks.isLocked]). The iOS app's `LockPublishing`,
 * run at each launch; the rows it gives are the app's own step's to save, which gives no change time.
 * A lock chosen from now on travels as it is made ([CategoryLocks.setLock]).
 */
object LockPublishing {
    /** The rows of [templates] to save with their lock sent up; none when there is nothing to send. */
    fun toSend(templates: List<CategoryTemplate>, locks: SectionLocks, now: Instant): List<CategoryTemplate> =
        templates.mapNotNull { template ->
            val here = locks.lockedHere(template.key)
            if (template.lockedEverywhereAt != null || here?.locked != true) return@mapNotNull null
            template.copy(lockedEverywhereAt = StoredMoment.kept(here.at ?: now))
        }
}
