package com.ar.dosarcusina.store.schema

import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.DocumentFraming
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.JsonCodec
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.StoredDay
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

// The models' accessors for what they keep as JSON or as days, as the iOS models' are: the one
// way to read and write those columns. Each reads the value this build knows and keeps, beside
// it, what a newer build wrote that this one doesn't read (KeptObject, KeptList), so writing it
// again loses nothing. Never read or write those columns another way.

private fun <T> keptObject(text: String?, codec: JsonCodec<T>): KeptObject<T>? =
    text?.let(MachineText::parseOrNull)?.let { KeptObject.decode(it, codec) }

private fun <T> keptObject(text: String?, codec: JsonCodec<T>, fallback: T): KeptObject<T> =
    text?.let(MachineText::parseOrNull)?.let { KeptObject.read(it, codec, fallback) }
        ?: KeptObject.made(fallback, codec)

private fun <E> keptList(text: String?, codec: JsonCodec<E>, identity: (E) -> Any): KeptList<E> =
    KeptList.read(text?.let(MachineText::parseOrNull), codec, identity)

private fun json(element: JsonElement): String = MachineText.json(element)

/** A list's text, or none for an empty list that keeps nothing more. */
private fun <E> listText(list: KeptList<E>): String? =
    if (list.items.isEmpty() && list.isFullyRead) null else json(list.toJson())

private val noValues: FieldValues = requireNotNull(FieldValues.codec.decode(JsonObject(emptyMap())))

// Asset

/** The section's values as stored, with what this build doesn't read (`Asset.keptValues`). */
val Asset.keptValues: KeptObject<FieldValues>
    get() = keptObject(valuesData, FieldValues.codec, noValues)

fun Asset.withKeptValues(values: KeptObject<FieldValues>): Asset = copy(valuesData = json(values.json))

/** The rows under Date importante as stored (`Asset.keptFacts`). */
val Asset.keptFacts: KeptList<CustomFact>
    get() = keptList(customFactsData, CustomFact.codec, CustomFact::id)

fun Asset.withKeptFacts(facts: KeptList<CustomFact>): Asset = copy(customFactsData = listText(facts))

// Obligation

/** The day it is due; a deadline whose stored day can't be read is due on the day it was made. */
val Obligation.dueDay: CalendarDay?
    get() = StoredDay.day(dueDayISO)

/** The day its snooze ends. */
val Obligation.snoozedUntil: CalendarDay?
    get() = StoredDay.day(snoozedUntilISO)

/** How it repeats, as stored (`Obligation.keptRecurrence`): a rule this build can't read stays as written. */
val Obligation.keptRecurrence: KeptObject<RecurrenceRule>
    get() = keptObject(recurrenceData, RecurrenceRule.codec, RecurrenceRule.None)

fun Obligation.withKeptRecurrence(recurrence: KeptObject<RecurrenceRule>): Obligation =
    copy(recurrenceData = json(recurrence.json))

/** The reminders as the columns hold them. */
val Obligation.reminders: ReminderProfile
    get() = ReminderProfile(reminderLeadDays, consequenceRaw, graceDays, followUpAfterLapse, travelMarginDays)

/**
 * The reminders as stored (`Obligation.keptReminders`): the columns, with what a newer build
 * wrote beside them ([Obligation.remindersData]) laid under them.
 */
val Obligation.keptReminders: KeptObject<ReminderProfile>
    get() {
        val columns = reminders
        val stored = keptObject(remindersData, ReminderProfile.codec)
            ?: return KeptObject.made(columns, ReminderProfile.codec)
        return stored.replacingValue(columns)
    }

/**
 * The reminders written to their columns, and what they keep beyond them to
 * [Obligation.remindersData], only while there is some.
 */
fun Obligation.withKeptReminders(kept: KeptObject<ReminderProfile>): Obligation {
    val profile = kept.value
    return copy(
        reminderLeadDays = profile.leadDays,
        consequenceRaw = profile.consequence,
        graceDays = profile.graceDays,
        followUpAfterLapse = profile.followUpAfterLapse,
        travelMarginDays = profile.travelMarginDays,
        remindersData = if (kept.keepsMore) json(kept.json) else null,
    )
}

// Attachment

/** The day printed on the document. */
val Attachment.documentDay: CalendarDay?
    get() = StoredDay.day(documentDayISO)

/** The last day the document itself is valid. */
val Attachment.validUntil: CalendarDay?
    get() = StoredDay.day(validUntilISO)

/** How its pages are shown, as stored; none: every page as it is. */
val Attachment.keptFraming: KeptObject<DocumentFraming>?
    get() = keptObject(framingData, DocumentFraming.codec)

fun Attachment.withKeptFraming(framing: KeptObject<DocumentFraming>?): Attachment =
    copy(framingData = framing?.let { json(it.json) })

// CategoryTemplate

val CategoryTemplate.keptSections: KeptList<FieldSection>
    get() = keptList(sectionsData, FieldSection.codec, FieldSection::key)

val CategoryTemplate.keptBlueprints: KeptList<ObligationBlueprint>
    get() = keptList(blueprintsData, ObligationBlueprint.codec, ObligationBlueprint::key)

val CategoryTemplate.keptComponents: KeptList<ComponentDefinition>
    get() = keptList(componentsData, ComponentDefinition.codec, ComponentDefinition::key)

/** What the category does, as stored; none for the standard behaviour with nothing more. */
val CategoryTemplate.keptBehavior: KeptObject<CategoryBehavior>?
    get() = keptObject(behaviorData, CategoryBehavior.codec)

fun CategoryTemplate.withDefinition(
    sections: KeptList<FieldSection>,
    blueprints: KeptList<ObligationBlueprint>,
    components: KeptList<ComponentDefinition>,
    behavior: KeptObject<CategoryBehavior>?,
): CategoryTemplate = copy(
    sectionsData = json(sections.toJson()),
    blueprintsData = json(blueprints.toJson()),
    componentsData = json(components.toJson()),
    behaviorData = behavior?.let { json(it.json) },
)
