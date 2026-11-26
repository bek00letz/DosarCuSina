package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.BuiltInBlueprints
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.history.cycleDueDay
import com.ar.dosarcusina.store.history.nextDueDay
import com.ar.dosarcusina.store.readings.LowerReadingAsked
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.schema.snoozedUntil
import com.ar.dosarcusina.store.schema.withKeptValues
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

/**
 * The iOS app's answers for what every deadline action leaves in the binder, the reminders that follow a
 * section, and deadlines closed twice (shared/test-vectors/deadlines/, written by
 * ios/DosarCuSinaTests/DeadlineVectorsTests.swift), run through this store's own actions on the real Room
 * store: each case's section and deadline are made, its earlier actions taken, then its action, and the
 * deadline, its history, the section's readings and what undo brings back must be the iOS app's.
 */
class DeadlineVectorsTest {
    private fun cases(name: String): List<JsonObject> {
        val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
        val file = File(shared, "test-vectors/deadlines/$name.json")
        check(file.isFile) {
            "${file.path} is missing: run the iOS DeadlineVectorsTests with TEST_RUNNER_DEADLINE_VECTORS_WRITE=1"
        }
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content

    private fun JsonObject.textOrNull(key: String): String? =
        this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

    private fun JsonObject.obj(key: String): JsonObject? = this[key]?.takeUnless { it is JsonNull }?.jsonObject

    private fun JsonObject.dayOrNull(key: String): CalendarDay? = textOrNull(key)?.let(CalendarDay::parse)

    private fun JsonObject.intOrNull(key: String): Int? = textOrNull(key)?.toInt()

    private fun JsonObject.doubleOrNull(key: String): Double? = textOrNull(key)?.toDouble()

    private fun day(text: String): CalendarDay = requireNotNull(CalendarDay.parse(text))

    private fun rule(json: JsonElement): RecurrenceRule = requireNotNull(RecurrenceRule.codec.decode(json))

    private fun profile(json: JsonElement): ReminderProfile = requireNotNull(ReminderProfile.codec.decode(json))

    private fun money(json: JsonElement?): Money? = json?.takeUnless { it is JsonNull }?.let(Money::fromJson)

    private fun values(json: JsonElement?): FieldValues =
        json?.let { requireNotNull(FieldValues.codec.decode(it)) } ?: FieldValues()

    private fun seconds(instant: Instant): Long = instant.epochSecond

    // The binder a case starts from

    private class Made(val binder: TestBinderStore, val actions: ObligationActions, val obligation: Obligation)

    private fun make(case: JsonObject): Made {
        val binder = TestBinderStore(now = Instant.ofEpochSecond(case.text("now").toLong()))
        binder.launch.installBuiltIns(binder.now)
        val actions = ObligationActions(binder.unit, zone = { bucharest })
        val section = case.obj("section")?.let { section(binder, it) }
        val start = case.getValue("start").jsonObject
        val obligation = when (val key = start.textOrNull("blueprint")) {
            null -> actions.create(
                title = start.text("title"),
                kind = ObligationKind.stored(start.text("kind")),
                dueDay = day(start.text("dueDay")),
                asset = section,
                recurrence = rule(start.getValue("recurrence")),
                reminders = start["reminders"]?.takeUnless { it is JsonNull }?.let(::profile),
            )
            else -> {
                val asset = requireNotNull(section) { "A blueprint's deadline is in a section" }
                val blueprints = DeadlineReminders.blueprintsOf(binder.snapshot(), asset)
                actions.create(blueprints.first { it.key == key }, asset, firstDue = day(start.text("firstDue")))
            }
        }
        return Made(binder, actions, obligation)
    }

    private fun section(binder: TestBinderStore, json: JsonObject): Asset = binder.unit.performPrivate { step ->
        val asset = step.insert(Asset(name = json.text("name"), templateKey = json.text("category")))
        val valued = asset.withKeptValues(KeptObject.made(values(json["values"]), FieldValues.codec))
        step.update(valued)
        for (item in json.getValue("readings").jsonArray) {
            val reading = item.jsonObject
            step.insert(
                MeasurementLog(
                    kindRaw = "odometer", value = reading.text("value").toDouble(), unit = "km",
                    recordedAt = requireNotNull(MachineText.moment(reading.text("at"))), asset = asset.pk,
                ),
            )
        }
        valued
    }

    /** Runs [action] on [made]'s deadline; its receipt when it gives one. */
    private fun run(made: Made, action: JsonObject): UndoReceipt? {
        val actions = made.actions
        val deadline = made.obligation
        return when (val name = action.text("do")) {
            "complete" -> actions.complete(
                deadline,
                on = action.textOrNull("on")?.toLong()?.let(Instant::ofEpochSecond),
                cost = money(action["cost"]),
                metricReading = action.doubleOrNull("metricReading"),
                note = action.textOrNull("note"),
                rating = action.intOrNull("rating"),
                cycle = action.dayOrNull("cycle"),
                continuingOn = action.dayOrNull("continuingOn"),
            ).receipt
            "snooze" -> actions.snooze(deadline, action.intOrNull("days") ?: 0)
            "clearSnooze" -> actions.clearSnooze(deadline)
            "reschedule" -> actions.reschedule(deadline, day(action.text("day")))
            "pause" -> actions.pause(deadline)
            "resume" -> actions.resume(deadline)
            "archive" -> actions.archive(deadline)
            "delete" -> actions.delete(deadline)
            "setRecurrence" -> actions.setRecurrence(
                deadline, rule(action.getValue("rule")), action["startedFrom"]?.let(::rule),
            )
            "setReminders" -> {
                val startedFrom = action["startedFrom"]?.let(::profile)
                actions.setReminders(deadline, profile(action.getValue("reminders")), startedFrom)
                null
            }
            "setFollowUpAfterLapse" -> {
                actions.setFollowUpAfterLapse(deadline, action.text("isOn").toBooleanStrict())
                null
            }
            "restoreUsualReminders" -> actions.restoreUsualReminders(deadline)?.receipt
            "setReminderTime" ->
                actions.setReminderTime(deadline, action.intOrNull("minuteOfDay"), action.intOrNull("startedFrom"))
            "rename" -> actions.rename(deadline, action.textOrNull("title").orEmpty(), action.textOrNull("startedFrom"))
            "setImportance" -> actions.setImportance(
                deadline, importance(action.text("importance")), action.textOrNull("startedFrom")?.let(::importance),
            )
            "setDetails" -> {
                actions.setDetails(deadline, money(action["estimatedCost"]), action.textOrNull("reference"))
                null
            }
            "edit" -> edit(made, action)
            else -> error("No action $name")
        }
    }

    private fun importance(raw: String): DeadlineChoice.Importance =
        DeadlineChoice.Importance.entries.first { it.raw == raw }

    private fun edit(made: Made, action: JsonObject): UndoReceipt? {
        val view = made.binder.snapshot()
        val stored = requireNotNull(view.row(Tables.obligations, made.obligation.pk))
        val start = DeadlineEdit.of(view, stored, bucharest)
        var edited = start
        action.textOrNull("title")?.let { edited = edited.copy(title = it) }
        action.textOrNull("importance")?.let { edited = edited.choosing(importance(it)) }
        action.dayOrNull("dueDay")?.let { edited = edited.copy(dueDay = it) }
        action["recurrence"]?.let { edited = edited.copy(recurrence = rule(it)) }
        action["leadDays"]?.let { leads ->
            val days = leads.jsonArray.map { it.jsonPrimitive.content.toInt() }
            edited = edited.copy(reminders = edited.reminders.withLeadDays(days))
        }
        if ("reminderMinuteOfDay" in action) {
            edited = edited.copy(reminderMinuteOfDay = action.intOrNull("reminderMinuteOfDay"))
        }
        return made.actions.edit(made.obligation, edited, start)
    }

    private fun refusal(error: Throwable): String = when (error) {
        is ObligationActionError -> error::class.simpleName.orEmpty().replaceFirstChar { it.lowercase() }
        is LowerReadingAsked -> "lowerReading"
        else -> throw error
    }

    // What a case compares

    /** A deadline as stored, its rule and reminders read as objects (the iOS JSON is the same rule). */
    private data class Deadline(
        val title: String, val kind: String, val dueDay: CalendarDay?, val dueMetric: Double?, val status: String,
        val snoozedUntil: CalendarDay?, val recurrence: RecurrenceRule, val reminders: ReminderProfile,
        val reminderMinuteOfDay: Int?, val remindersCustomized: Boolean, val blueprintKey: String?,
        val reference: String?, val estimatedCost: Pair<BigDecimal, String>?,
    )

    private fun deadline(json: JsonObject?): Deadline? = json?.let {
        Deadline(
            it.text("title"), it.text("kind"), it.dayOrNull("dueDay"), it.doubleOrNull("dueMetric"), it.text("status"),
            it.dayOrNull("snoozedUntil"), rule(it.getValue("recurrence")), profile(it.getValue("reminders")),
            it.intOrNull("reminderMinuteOfDay"), it.text("remindersCustomized").toBooleanStrict(),
            it.textOrNull("blueprintKey"),
            it.textOrNull("reference"), money(it["estimatedCost"])?.let { cost -> cost.amount to cost.currency },
        )
    }

    private fun deadline(made: Made): Deadline? {
        val row = made.binder.snapshot().all(Tables.obligations)
            .firstOrNull { it.id == made.obligation.id } ?: return null
        return Deadline(
            row.title, row.kindRaw, row.dueDay(bucharest), row.dueMetric, row.statusRaw, row.snoozedUntil,
            row.recurrence,
            row.reminders, row.reminderMinuteOfDay, row.remindersCustomized, row.blueprintKey, row.reference,
            row.estimatedCostAmount?.let { Money(it, row.estimatedCostCurrency ?: Money.DEFAULT_CURRENCY) }
                ?.let { it.amount to it.currency },
        )
    }

    /** A record of history, as a case writes it. */
    private data class Record(
        val kind: String, val title: String, val occurredAt: Long, val cycleDueDay: CalendarDay?,
        val nextDueDay: CalendarDay?,
        val previousStatus: String?, val previousDueMetric: Double?, val cost: Pair<BigDecimal, String>?,
        val metricReading: Double?, val note: String?, val rating: Int?, val hasDeadline: Boolean,
    )

    private fun records(json: JsonElement): List<Record> = json.jsonArray.map { item ->
        val it = item.jsonObject
        Record(
            it.text("kind"), it.text("title"), it.text("occurredAt").toLong(), it.dayOrNull("cycleDueDay"),
            it.dayOrNull("nextDueDay"), it.textOrNull("previousStatus"), it.doubleOrNull("previousDueMetric"),
            money(it["cost"])?.let { cost -> cost.amount to cost.currency }, it.doubleOrNull("metricReading"),
            it.textOrNull("note"), it.intOrNull("rating"), it.text("hasDeadline").toBooleanStrict(),
        )
    }

    private fun records(made: Made): List<Record> =
        made.binder.snapshot().all(Tables.history)
            .sortedWith(compareBy({ it.cycleDueDay ?: CalendarDay.EARLIEST }, { it.occurredAt }))
            .map {
                Record(
                    it.kindRaw, it.title, seconds(it.occurredAt), it.cycleDueDay, it.nextDueDay, it.previousStatusRaw,
                    it.previousDueMetric,
                    it.totalCostAmount?.let { amount -> Money(amount, it.totalCostCurrency ?: Money.DEFAULT_CURRENCY) }
                        ?.let { cost -> cost.amount to cost.currency },
                    it.metricReading, it.note, it.rating, it.obligation != null,
                )
            }

    private fun readings(made: Made): List<Triple<Long, Double, String>> =
        made.binder.snapshot().all(Tables.readings)
            .sortedWith(compareBy({ it.recordedAt }, { it.value }))
            .map { Triple(seconds(it.recordedAt), it.value, it.unit) }

    private fun readings(json: JsonElement): List<Triple<Long, Double, String>> = json.jsonArray.map { item ->
        val it = item.jsonObject
        Triple(it.text("at").toLong(), it.text("value").toDouble(), it.text("unit"))
    }

    @TestFactory
    fun actions(): List<DynamicTest> = cases("actions").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val made = make(case)
            for (step in case.getValue("before").jsonArray) run(made, step.jsonObject)
            val before = deadline(made)
            val historyBefore = records(made)
            var refused: String? = null
            var receipt: UndoReceipt? = null
            try {
                receipt = run(made, case.getValue("action").jsonObject)
            } catch (error: Exception) {
                refused = refusal(error)
            }
            assertEquals(case.textOrNull("refused"), refused, "What the step refused")
            assertEquals(deadline(case.obj("deadline")), deadline(made), "The deadline after it")
            assertEquals(records(case.getValue("history")), records(made), "The history after it")
            assertEquals(readings(case.getValue("readings")), readings(made), "The section's readings after it")
            val undoes = case["undoRestores"]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content
                ?.toBooleanStrict()
            val gives = case.text("receipt").toBooleanStrict()
            assertEquals(gives, receipt != null, "A receipt where the iOS action gives one")
            assertEquals(case.text("canUndo").toBooleanStrict(), receipt?.canUndo ?: false, "Something to take back")
            if (receipt != null && receipt.canUndo) {
                receipt.undo()
                assertEquals(undoes, deadline(made) == before && records(made) == historyBefore, "What undo gives back")
            }
        }
    }

    @TestFactory
    fun remindersFollow(): List<DynamicTest> = cases("reminders-follow").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val binder = TestBinderStore()
            binder.launch.installBuiltIns(binder.now)
            val actions = ObligationActions(binder.unit, zone = { bucharest })
            val asset = binder.unit.performPrivate { step ->
                val made = step.insert(Asset(name = "Act", templateKey = BuiltInTemplates.Key.DOCUMENTS))
                made.withKeptValues(KeptObject.made(values(case["from"]), FieldValues.codec)).also(step::update)
            }
            val blueprints = DeadlineReminders.blueprintsOf(binder.snapshot(), asset)
            val renewal = blueprints.first { it.key == BuiltInBlueprints.DOCUMENT_RENEW }
            val obligation = actions.create(renewal, asset, firstDue = CalendarDay(2027, 8, 12))
            case["setByThePerson"]?.takeUnless { it is JsonNull }?.let { leads ->
                val stored = requireNotNull(binder.stored(Tables.obligations, obligation.pk))
                val days = leads.jsonArray.map { it.jsonPrimitive.content.toInt() }
                actions.setReminders(obligation, stored.reminders.withLeadDays(days))
            }
            val previous = binder.stored(asset).keptValues.value
            val changed = binder.unit.perform { step ->
                val current = requireNotNull(step.row(Tables.assets, asset.pk))
                step.update(current.withKeptValues(current.keptValues.replacingValue(values(case["to"]))))
                DeadlineReminders.follow(step, current, blueprints, previous)
            }
            val after = requireNotNull(binder.stored(Tables.obligations, obligation.pk))
            assertEquals(case.text("changed").toInt(), changed.size)
            assertEquals(profile(case.getValue("reminders")), after.reminders)
            assertEquals(case.text("remindersCustomized").toBooleanStrict(), after.remindersCustomized)
        }
    }

    @TestFactory
    fun doubleCompletions(): List<DynamicTest> = cases("double-completions").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            fun completion(json: JsonObject) = LikelyDoubleCompletions.Completion(
                UUID.randomUUID(), Instant.ofEpochSecond(json.text("occurredAt").toLong()),
                json.dayOrNull("cycle"), json.dayOrNull("next"),
            )
            val latest = completion(requireNotNull(case.obj("latest")))
            val previous = completion(requireNotNull(case.obj("previous")))
            val likely = LikelyDoubleCompletions.isLikely(latest, previous, bucharest)
            assertEquals(case.text("isLikely").toBooleanStrict(), likely)
        }
    }
}
