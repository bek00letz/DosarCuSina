package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.BuiltInBlueprints
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.DocumentFields
import com.ar.dosarcusina.catalog.remindersFor
import com.ar.dosarcusina.core.deadlines.ObligationKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.obligations.DeadlineEdit
import com.ar.dosarcusina.store.obligations.DeadlineReminders
import com.ar.dosarcusina.store.obligations.LikelyDoubleCompletions
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.obligations.dueDay
import com.ar.dosarcusina.store.obligations.recurrence
import com.ar.dosarcusina.store.obligations.status
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import com.ar.dosarcusina.store.schema.withKeptReminders
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The repair steps over deadlines, as the iOS tests pin them (OutsideActionsTests'
 * `likelyDoubleCompletionsAreFoundNotChanged`, TravelCutoffTests' existing passports, DataRepairTests'
 * `aRenewalKeptRepeatingIsOffered`): each finds what it should and nothing else, changes nothing before
 * the owner says so, and applied once, finds nothing again.
 */
class DeadlineStepsTest {
    private fun binder(now: String = "2026-11-03"): TestBinderStore =
        TestBinderStore(now = noon(now)).also { it.launch.installBuiltIns(it.now) }

    private fun actions(binder: TestBinderStore) = ObligationActions(binder.unit, zone = { bucharest })

    private fun section(
        binder: TestBinderStore,
        category: String,
        name: String,
        vararg values: Pair<String, FieldValue>,
    ): Asset =
        binder.unit.performPrivate { step ->
            val made = step.insert(Asset(name = name, templateKey = category))
            made.with(*values).also(step::update)
        }

    private fun stored(binder: TestBinderStore, obligation: Obligation): Obligation =
        requireNotNull(binder.stored(Tables.obligations, obligation.pk))

    private fun deadline(binder: TestBinderStore, asset: Asset, key: String, firstDue: CalendarDay): Obligation {
        val blueprint = DeadlineReminders.blueprintsOf(binder.snapshot(), asset).first { it.key == key }
        return actions(binder).create(blueprint, asset, firstDue = firstDue)
    }

    @Test
    fun likelyDoubleCompletionsAreFoundNotChanged() {
        val binder = binder()
        val rent = actions(binder).create(
            title = "Chirie", kind = ObligationKind.PAYMENT, dueDay = CalendarDay(2026, 11, 5), asset = null,
            recurrence = RecurrenceRule.Interval(1, "month", "dueDate"),
        )
        actions(binder).complete(rent)
        binder.now = noon("2026-11-04")
        actions(binder).complete(rent)

        val found = LikelyDoubleCompletions.find(binder.snapshot(), bucharest)
        assertEquals(listOf(rent.id), found.map { it.obligationId })
        val latest = HistoryActions.history(binder.snapshot(), rent).first()
        assertEquals(latest.id, found.single().historyEntryId)
        assertEquals(2, HistoryActions.history(binder.snapshot(), rent).size, "Finding changes nothing")

        // Only with the person's OK, and safe to run twice.
        val candidate = found.single()
        assertTrue(binder.unit.perform { step -> LikelyDoubleCompletions.undoSecond(step, candidate, bucharest) })
        assertEquals(1, HistoryActions.history(binder.snapshot(), rent).size)
        assertEquals(CalendarDay(2026, 12, 5), stored(binder, rent).dueDay(bucharest))
        assertFalse(binder.unit.perform { step -> LikelyDoubleCompletions.undoSecond(step, candidate, bucharest) })
        assertEquals(1, HistoryActions.history(binder.snapshot(), rent).size)
        assertTrue(LikelyDoubleCompletions.find(binder.snapshot(), bucharest).isEmpty())
    }

    @Test
    fun theRepairListOffersADeadlineClosedTwice() {
        val binder = binder()
        val rent = actions(binder).create(
            title = "Chirie", kind = ObligationKind.PAYMENT, dueDay = CalendarDay(2026, 11, 5), asset = null,
            recurrence = RecurrenceRule.Interval(1, "month", "dueDate"),
        )
        actions(binder).complete(rent)
        binder.now = noon("2026-11-04")
        actions(binder).complete(rent)
        val found = applyTwice(binder, DataRepairStepId.DOUBLE_COMPLETIONS) {
            assertEquals(CalendarDay(2026, 12, 5), stored(binder, rent).dueDay(bucharest))
        }
        val subject = found.single().subject as DataRepairSubject.DoubleCompletion
        assertEquals("Chirie", subject.deadline)
        assertEquals("", subject.section, "A household deadline names no section")
    }

    private val expiry = CalendarDay(2027, 8, 12)

    private fun document(binder: TestBinderStore, name: String, type: String): Pair<Asset, Obligation> {
        val asset = section(
            binder, BuiltInTemplates.Key.DOCUMENTS, name,
            DOCUMENT_TYPE to FieldValue.Text(type), DocumentFields.EXPIRY to FieldValue.Day(expiry),
        )
        return asset to deadline(binder, asset, BuiltInBlueprints.DOCUMENT_RENEW, expiry)
    }

    private fun usual(binder: TestBinderStore, asset: Asset): ReminderProfile {
        val blueprint = DeadlineReminders.blueprintsOf(binder.snapshot(), asset)
            .first { it.key == BuiltInBlueprints.DOCUMENT_RENEW }
        return blueprint.remindersFor(binder.stored(asset).keptValues.value)
    }

    /** Writes [profile] on [obligation] around the unit of work, as an earlier version saved it. */
    private fun savedEarlier(
        binder: TestBinderStore,
        obligation: Obligation,
        profile: ReminderProfile,
        customized: Boolean = false,
    ) {
        val row = stored(binder, obligation)
        val written = row.withKeptReminders(KeptObject.made(profile, ReminderProfile.codec))
            .copy(remindersCustomized = customized)
        runBlocking { binder.store.database.obligations().update(written) }
    }

    @Test
    fun anExistingPassportGetsItsCutoffOnlyWithTheOwnersOK() {
        val binder = binder()
        val (passport, renewal) = document(binder, "Pașaport", PASSPORT)
        val (card, cardRenewal) = document(binder, "Carte de identitate", ID_CARD)
        val passportProfile = usual(binder, passport)
        assertEquals(passportProfile, stored(binder, renewal).reminders, "A new passport gets its cut-off at once")
        assertTrue(passportProfile.travelMarginDays > 0)

        // As an earlier version saved it: six and two months before the expiry, no cut-off.
        savedEarlier(binder, renewal, ReminderProfile(listOf(180, 60), "legal", followUpAfterLapse = false))
        val list = repairs(binder)
        val found = list.detect().filter { it.step == DataRepairStepId.TRAVEL_CUTOFF }
        assertEquals(1, found.size, "Only the passport, never the identity card")
        assertEquals(0, stored(binder, renewal).travelMarginDays, "Nothing changes before the owner says so")
        val subject = found.single().subject as DataRepairSubject.TravelCutoff
        assertEquals("Pașaport", subject.section)
        assertEquals(CalendarDay(2027, 2, 12), subject.cutoff)

        list.apply(found)
        assertEquals(passportProfile, stored(binder, renewal).reminders, "It takes the passport's reminders")
        assertEquals(usual(binder, card), stored(binder, cardRenewal).reminders)
        assertTrue(list.detect().none { it.step == DataRepairStepId.TRAVEL_CUTOFF }, "Applied once, not found again")
    }

    @Test
    fun theRepairChecksTheSameRuleAsEditing() {
        val binder = binder()
        val (card, cardRenewal) = document(binder, "Carte de identitate", ID_CARD)
        val (passport, own) = document(binder, "Pașaport", PASSPORT)
        // A card that was a passport before reminders followed the type: it kept the cut-off.
        savedEarlier(binder, cardRenewal, usual(binder, passport))
        // A passport whose reminders the person set before margins existed.
        savedEarlier(binder, own, ReminderProfile(listOf(200), "legal"), customized = true)

        val list = repairs(binder)
        val found = list.detect().filter { it.step == DataRepairStepId.TRAVEL_CUTOFF }
        assertEquals(2, found.size, "The card, and the passport the person set reminders on")
        list.apply(found)
        assertEquals(usual(binder, card), stored(binder, cardRenewal).reminders)
        val margin = usual(binder, passport).travelMarginDays
        assertEquals(ReminderProfile(listOf(200), "legal", travelMarginDays = margin), stored(binder, own).reminders,
            "The person's leads stay, now counted from the cut-off")
        assertTrue(stored(binder, own).remindersCustomized)
    }

    @Test
    fun aRenewalKeptRepeatingIsOffered() {
        val binder = binder()
        val file = section(binder, BuiltInTemplates.Key.HEALTH, "Fișa medicală")
        val day = CalendarDay(2027, 3, 1)
        val card = deadline(binder, file, BuiltInBlueprints.HEALTH_EU_CARD, day)
        val flu = deadline(binder, file, "health.flu", day)
        // As an earlier catalog made it.
        val repeating = stored(binder, card).let {
            val rule: RecurrenceRule = RecurrenceRule.Interval(2, "year", "completion")
            it.withKeptRecurrence(KeptObject.made(rule, RecurrenceRule.codec))
        }
        runBlocking { binder.store.database.obligations().update(repeating) }
        val view = binder.snapshot()
        assertFalse(DeadlineEdit.of(view, stored(binder, card), bucharest).offersRepeat,
            "Editează offers no repeat for a deadline that closes when done")

        val found = applyTwice(binder, DataRepairStepId.RENEWAL_REPEATS) {
            assertEquals(RecurrenceRule.None, stored(binder, card).recurrence)
            assertEquals(day, stored(binder, card).dueDay(bucharest))
            assertEquals(ObligationStatus.ACTIVE, stored(binder, card).status, "Only what its page says changes")
            assertTrue(stored(binder, flu).recurrence != RecurrenceRule.None, "A vaccine keeps repeating")
        }
        assertEquals(1, found.size)
        assertFalse(DataRepairs.step(DataRepairStepId.RENEWAL_REPEATS).isSuggestion, "A correction, not a suggestion")
    }

    private companion object {
        const val DOCUMENT_TYPE = "document.type"
        const val PASSPORT = "documentType.passport"
        const val ID_CARD = "documentType.idCard"
    }
}
