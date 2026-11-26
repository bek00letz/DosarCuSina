package com.ar.dosarcusina.core.reminders

import com.ar.dosarcusina.core.urgency.UrgencyVectors
import com.ar.dosarcusina.core.urgency.day
import com.ar.dosarcusina.core.urgency.dayOrNull
import com.ar.dosarcusina.core.urgency.deadline
import com.ar.dosarcusina.core.urgency.normalized
import com.ar.dosarcusina.core.urgency.obj
import com.ar.dosarcusina.core.urgency.objects
import com.ar.dosarcusina.core.urgency.triggerText
import com.ar.dosarcusina.core.urgency.written
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.long
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** When a deadline reminds and what the badge says, pinned against the iOS app's answers. Placeholder data only. */
class ReminderVectorsTest {
    @TestFactory
    fun `a reminder's time is a moment on the wall clock`(): List<DynamicTest> =
        UrgencyVectors.tests("reminder-clock", { label(it, "clamped", "day", "springForward") }) { case ->
            when {
                case.containsKey("clamped") -> assertEquals(case.int("is"), ReminderClock.clamped(case.int("clamped")))
                case.containsKey("springForward") -> {
                    val now = Instant.ofEpochSecond(case.long("now"))
                    val zone = ZoneId.of(case.text("zone"))
                    val found = ReminderClock.springForward(case.int("springForward"), now, zone)
                    if (case.isNull("skipped")) {
                        assertEquals(null, found)
                    } else {
                        val skipped = case.obj("skipped")
                        val expected = ReminderClock.SkippedTime(day(skipped.text("day")), skipped.int("remindsAt"))
                        assertEquals(expected, found)
                    }
                }
                else -> {
                    val zone = ZoneId.of(case.text("zone"))
                    val fire = ReminderClock.moment(day(case.text("day")), case.int("minute"), zone)
                    assertEquals(case.long("fireAt"), fire.epochSecond)
                    assertEquals(case.text("trigger"), triggerText(TriggerParts.of(fire, zone)))
                    assertEquals(case.int("minuteOfDay"), ReminderClock.minuteOfDay(fire, zone))
                }
            }
        }

    private fun planned(case: JsonObject, badges: Boolean): List<PlannedReminder> {
        val deadlines = case.objects("deadlines").map(::deadline)
        val now = Instant.ofEpochSecond(case.long("now"))
        val zone = ZoneId.of(case.text("zone"))
        val limit = case.int("limit")
        val plan = ReminderPlanner.plan(deadlines, now, zone, case.int("defaultMinuteOfDay"), limit)
        return if (badges) BadgePlanner.plan(plan, deadlines, now, zone, limit) else plan
    }

    /** What a reminder is for is what its identifier says, and its trigger is its moment's. */
    private fun checkCarried(reminder: PlannedReminder, zone: ZoneId) {
        val suffix = reminder.identifier.substringAfterLast('.')
        val expected = when {
            reminder.identifier == ReminderPlanner.CONTINUE_IDENTIFIER -> ReminderPurpose.CONTINUE
            reminder.identifier.startsWith(BadgePlanner.IDENTIFIER_PREFIX) -> ReminderPurpose.BADGE
            suffix == ReminderPlanner.LAPSE_SUFFIX -> ReminderPurpose.FOLLOW_UP
            suffix == ReminderPlanner.CATCH_UP_SUFFIX -> ReminderPurpose.CATCH_UP
            suffix == ReminderPlanner.SNOOZE_SUFFIX -> ReminderPurpose.SNOOZE
            suffix.startsWith("t") -> ReminderPurpose.TRAVEL_LEAD
            else -> ReminderPurpose.LEAD
        }
        assertEquals(expected, reminder.purpose, reminder.identifier)
        assertEquals(TriggerParts.of(reminder.fireAt, zone), reminder.trigger)
    }

    private fun checkPlan(case: JsonObject, badges: Boolean) {
        val plan = planned(case, badges)
        val expected = case.getValue("plan") as JsonArray
        assertEquals(normalized(expected), normalized(JsonArray(plan.map(::written))))
        plan.forEach { checkCarried(it, ZoneId.of(case.text("zone"))) }
        assertEquals(plan.size, plan.map { it.identifier }.toSet().size, "one reminder per identifier")
    }

    @TestFactory
    fun `the reminder plan is the iPhone's`(): List<DynamicTest> =
        UrgencyVectors.tests("reminder-plan", { it.text("name") }) { case -> checkPlan(case, badges = false) }

    @TestFactory
    fun `the badge travels with the reminders`(): List<DynamicTest> =
        UrgencyVectors.tests("badge-plan", { it.text("name") }) { case ->
            val deadlines = case.objects("deadlines").map(::deadline)
            for (count in case.objects("counts")) {
                val found = BadgePlanner.count(deadlines, day(count.text("day")))
                assertEquals(count.int("count"), found, count.toString())
            }
            checkPlan(case, badges = true)
        }

    @TestFactory
    fun `an identifier names its deadline and its cycle`(): List<DynamicTest> =
        UrgencyVectors.tests("reminder-identifiers", { label(it, "identifier", "made") }) { case ->
            if (case.containsKey("made")) {
                val made = ReminderIdentifiers.make(UUID.fromString(case.text("id")), case.text("suffix"))
                assertEquals(case.text("made"), made)
                return@tests
            }
            val identifier = case.text("identifier")
            assertEquals(case.textOrNull("obligationId"), ReminderIdentifiers.obligationId(identifier)?.toString())
            for (cycle in case.objects("cycles")) {
                val found = ReminderIdentifiers.cycle(identifier, day(cycle.text("deliveredOn")))
                assertEquals(cycle.dayOrNull("cycle"), found, cycle.toString())
            }
        }

    @TestFactory
    fun `a shown reminder goes when a pass wouldn't say it`(): List<DynamicTest> =
        UrgencyVectors.tests("shown-reminders", { it.text("identifier") }) { case ->
            val open = case.obj("openCycles")
                .mapKeys { UUID.fromString(it.key) }
                .mapValues { day(it.value.jsonPrimitive.content) }
            val locked = case.texts("locked").map(UUID::fromString).toSet()
            val shown = DeliveredReminder(
                identifier = case.text("identifier"),
                obligationId = case.textOrNull("obligationId")?.let(UUID::fromString),
                cycle = case.dayOrNull("cycle"),
                isProtected = case.bool("isProtected"),
            )
            assertEquals(case.bool("isOutdated"), ShownReminders.isOutdated(shown, open, locked))
        }

    @TestFactory
    fun `the open cycles and the locks are read from the same deadlines`(): List<DynamicTest> =
        UrgencyVectors.tests("reminder-plan", { it.text("name") }) { case ->
            val deadlines = case.objects("deadlines").map(::deadline)
            val open = ShownReminders.openCycles(deadlines)
            assertTrue(open.keys.all { id -> deadlines.any { it.id == id && it.status.stored == "active" } })
            assertEquals(deadlines.filter { it.isSensitive }.map { it.id }.toSet(), ShownReminders.locked(deadlines))
            // Every reminder the plan made for a deadline is about its open cycle.
            for (reminder in planned(case, badges = false)) {
                val id = reminder.obligationId ?: continue
                assertEquals(open[id], reminder.cycle)
            }
        }
}
