package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import java.time.Instant

/**
 * Whose change a unit of work saves, which decides the change times it gives ([ChangeTimes]), as
 * the iOS app's `ChangeOrigin`.
 */
enum class ChangeOrigin {
    /** The person's own step (an edit, a filing, "Gata", a reorder): what it changes gets a new change time. */
    PERSON,

    /**
     * What the app does by itself to keep the binder right (the catalog's categories at launch,
     * the repair list, the household's own deadlines): it changes no record's time, so a copy of
     * the record that carries the person's change, on this phone or in a backup, is never taken
     * for the older one. What it makes still gets the time it was made.
     */
    APP,

    /**
     * Undo, putting records back as they were, change times included: no time is given. A backup's
     * own writer saves the same way, keeping the times the backup carries ([UnitOfWork.performPrivate]).
     */
    RESTORING,
}

/**
 * The one rule for change times (`updatedAt`), kept by the unit of work as it saves, and the only
 * code that writes them beside a backup's importer, as the iOS app's `ChangeTimes`
 * (ios/DosarCuSina/Services/Persistence/ChangeTimes.swift):
 *
 * - In the person's step ([ChangeOrigin.PERSON]), a record whose own values or links changed gets
 *   the step's time. A record only linked to (a section that got a new visit) hasn't changed: the
 *   visit keeps the link. A record whose values were written again as they were hasn't changed either.
 * - Records a step makes have the time they were made, whoever made them.
 * - A step the app takes by itself ([ChangeOrigin.APP]) changes no record's time.
 * - Undo ([ChangeOrigin.RESTORING]) puts the old times back with everything else.
 *
 * A built-in category is the app's own definition, the same on every phone: only what the person
 * chooses for it (its place on the binder, whether it shows there, its box, when it was locked
 * anywhere) is a change of it, and one the catalog installs starts with no change at all
 * ([ChangeTime.UNKNOWN]). A document's page is part of its document: changing, adding or taking
 * away a page is a change of the document.
 */
object ChangeTimes {
    /** The times the unit of work keeps about a record as it saves, never part of its own state. */
    val keptTimes: Set<String> = setOf("updatedAt", "cycleKnownAt")

    /** Which copy of a record it is: given by the device that made the copy, never a change of the record. */
    const val COPY_MARK: String = "copyID"

    /** What the person chooses for a built-in category; everything else of it is the catalog's. */
    val personsOwnChoices: Set<String> = setOf("homeOrder", "isOnHome", "boxGroupingRaw", "lockedEverywhereAt")

    /**
     * Whether [property] is part of the record's own state: a value or a link it keeps itself,
     * that counts as a change of it, and neither a time the unit keeps, nor which copy it is, nor
     * the id of what holds it (written from its link). The one definition: change times are given
     * by it, and undo checks and takes back by it.
     */
    fun <R : Any> isOwnState(property: StoredProperty<R>, record: R): Boolean =
        property.isOwn && property.name !in keptTimes && property.name != COPY_MARK &&
            property.name !in ParentLinks.idNames && changeCounts(record, property.name)

    /** The values and links a record keeps itself that count as a change of it ([isOwnState]). */
    fun <R : Any> ownState(table: Table<R>, record: R, view: BinderView): Map<String, StoredValue> =
        table.properties.filter { isOwnState(it, record) }.associate { it.name to it.read(record, view) }

    /** Whether a change to the stored property [name] is a change of [record]: every one, but a built-in category's. */
    private fun changeCounts(record: Any, name: String): Boolean =
        record !is CategoryTemplate || !record.isBuiltIn || name in personsOwnChoices

    /** The change time of a record a step makes at [now]: [now], but a built-in category's. */
    private fun changeTime(record: Any, now: Instant): Instant =
        if (record is CategoryTemplate && record.isBuiltIn) ChangeTime.UNKNOWN else now

    /**
     * Gives the change times a save calls for: [now] to every record the step made and, for the
     * person's step, to every record whose own values or links changed and to the document each
     * changed page belongs to. Since when each deadline's cycle is known is kept first, whoever's
     * step it is ([CycleTimes]).
     */
    internal fun stamp(step: Step, origin: ChangeOrigin, now: Instant) {
        if (origin == ChangeOrigin.RESTORING) return
        CycleTimes.stamp(step, now)
        for (table in Tables.all) made(step, table, now)
        if (origin != ChangeOrigin.PERSON) return
        for (table in Tables.all) changed(step, table, now)
        touchDocuments(step, now)
    }

    private fun <R : Any> made(step: Step, table: Table<R>, now: Instant) {
        val set = table.withUpdatedAt ?: return
        for (record in step.changes(table).made) step.update(set(record, changeTime(record, now)))
    }

    private fun <R : Any> changed(step: Step, table: Table<R>, now: Instant) {
        val set = table.withUpdatedAt ?: return
        val written = step.changes(table).written.map(table.rowOf)
        val relinked = Tables.manyLinks.filter { it.owner === table }.flatMap { step.changedOwners(it) }
        for (row in (written + relinked).distinct()) {
            val record = step.row(table, row)
            // Not stored yet: made by this step, with the time it was made.
            val stored = step.stored.row(table, row)
            if (record == null || stored == null) continue
            if (ownState(table, record, step) != ownState(table, stored, step.stored)) step.update(set(record, now))
        }
    }

    /** A page changed, added or taken away is a change of its document, as it is now and as it was. */
    private fun touchDocuments(step: Step, now: Instant) {
        val pages = step.changes(Tables.pages)
        val documents = (pages.saved + pages.deleted).flatMap { page: AttachmentPage ->
            listOfNotNull(page.attachment, step.stored.row(Tables.pages, page.pk)?.attachment)
        }.toSet()
        // One made by this step already has the time it was made.
        val touched = documents.filter { step.stored.row(Tables.attachments, it) != null }
        for (document in touched.mapNotNull { step.row(Tables.attachments, it) }) {
            step.update(document.copy(updatedAt = now))
        }
    }
}

/**
 * Since when a deadline's cycle is known as it now is ([Obligation.cycleKnownAt]): the moment the
 * one reminder that makes up for warnings already passed counts from. Kept by the unit of work as
 * it saves, beside the change times, and written by nothing else but a backup's importer, as the
 * iOS app's `CycleTimes` (ios/DosarCuSina/Services/Persistence/CycleTimes.swift):
 *
 * - A deadline a step makes is known from the moment it is made, whoever made it.
 * - A deadline whose due day, reminders' leads, travel margin or status changed is known as it now
 *   is from that moment, whoever changed it, the app's own steps included (its change time is
 *   another thing: the app's steps leave that alone).
 * - Anything else leaves it, a note, a cost, the reminder time and a snooze among them.
 * - Undo puts the old moment back with everything else ([ChangeOrigin.RESTORING] gives none).
 */
object CycleTimes {
    /** The stored properties of a deadline that make its cycle as the person knows it. */
    val cycleProperties: Set<String> = setOf("dueDayISO", "reminderLeadDays", "travelMarginDays", "statusRaw")

    /** Gives every deadline the step makes, and every one whose cycle it changes, [now]. */
    internal fun stamp(step: Step, now: Instant) {
        val changes = step.changes(Tables.obligations)
        for (made in changes.made) step.update(made.copy(cycleKnownAt = now))
        for (written in changes.written) {
            val stored = step.stored.row(Tables.obligations, written.pk) ?: continue
            if (cycle(written, step) != cycle(stored, step.stored)) step.update(written.copy(cycleKnownAt = now))
        }
    }

    /** The values of a deadline's cycle, by property. */
    fun cycle(obligation: Obligation, view: BinderView): Map<String, StoredValue> =
        Tables.obligations.properties.filter { it.name in cycleProperties }
            .associate { it.name to it.read(obligation, view) }
}
