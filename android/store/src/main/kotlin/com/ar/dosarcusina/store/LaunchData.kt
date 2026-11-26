package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.binder.Removed
import com.ar.dosarcusina.catalog.BuiltInInstall
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.locks.LockPublishing
import com.ar.dosarcusina.store.templates.HouseholdDeadlines
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * What launch does to the household's data, in this order, as the iOS app's `LaunchData`
 * (ios/DosarCuSina/App/LaunchData.swift): what a deletion let go put back with its holder
 * ([ParentLinks.rehome]), the built-in categories from the app's catalog ([BuiltInInstall]), then
 * this phone's locks sent up ([LockPublishing]). Each step saves through the unit of work on its
 * own, as the app's own step ([ChangeOrigin.APP]: nothing it changes gets a new change time), so
 * one that fails takes back only its own changes and is tried again at the next launch. Nothing
 * here is the person's to answer, so nothing is shown; a failure goes to the persistence log, by
 * its kind and without any of the household's values, and the next step still runs.
 *
 * Last, the household's own deadlines ([HouseholdDeadlines]). The steps the iOS app runs between
 * these (copies that meet, what capture learned, the repair list) come with what they keep.
 */
class LaunchData(
    private val unit: UnitOfWork,
    private val catalog: Catalog = Catalog.builtIn,
    /** The time zone the app counts days in, for reading the binder as the catalog's plan reads it. */
    private val zone: () -> ZoneId = DosarCalendar::zone,
) {
    /** The steps, by the name the log gives them. */
    enum class LaunchStep(val label: String) {
        PARENT_LINKS("Putting back what a deletion let go"),
        BUILT_IN_CATEGORIES("Installing the built-in categories"),
        LOCK_PUBLISHING("Sending this device's locks to the others"),
        HOUSEHOLD_DEADLINES("Working out the household's own deadlines"),
    }

    /** Runs every step; gives the ones that failed, which the log names. */
    fun prepare(now: Instant = unit.clock()): List<LaunchStep> = LaunchStep.entries.filterNot { step ->
        unit.log.attempt(step.label) {
            when (step) {
                LaunchStep.PARENT_LINKS -> rehome()
                LaunchStep.BUILT_IN_CATEGORIES -> installBuiltIns(now)
                LaunchStep.LOCK_PUBLISHING -> publishLocks(now)
                LaunchStep.HOUSEHOLD_DEADLINES -> reconcileHouseholdRules(now)
            }
        }
    }

    /** Every record left without what held it goes back to a copy of its holder by its id. Whether anything did. */
    fun rehome(): Boolean = unit.perform(ChangeOrigin.APP) { step ->
        val held = ParentLinks.Held(
            obligations = step.all(Tables.obligations),
            attachments = step.all(Tables.attachments),
            history = step.all(Tables.history),
            readings = step.all(Tables.readings),
            items = step.all(Tables.items),
            pages = step.all(Tables.pages),
        )
        if (held.loose().isEmpty) return@perform false
        val back = ParentLinks.rehome(
            held,
            assets = rowOfId(step.all(Tables.assets)) { it.id to it.pk },
            entries = rowOfId(step.all(Tables.history)) { it.id to it.pk },
            attachments = rowOfId(step.all(Tables.attachments)) { it.id to it.pk },
        )
        (back.obligations + back.attachments + back.history + back.readings + back.items + back.pages)
            .forEach(step::update)
        !back.isEmpty
    }

    /**
     * Installs the built-ins the binder lacks and gives the installed ones the catalog's definition
     * where theirs is older, keeping the household's choices ([BuiltInInstall.plan]), in one app-made
     * step: no record's change time moves, and each built-in it makes starts with the catalog's lock
     * only where this phone has no choice for it yet ([DeviceLocks.madeWith]). Whether anything changed.
     */
    fun installBuiltIns(now: Instant): Boolean = unit.perform(ChangeOrigin.APP, now) { step ->
        val locked = unit.locks.locked(step.all(Tables.templates))
        val binder = BinderReading(unit.store.files, zone()).read(step, locked)
        // Until the binder can arrive from elsewhere (sync), it is always whole here.
        val plan = BuiltInInstall.plan(catalog, binder, now, binderIsWhole = true)
        if (!plan.changesAnything) return@perform false
        val written = Binder(templates = plan.templates, assets = plan.assets)
        BinderWriting(step, BinderChanges(written, Removed(templates = plan.removedTemplates), emptyMap())).write()
        for (template in step.changes(Tables.templates).made) {
            plan.startingLocks[template.key]?.let { step.lockMadeWith(template, it) }
        }
        true
    }

    /** This phone's locks that never travelled, sent up on their categories' records. Whether any were. */
    fun publishLocks(now: Instant): Boolean = unit.perform(ChangeOrigin.APP, now) { step ->
        val rows = LockPublishing.toSend(step.all(Tables.templates), unit.store.locks, now)
        rows.forEach(step::update)
        rows.isNotEmpty()
    }

    /**
     * The household's own deadlines worked out again from its sections ([HouseholdDeadlines]), as the
     * app's own step: nothing it changes gets a new change time. Whether anything changed.
     */
    fun reconcileHouseholdRules(now: Instant): Boolean = unit.perform(ChangeOrigin.APP, now) { step ->
        HouseholdDeadlines(catalog.household, zone()).reconcile(step, CalendarDay.of(now, zone()), now)
    }

    private fun <R> rowOfId(rows: List<R>, pair: (R) -> Pair<UUID, Long>): ParentLinks.RowOfId {
        val byId = LinkedHashMap<UUID, Long>()
        for (row in rows) pair(row).let { (id, pk) -> byId.putIfAbsent(id, pk) }
        return ParentLinks.RowOfId(byId::get)
    }
}
