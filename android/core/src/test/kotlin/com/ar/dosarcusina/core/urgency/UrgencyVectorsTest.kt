package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.ints
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.io.File

/** How urgent a deadline is, pinned against the iOS app's answers. Placeholder data only. */
class UrgencyVectorsTest {
    private companion object {
        val KIND_KEYS = arrayOf("consequence", "storedConsequence", "storedStatus", "urgency")
    }

    @Test
    fun `every file in the folder is read`() {
        val present = UrgencyVectors.folder.listFiles { file: File -> file.extension == "json" }.orEmpty()
            .map { it.nameWithoutExtension }.toSet()
        assertEquals(UrgencyVectors.files, present)
    }

    @TestFactory
    fun `a lead of whole months is calendar months`(): List<DynamicTest> =
        UrgencyVectors.tests("reminder-lead", { label(it, "days", "bounded") }) { case ->
            if (case.containsKey("bounded")) {
                assertEquals(case.int("is"), ReminderLead.bounded(case.int("bounded")))
                return@tests
            }
            val lead = ReminderLead.of(case.int("days"))
            val expected = case.obj("lead")
            val made = when (lead) {
                is ReminderLead.Days -> mapOf("days" to lead.days)
                is ReminderLead.Months -> mapOf("months" to lead.months)
            }
            assertEquals(expected.mapValues { it.value.jsonPrimitive.content.toInt() }, made)
            for (before in case.objects("before")) {
                assertEquals(before.text("day"), lead.dayBefore(day(before.text("due"))).isoString, before.toString())
            }
        }

    @TestFactory
    fun `stored kinds read as the iPhone reads them`(): List<DynamicTest> =
        UrgencyVectors.tests("stored-kinds", { label(it, *KIND_KEYS) }) { case ->
            when {
                case.containsKey("storedConsequence") ->
                    assertEquals(case.text("reads"), Consequence.stored(case.textOrNull("storedConsequence")).stored)
                case.containsKey("storedStatus") ->
                    assertEquals(case.text("reads"), DeadlineStatus.stored(case.textOrNull("storedStatus")).stored)
                case.containsKey("urgency") -> {
                    val urgency = AttentionUrgency.entries.single { it.stored == case.text("urgency") }
                    assertEquals(case.int("order"), urgency.ordinal)
                    assertEquals(case.text("tone"), urgency.tone.stored)
                    assertEquals(case.bool("isAlarming"), urgency.isAlarming)
                    assertEquals(case.bool("needsAttentionNow"), urgency.needsAttentionNow)
                }
                else -> {
                    val consequence = Consequence.entries.single { it.stored == case.text("consequence") }
                    assertEquals(case.int("weight"), consequence.weight)
                    assertEquals(case.int("maxAttentionWindowDays"), consequence.maxAttentionWindowDays)
                    assertEquals(case.bool("allowsTimeSensitiveReminders"), consequence.allowsTimeSensitiveReminders)
                    assertEquals(case.bool("followsUpByDefault"), consequence.followsUpByDefault)
                }
            }
        }

    @Test
    fun `every consequence and urgency the iPhone has is here`() {
        val cases = UrgencyVectors.cases("stored-kinds")
        val consequences = cases.mapNotNull { it.textOrNull("consequence") }.toSet()
        val urgencies = cases.mapNotNull { it.textOrNull("urgency") }.toSet()
        assertEquals(consequences, Consequence.entries.map { it.stored }.toSet())
        assertEquals(urgencies, AttentionUrgency.entries.map { it.stored }.toSet())
    }

    @TestFactory
    fun `a profile holds its lengths and its cycle keeps the leads that fit`(): List<DynamicTest> =
        UrgencyVectors.tests("reminder-profile", { label(it, "cycle", "input") }) { case ->
            if (case.containsKey("cycle")) {
                val due = day(case.text("due"))
                val start = case.dayOrNull("cycleStart")
                assertEquals(case.ints("leadDays"), profile(case.obj("stored")).forCycle(start, due).leadDays)
                return@tests
            }
            val made = profile(case.obj("input"))
            assertEquals(normalized(case.obj("profile")), normalized(written(made)))
            assertEquals(normalized(case.obj("urgencyRule")), normalized(written(made.urgencyRule)))
            assertEquals(case.bool("hasTravelCutoff"), made.hasTravelCutoff)
        }

    @TestFactory
    fun `the urgency rule says what the iPhone says on every day`(): List<DynamicTest> =
        UrgencyVectors.tests("urgency-rule", { "${it.text("name")} ${it.text("due")}" }) { case ->
            val given = case.obj("rule")
            val rule = UrgencyRule(
                graceDays = given.int("graceDays"),
                firstLeadDays = given.int("firstLeadDays"),
                maxWindowDays = given.int("maxWindowDays"),
                travelMarginDays = given.int("travelMarginDays"),
            )
            val due = day(case.text("due"))
            assertEquals(case.textOrNull("travelCutoff"), rule.travelCutoff(due)?.isoString)
            assertEquals(case.text("reminderAnchor"), rule.reminderAnchor(due).isoString)
            assertEquals(case.text("attentionStart"), rule.attentionStart(due).isoString)
            assertEquals(case.int("windowDays"), rule.windowDays(due))

            val sweep = case.obj("sweep")
            val changes = mutableListOf<Pair<String, String>>()
            var today = day(sweep.text("from"))
            var previous: AttentionUrgency? = null
            while (today <= day(sweep.text("to"))) {
                val urgency = rule.urgency(due, today)
                if (urgency != previous) changes += today.isoString to urgency.stored
                previous = urgency
                today = today.addingDays(1)
            }
            assertEquals(sweep.objects("changes").map { it.text("from") to it.text("urgency") }, changes)
        }

    @TestFactory
    fun `a date on a page is as urgent as the deadline it drives`(): List<DynamicTest> =
        UrgencyVectors.tests("date-urgency", { "${it.text("name")} ${it.text("day")}" }) { case ->
            val deadlines = case.getValue("deadlines").jsonArray.map { deadline(it.jsonObject) }
            val rule = DateUrgency.rule(day(case.text("day")), deadlines)
            assertEquals(normalized(case.obj("rule")), normalized(written(rule)))
        }

    @Test
    fun `a rule without lengths is the one nothing reminds about`() {
        assertEquals(UrgencyRule.NO_REMINDERS, UrgencyRule(graceDays = -1, firstLeadDays = 0, maxWindowDays = -3))
    }
}
