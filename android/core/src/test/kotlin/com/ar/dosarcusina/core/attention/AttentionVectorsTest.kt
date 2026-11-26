package com.ar.dosarcusina.core.attention

import com.ar.dosarcusina.core.subscriptions.BillRecord
import com.ar.dosarcusina.core.subscriptions.BillWatch
import com.ar.dosarcusina.core.subscriptions.MissingBills
import com.ar.dosarcusina.core.subscriptions.interval
import com.ar.dosarcusina.core.subscriptions.money
import com.ar.dosarcusina.core.subscriptions.optionalText
import com.ar.dosarcusina.core.subscriptions.uuid
import com.ar.dosarcusina.core.urgency.day
import com.ar.dosarcusina.core.urgency.dayOrNull
import com.ar.dosarcusina.core.urgency.normalized
import com.ar.dosarcusina.core.urgency.obj
import com.ar.dosarcusina.core.urgency.objects
import com.ar.dosarcusina.core.urgency.profile
import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import java.io.File
import java.util.UUID
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/**
 * The attention list behind Urmează, the lines on the binder's boxes and heroes, a due line's data
 * and the calm notes of „Din timp”, pinned against the iOS app's answers. Placeholder data only.
 */
class AttentionVectorsTest {
    private companion object {
        /** The name the household's own group of „Curând” is ordered under, as the iOS cases write it. */
        const val UNASSIGNED = "Fără secțiune"
    }

    @Test
    fun `every file in the folder is read`() {
        val present = AttentionVectors.folder.listFiles { file: File -> file.extension == "json" }.orEmpty()
            .map { it.nameWithoutExtension }.toSet()
        assertEquals(AttentionVectors.files, present)
    }

    @TestFactory
    fun `one deadline as every surface sees it`(): List<DynamicTest> =
        AttentionVectors.tests("attention-entry", { "${it.obj("deadline").text("title")} on ${it.text("today")}" }) { case ->
            val entry = AttentionModel.entry(attentionDeadline(case.obj("deadline")), day(case.text("today")))
            assertEquals(normalized(case.obj("entry")), normalized(written(entry)))
        }

    @TestFactory
    fun `the list behind Urmeaza`(): List<DynamicTest> =
        AttentionVectors.tests("attention-digest", { label(it, "name") }) { case ->
            val deadlines = case.objects("deadlines").map(::attentionDeadline)
            val today = day(case.text("today"))
            val digest = AttentionModel.digest(deadlines, today, UNASSIGNED, AttentionModel.Limits(case.int("maxNow")))
            assertEquals(normalized(case.getValue("now")), normalized(JsonArray(digest.now.map(::written))), "Acum")
            val soon = digest.soon.map { group ->
                JsonObject(
                    mapOf(
                        "sectionId" to JsonPrimitive(group.sectionId?.toString()),
                        "sectionName" to JsonPrimitive(group.sectionName ?: UNASSIGNED),
                        "entries" to JsonArray(group.entries.map(::written)),
                    ),
                )
            }
            assertEquals(normalized(case.getValue("soon")), normalized(JsonArray(soon)), "Curând")
            val later = case.obj("later")
            assertEquals(later.int("count"), digest.later.count, "Mai târziu")
            assertEquals(later.dayOrNull("nextDay"), digest.later.nextDay)
            val costs = later.getValue("estimatedCost").jsonArray.map { it.money() }
            assertEquals(costs, digest.later.estimatedCost.amounts)
            assertEquals(case.int("overflowCount"), digest.overflowCount)
            assertEquals(case.int("hiddenCount"), digest.hiddenCount)
            assertEquals(case.int("needsActionCount"), digest.needsActionCount)
            assertEquals(case.bool("isAllClear"), digest.isAllClear)
            for (group in digest.soon) assertEquals(group.entries.first().deadline.dueDay, group.nextDay)
        }

    @TestFactory
    fun `the line under a box and on a hero`(): List<DynamicTest> =
        AttentionVectors.tests("box-status", { label(it, "name") }) { case ->
            val deadlines = case.objects("deadlines").map(::attentionDeadline)
            val sections = case.texts("sections").map(UUID::fromString).toSet()
            val status = BoxStatus.make(forSections = sections, deadlines = deadlines, today = day(case.text("today")))
            if (case.isNull("entry")) {
                assertNull(status.entry)
            } else {
                assertEquals(normalized(case.obj("entry")), normalized(written(checkNotNull(status.entry))))
            }
            assertEquals(case.bool("isAlarming"), status.isAlarming)
            assertEquals(case.text("urgencyTone"), status.urgencyTone.stored)
            for (line in case.objects("lines")) {
                val isSensitive = line.bool("isSensitive")
                val closed = line.bool("lockedSectionsClosed")
                val isLocked = { sectionIsSensitive: Boolean -> closed && sectionIsSensitive }
                val shows = line.bool("showsTitle")
                assertEquals(shows, status.showsTitle(isSensitive, isLocked), "showsTitle for $line")
                val expected = status.entry?.let { BoxLine.Pending(it, shows) } ?: BoxLine.AllGood
                assertEquals(expected, status.line(isSensitive, isLocked))
                if (!isSensitive) assertEquals(expected, status.heroLine(isLocked), "A hero's line is an open box's")
            }
            val counting = case["counting"]?.jsonObject ?: return@tests
            val noun = SectionNoun.of(counting.textOrNull("noun"))
            assertEquals(counting.textOrNull("noun"), noun?.raw)
            val counted = status.line(counting = counting.int("count"), noun = noun, isSensitive = false)
            assertEquals(CountedBoxLine(counting.int("count"), noun, status.line(isSensitive = false)), counted)
        }

    @TestFactory
    fun `a due line's verb, distance and day, and a passport's two lines`(): List<DynamicTest> =
        AttentionVectors.tests("due-line", { label(it, "kind", "due") + " on " + it.text("today") }) { case ->
            val today = day(case.text("today"))
            val due = day(case.text("due"))
            if (case.containsKey("kind")) {
                val line = DueLine.of(ObligationKind.stored(case.text("kind")), due, today)
                val expected = case.obj("line")
                assertEquals(expected.text("verb"), line.verb.name.lowercase())
                assertEquals(expected.bool("isLate"), line.isLate)
                assertEquals(expected.text("when"), line.whenDue.name.lowercase())
                assertEquals(expected.int("daysRemaining"), line.daysRemaining)
                assertEquals(DueDate(due, expected.bool("showsYear")), line.date)
                return@tests
            }
            val lines = TravelLines.of(due, profile(case.obj("reminders")).urgencyRule, today)
            if (case.isNull("travel")) {
                assertNull(lines)
                return@tests
            }
            val travel = case.obj("travel")
            val expected = travel["expired"]?.jsonObject?.let { TravelLines.Expired(dueDate(it)) }
                ?: travel.obj("valid").let {
                    val until = dueDate(it.obj("goodForTravelUntil"))
                    TravelLines.Valid(dueDate(it.obj("expiry")), until, it.bool("stillGoodForTravel"))
                }
            assertEquals(expected, lines)
        }

    @TestFactory
    fun `the calm notes of Din timp`(): List<DynamicTest> =
        AttentionVectors.tests("calm-notes", { label(it, "name") }) { case ->
            val watches = case.objects("subscriptions").map {
                BillWatch(
                    id = it.uuid("id"), service = it.optionalText("service"), cycle = it.getValue("cycle").interval(),
                    bills = it.texts("days").map { text -> BillRecord(day(text), null) },
                    isSensitive = it.bool("isSensitive"), isExample = it.bool("isExample"),
                )
            }
            val waiting = case.obj("suggestions")
            val topics = waiting.texts("topics")
            val notes = AttentionModel.calmNotes(
                MissingBills.find(watches, day(case.text("today"))),
                AttentionModel.suggestionNote(waiting.int("count"), topics),
            )
            val expected = case.objects("notes")
            assertEquals(expected.size, notes.size, "how many notes")
            val locked = watches.filter { it.isSensitive }.map { it.id }.toSet()
            for ((note, want) in notes.zip(expected)) {
                assertEquals(want.dayOrNull("expectedDay"), note.expectedDay)
                when (note) {
                    is CalmNote.Suggestions -> {
                        assertEquals("suggestions", (want.getValue("opens") as JsonPrimitive).content)
                        assertEquals(CalmNote.Suggestions(waiting.int("count"), topics), note)
                    }
                    is CalmNote.MissingBill -> {
                        assertEquals(want.obj("opens").uuid("section"), note.sectionId)
                        assertEquals(want.bool("isWeekly"), note.isWeekly)
                        assertEquals(want.int("monthsApart"), note.monthsApart)
                        assertEquals(note.sectionId in locked, note.isLocked)
                    }
                }
            }
            val afterBills = notes.dropWhile { it is CalmNote.MissingBill }
            assertTrue(afterBills.all { it is CalmNote.Suggestions }, "Suggestions go last")
        }

    private fun dueDate(json: JsonObject) = DueDate(day(json.text("day")), json.bool("showsYear"))
}
