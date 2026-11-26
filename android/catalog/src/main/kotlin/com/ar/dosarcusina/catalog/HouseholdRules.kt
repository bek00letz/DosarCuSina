package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.core.values.CalendarDay
import java.util.UUID

/**
 * Deadlines that belong to the household rather than to one section, as the iOS app's
 * `HouseholdRules` (ios/DosarCuSina/Services/Templates/HouseholdRules.swift): what each is made from
 * ([blueprints], the shared catalog's `household.json`), and which copy stays when there are two
 * ([kept]). The store keeps them in step with the sections that call for them
 * (`HouseholdDeadlines.reconcile`).
 *
 * Today there is one: while at least one tenancy exists, the household files a single "Declarația
 * unică" for rental income every year by 25 May (Codul fiscal, art. 120–122; ANAF). It has no
 * section: it isn't about one property but about the household's income, so it shows in Urmează
 * but in no section.
 */
class HouseholdRules(
    /** Every household deadline's blueprint: what a deadline with no section was made from. */
    val blueprints: List<ObligationBlueprint>,
) {
    /** The rental income declaration's blueprint. */
    val rentalDeclaration: ObligationBlueprint =
        blueprints.firstOrNull { it.key == RENTAL_DECLARATION_KEY }
            ?: throw CatalogError("household.json has no $RENTAL_DECLARATION_KEY")

    /**
     * One copy of a household deadline, as [kept] compares them: what the person left on it, its
     * cycle, and its id.
     */
    data class Copy(
        val id: UUID,
        val dueDay: CalendarDay,
        /** Still running (`ObligationStatus.active`). */
        val isOpen: Boolean,
        /** It has a completion: the person filed it. */
        val isFiled: Boolean,
        /** A document was filed with it. */
        val hasDocuments: Boolean,
        val notes: String?,
        val isSnoozed: Boolean,
        /** The person chose its reminders. */
        val remindersCustomized: Boolean,
        /** The person chose the time of day it reminds at. */
        val hasOwnReminderTime: Boolean,
    )

    /**
     * The copy of a household deadline that stays when there are several, whatever order they are
     * read in, so every phone keeps the same one:
     * 1. a copy with a completion: the person filed it. The one furthest on stays (a declaration filed
     *    this year is due next year), so no reminder comes back for a cycle already filed;
     * 2. else a copy with something else of the person's on it (a document, their own note, a snooze,
     *    reminders they changed): the overdue copy they were working on, never a fresh copy the app
     *    just made;
     * 3. else the earliest still open: the one that reminds soonest;
     * 4. then the smallest id.
     */
    fun <T> kept(copies: List<T>, copy: (T) -> Copy): T? =
        copies.minWithOrNull { a, b -> order(copy(a), copy(b)) }

    /**
     * Whether the person left something of theirs on a copy besides a completion: a document, a note
     * other than the one the app writes, a snooze, reminders or a reminder time they chose.
     */
    fun hasPersonsMarks(copy: Copy): Boolean =
        copy.hasDocuments || hasOwnNote(copy.notes) || copy.isSnoozed || copy.remindersCustomized ||
            copy.hasOwnReminderTime

    /** A note the person wrote: anything but none or the declaration's own. */
    fun hasOwnNote(notes: String?): Boolean {
        val note = notes?.trim()
        if (note.isNullOrEmpty()) return false
        return note != rentalDeclaration.note?.trim()
    }

    /** Negative when [a] stays rather than [b] ([kept]'s order). */
    private fun order(a: Copy, b: Copy): Int {
        if (a.isFiled != b.isFiled) return if (a.isFiled) -1 else 1
        if (a.isFiled && a.dueDay != b.dueDay) return b.dueDay.compareTo(a.dueDay)
        val aMarked = hasPersonsMarks(a)
        if (aMarked != hasPersonsMarks(b)) return if (aMarked) -1 else 1
        if (a.isOpen != b.isOpen) return if (a.isOpen) -1 else 1
        if (a.dueDay != b.dueDay) return a.dueDay.compareTo(b.dueDay)
        // Swift's `uuidString`, in capitals, compared as text.
        return a.id.toString().uppercase().compareTo(b.id.toString().uppercase())
    }

    companion object {
        /** The rental income declaration's key. Part of the `.dosar` contract. */
        const val RENTAL_DECLARATION_KEY = "household.rentalDeclaration"
    }
}
