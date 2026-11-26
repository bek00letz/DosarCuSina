package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.reminders.PlannedReminder
import com.ar.dosarcusina.core.reminders.TriggerParts
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.ints
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/**
 * The urgency and reminder rules' answers, in shared/test-vectors/urgency/, by
 * ios/DosarCuSinaTests/UrgencyVectorsTests.swift.
 */
object UrgencyVectors : VectorFolder(
    folderName = "urgency",
    files = setOf(
        "badge-plan", "date-urgency", "reminder-clock", "reminder-identifiers", "reminder-lead", "reminder-plan",
        "reminder-profile", "shown-reminders", "stored-kinds", "urgency-rule",
    ),
    writtenBy = "the iOS UrgencyVectorsTests with TEST_RUNNER_URGENCY_VECTORS_WRITE=1",
)

fun day(text: String): CalendarDay = requireNotNull(CalendarDay.parse(text)) { "Not a day: $text" }

fun JsonObject.obj(key: String): JsonObject = getValue(key).jsonObject

fun JsonObject.objects(key: String): List<JsonObject> = getValue(key).jsonArray.map { it.jsonObject }

fun JsonObject.intOrNull(key: String): Int? = if (isNull(key)) null else int(key)

fun JsonObject.dayOrNull(key: String): CalendarDay? = textOrNull(key)?.let(::day)

/** A profile as a case gives it. */
fun profile(json: JsonObject): ReminderProfile = ReminderProfile(
    leadDays = json.ints("leadDays"),
    consequence = Consequence.stored(json.textOrNull("consequence")),
    graceDays = json.int("graceDays"),
    followUpAfterLapse = if (json.isNull("followUpAfterLapse")) null else json.bool("followUpAfterLapse"),
    travelMarginDays = json.int("travelMarginDays"),
)

/** A deadline as a case gives it: its reminders are its stored ones as the cycle that began on cycleStart uses them. */
fun deadline(json: JsonObject): DeadlineSnapshot {
    val due = day(json.text("dueDay"))
    return DeadlineSnapshot(
        id = UUID.fromString(json.text("id")),
        status = ObligationStatus.stored(json.textOrNull("status")),
        dueDay = due,
        snoozedUntil = json.dayOrNull("snoozedUntil"),
        reminders = profile(json.obj("reminders")).forCycle(json.dayOrNull("cycleStart"), due),
        reminderMinuteOfDay = json.intOrNull("reminderMinuteOfDay"),
        isSensitive = json.bool("isSensitive"),
        isExample = json.bool("isExample"),
        cycleKnownSince = json.intOrNull("cycleKnownSince")?.let { Instant.ofEpochSecond(it.toLong()) },
        closesInTheApp = json.bool("closesInTheApp"),
    )
}

fun written(rule: UrgencyRule): JsonObject = buildJsonObject {
    put("graceDays", rule.graceDays)
    put("firstLeadDays", rule.firstLeadDays)
    put("maxWindowDays", rule.maxWindowDays)
    put("travelMarginDays", rule.travelMarginDays)
}

fun written(profile: ReminderProfile): JsonObject = buildJsonObject {
    put("leadDays", kotlinx.serialization.json.JsonArray(profile.leadDays.map(::JsonPrimitive)))
    put("consequence", profile.consequence.stored)
    put("graceDays", profile.graceDays)
    put("followUpAfterLapse", profile.followUpAfterLapse)
    put("travelMarginDays", profile.travelMarginDays)
}

private fun nullable(value: Any?): JsonElement = when (value) {
    null -> JsonNull
    is Number -> JsonPrimitive(value)
    else -> JsonPrimitive(value.toString())
}

/** A planned reminder as the iOS case writes one: everything it carries but its words. */
fun written(reminder: PlannedReminder): JsonObject = buildJsonObject {
    val trigger = triggerText(reminder.trigger)
    put("identifier", reminder.identifier)
    put("obligationId", nullable(reminder.obligationId))
    put("cycle", nullable(reminder.cycle?.isoString))
    put("fireAt", reminder.fireAt.epochSecond)
    put("trigger", trigger)
    put("isTimeSensitive", reminder.isTimeSensitive)
    put("isProtected", reminder.isProtected)
    put("closesInTheApp", reminder.closesInTheApp)
    put("badge", nullable(reminder.badge))
    put("showsAlert", reminder.showsAlert)
}

/** Date parts as the iOS cases write them: `yyyy-MM-ddTHH:mm`. */
fun triggerText(parts: TriggerParts): String =
    String.format(Locale.ROOT, "%04d-%02d-%02dT%02d:%02d", parts.year, parts.month, parts.day, parts.hour, parts.minute)

/** The same JSON, numbers compared by their value. */
fun normalized(element: JsonElement): JsonElement = when (element) {
    is JsonObject -> JsonObject(element.mapValues { normalized(it.value) }.toSortedMap())
    is kotlinx.serialization.json.JsonArray -> kotlinx.serialization.json.JsonArray(element.map(::normalized))
    is JsonNull -> JsonNull
    is JsonPrimitive -> if (element.isString) element else JsonPrimitive(element.content)
}
