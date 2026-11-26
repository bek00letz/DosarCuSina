package com.ar.dosarcusina.store.templates

import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.HouseholdRules
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.LaunchData
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptReminders
import com.ar.dosarcusina.store.schema.withKeptReminders
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import java.time.ZoneId
import java.util.UUID

/**
 * The household's own deadlines: one rental income declaration while a tenancy exists, and when a
 * backup brought two copies, the same one kept whatever order they are read in, with everything the
 * other recorded. The iOS app's `HouseholdDeadlineCopiesTests` and `HouseholdTemplatesTests`, below
 * the screens. Every value is a placeholder.
 */
class HouseholdDeadlinesTest {
    private val then = noon("2026-06-01")
    private val binder = TestBinderStore(now = noon("2026-11-02"))
    private val rules = Catalog.builtIn.household
    private val bucharest = ZoneId.of("Europe/Bucharest")

    private val smaller = UUID.fromString("00000000-0000-4000-8000-000000000001")
    private val larger = UUID.fromString("00000000-0000-4000-8000-000000000002")

    private fun tenancy(isExample: Boolean = false): Asset = binder.unit.performPrivate { step ->
        step.insert(Asset(
            name = "Apartament Exemplu – chiriaș",
            templateKey = BuiltInTemplates.Key.TENANCY,
            isExample = isExample,
        ))
    }

    /** A copy of the declaration, saved as an import leaves it, with an old change time. */
    private fun declaration(
        id: UUID,
        due: String = "2027-05-25",
        change: (Obligation) -> Obligation = { it },
    ): Obligation {
        val blueprint = rules.rentalDeclaration
        val reminders = requireNotNull(blueprint.reminders?.let(ReminderProfile.codec::decode))
        return binder.unit.performPrivate { step ->
            step.insert(
                change(
                    Obligation(
                        id = id, title = blueprint.title, kindRaw = blueprint.kind, dueDayISO = due,
                        blueprintKey = blueprint.key, notes = blueprint.note, updatedAt = then,
                    ).withKeptReminders(KeptObject.made(reminders, ReminderProfile.codec)),
                ),
            )
        }
    }

    /** Files [copy]: a completion and the document filed with it, and its next cycle. */
    private fun file(copy: Obligation, nextDue: String): Attachment = binder.unit.performPrivate { step ->
        step.update(requireNotNull(step.row(Tables.obligations, copy.pk)).copy(dueDayISO = nextDue))
        step.insert(HistoryEntry(kindRaw = "completion", title = copy.title, obligation = copy.pk, updatedAt = then))
        step.insert(Attachment(
            fileName = "declaratia-unica.pdf",
            contentType = "com.adobe.pdf",
            obligation = copy.pk,
            updatedAt = then,
        ))
    }

    private fun declarations(): List<Obligation> =
        binder.snapshot().all(Tables.obligations).filter { it.blueprintKey == HouseholdRules.RENTAL_DECLARATION_KEY }

    private fun reconcile(today: String, whole: Boolean = true): Boolean =
        binder.unit.perform(ChangeOrigin.APP, noon(today)) { step ->
            HouseholdDeadlines(
                rules,
                bucharest,
            ).reconcile(step, requireNotNull(CalendarDay.parse(today)), noon(today), whole)
        }

    @Test
    fun whileATenancyExistsThereIsExactlyOneDeclaration() {
        val launch = binder.launch
        assertFalse(launch.reconcileHouseholdRules(binder.now), "No tenancy, no declaration")
        val first = tenancy()
        tenancy()
        assertTrue(launch.reconcileHouseholdRules(binder.now))
        assertFalse(launch.reconcileHouseholdRules(binder.now), "Once")
        val declaration = declarations().single()
        assertNull(declaration.asset, "It belongs to the household, not to one property")
        assertEquals("2027-05-25", declaration.dueDayISO)
        assertEquals(
            ReminderProfile(listOf(30, 7), "legal", followUpAfterLapse = true),
            declaration.keptReminders.value,
        )
        assertEquals(rules.rentalDeclaration.note, declaration.notes)
        assertEquals(binder.now, declaration.updatedAt, "Made now, by the app's own step")

        binder.unit.perform { it.delete(requireNotNull(it.row(Tables.assets, first.pk))) }
        launch.reconcileHouseholdRules(binder.now)
        assertEquals(1, declarations().size)
        binder.unit.perform { step -> step.all(Tables.assets).forEach(step::delete) }
        assertTrue(launch.reconcileHouseholdRules(binder.now))
        assertTrue(declarations().isEmpty())
    }

    @Test
    fun oneWithSomethingOfThePersonsOnItStaysAfterTheLastTenancy() {
        val declaration = declaration(smaller)
        file(declaration, "2028-05-25")
        assertFalse(reconcile("2027-06-01"))
        assertEquals(listOf(smaller), declarations().map { it.id }, "The income it declares is still due")
    }

    @Test
    fun examplesOnlyMakeAnExampleDeclarationAndOneRealTenancyMakesItReal() {
        tenancy(isExample = true)
        reconcile("2026-11-02")
        assertTrue(declarations().single().isExample)
        tenancy()
        assertTrue(reconcile("2026-11-02"))
        assertFalse(declarations().single().isExample)
    }

    @ParameterizedTest
    @CsvSource("true,true", "true,false", "false,true", "false,false")
    fun theFiledCopyStaysWithItsCompletionAndItsDocumentInAnyOrder(filedHasSmallerID: Boolean, filedFirst: Boolean) {
        tenancy()
        val (filedID, dueID) = if (filedHasSmallerID) smaller to larger else larger to smaller
        val (filed, _) = if (filedFirst) {
            declaration(filedID) to declaration(dueID)
        } else {
            declaration(dueID).let { due -> declaration(filedID) to due }
        }
        val document = file(filed, "2028-05-25")

        assertTrue(reconcile("2027-05-12"))

        val kept = declarations().single()
        assertEquals(filedID, kept.id, "The declaration already filed is kept, so no reminder comes back for it")
        assertEquals("2028-05-25", kept.dueDayISO)
        assertEquals(
            1,
            binder.snapshot().all(Tables.history).count { it.obligation == kept.pk },
            "Its completion stays",
        )
        assertEquals(kept.pk, binder.stored(document).obligation)
        assertEquals(then, kept.updatedAt, "Keeping one copy is the app's own step: no new change time")
    }

    @Test
    fun whatTheCopyThatGoesRecordedMovesOntoTheOneThatStays() {
        tenancy()
        val filed = declaration(smaller)
        val due = declaration(larger) { it.copy(notes = "Chiriașul a plătit în avans.") }
        file(filed, "2028-05-25")
        val receipt = binder.unit.performPrivate { step ->
            step.insert(Attachment(
                fileName = "recipisa.pdf",
                contentType = "com.adobe.pdf",
                obligation = due.pk,
                updatedAt = then,
            ))
        }

        reconcile("2027-05-12")

        val kept = declarations().single()
        assertEquals(smaller, kept.id, "The filed copy stays")
        assertEquals(kept.pk, binder.stored(receipt).obligation)
        assertEquals(then, binder.stored(receipt).updatedAt, "Moved by the app's own step: it keeps its change time")
        assertEquals(2, binder.snapshot().all(Tables.attachments).size, "No document goes with the copy")
        assertEquals(
            "Chiriașul a plătit în avans.",
            kept.notes,
            "What the person wrote comes over where the kept copy has none",
        )
    }

    @ParameterizedTest
    @CsvSource("true", "false")
    fun copiesJustAsFarOnKeepTheSmallestIdOnEveryPhone(smallerFirst: Boolean) {
        tenancy()
        for (id in if (smallerFirst) listOf(smaller, larger) else listOf(larger, smaller)) declaration(id)
        reconcile("2026-11-10")
        assertEquals(listOf(smaller), declarations().map { it.id })
    }

    @ParameterizedTest
    @CsvSource("true,true", "true,false", "false,true", "false,false")
    fun theOverdueCopyThePersonWorkedOnStaysWithItsNoteRemindersAndSnooze(
        overdueHasSmallerID: Boolean,
        overdueFirst: Boolean,
    ) {
        tenancy()
        val (overdueID, freshID) = if (overdueHasSmallerID) smaller to larger else larger to smaller
        fun overdue() = declaration(overdueID, due = "2026-05-25") { copy ->
            copy.withKeptReminders(copy.keptReminders.replacingValue(ReminderProfile(listOf(14), "legal")))
                .copy(
                    notes = "Am cerut adeverința de la bancă.",
                    remindersCustomized = true,
                    snoozedUntilISO = "2026-06-05",
                )
        }
        if (overdueFirst) overdue()
        declaration(freshID)
        if (!overdueFirst) overdue()

        reconcile("2026-06-01")

        val stays = declarations().single()
        assertEquals(overdueID, stays.id, "The copy the person was working on stays")
        assertEquals("2026-05-25", stays.dueDayISO, "Still overdue: the fresh copy's later day never hides it")
        assertEquals("Am cerut adeverința de la bancă.", stays.notes)
        assertEquals(listOf(14), stays.reminderLeadDays)
        assertEquals("2026-06-05", stays.snoozedUntilISO)
    }

    @Test
    fun ofTwoCopiesNobodyTouchedTheOneOpenEarliestStays() {
        tenancy()
        declaration(smaller)
        declaration(larger, due = "2026-05-25")
        reconcile("2026-06-01")
        assertEquals(listOf(larger), declarations().map { it.id })
    }

    @Test
    fun theRemindersThePersonChoseComeOverWhenTheKeptCopyHasNone() {
        tenancy()
        val filed = declaration(smaller)
        declaration(larger) { copy ->
            copy.withKeptReminders(copy.keptReminders.replacingValue(ReminderProfile(listOf(10), "legal")))
                .copy(remindersCustomized = true, reminderMinuteOfDay = 540)
        }
        file(filed, "2028-05-25")
        reconcile("2027-05-12")
        val kept = declarations().single()
        assertEquals(smaller, kept.id)
        assertTrue(kept.remindersCustomized)
        assertEquals(listOf(10), kept.reminderLeadDays)
        assertEquals(540, kept.reminderMinuteOfDay)
    }

    @Test
    fun nothingIsMadeOrJoinedOrRemovedWhileTheBinderIsArriving() {
        tenancy()
        assertFalse(reconcile("2026-11-10", whole = false), "The person's own may be on its way")
        assertTrue(declarations().isEmpty())
        declaration(smaller)
        declaration(larger)
        reconcile("2026-11-10", whole = false)
        assertEquals(2, declarations().size, "A completion may still be on its way")
        assertTrue(reconcile("2026-11-10"))
        assertEquals(1, declarations().size, "Joined once all of it has come")
    }

    @Test
    fun copiesOfOneRecordAreLeftToTheCopyRule() {
        tenancy()
        declaration(smaller)
        declaration(smaller)
        reconcile("2026-11-10")
        assertEquals(
            2,
            declarations().size,
            "The household rules can't tell them apart, so each phone would keep its own",
        )
    }

    @Test
    fun theStepComesLastAtLaunch() {
        assertEquals(LaunchData.LaunchStep.HOUSEHOLD_DEADLINES, LaunchData.LaunchStep.entries.last())
        tenancy()
        assertEquals(emptyList<LaunchData.LaunchStep>(), binder.launch.prepare(binder.now))
        assertEquals(1, declarations().size)
    }
}
