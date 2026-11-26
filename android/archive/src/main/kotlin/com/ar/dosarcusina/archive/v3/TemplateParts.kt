package com.ar.dosarcusina.archive.v3

import com.ar.dosarcusina.core.values.JsonCodec
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RomanianText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// What a category's definition holds, as the archive writes it (shared/schemas/dosar-v3.md,
// "Template"): its sections and fields, its deadlines, its parts and its behaviour. Each is read
// as the iOS app reads it, so what the importer decides (secret fields, choice keys, a category
// of one's own's name) reads the same values; the parts the importer only carries (a field's
// derivation, a deadline's first due date, its facts) are kept as written. A built-in's
// definition is the shared catalog's (`BuiltIns`), read with these same codecs.

/** A codec that reads with [read] (null, or [UnreadableRecord], when it can't) and writes with [write]. */
internal fun <T> codec(read: (JsonRecord) -> T, write: (T) -> JsonElement): JsonCodec<T> = object : JsonCodec<T> {
    override fun decode(json: JsonElement): T? = try {
        read(JsonRecord.of(json))
    } catch (_: UnreadableRecord) {
        null
    }

    override fun encode(value: T): JsonElement = write(value)
}

/** A condition on a section's value: `{"field": "document.type", "oneOf": [...], "orWhenEmpty": true}`. */
data class Condition(val field: String, val oneOf: List<String>, val orWhenEmpty: Boolean = false) {
    /** Whether [values] meet it, as the iOS app's `BlueprintCondition.isMet`. */
    fun isMet(values: FieldValues): Boolean = when (val value = values[field]) {
        null -> orWhenEmpty
        is FieldValue.Text -> value.value in oneOf
        is FieldValue.Choices -> value.value.any { it in oneOf }
        else -> false
    }

    companion object {
        /** The condition [json] holds, or null when this build can't read it (kept as written). */
        fun read(json: JsonElement): Condition? = codec.decode(json)

        val codec: JsonCodec<Condition> = codec(
            read = { Condition(it.string("field"), it.strings("oneOf"), it.boolOrNull("orWhenEmpty") ?: false) },
            write = { condition ->
                jsonObject {
                    put("field", condition.field)
                    putStrings("oneOf", condition.oneOf)
                    if (condition.orWhenEmpty) put("orWhenEmpty", true)
                }
            },
        )
    }
}

/** An option of a choice field: its key, its label, older spellings, and when it is offered. */
data class ChoiceOption(
    val key: String,
    val label: String,
    val aliases: List<String> = emptyList(),
    val appliesWhen: JsonElement? = null,
) {
    /** Whether [text] names it: its key, or its label or an alias without case or diacritics. */
    fun matches(text: String): Boolean {
        if (text == key) return true
        val needle = fold(text)
        return needle.isNotEmpty() && (listOf(label) + aliases).any { fold(it) == needle }
    }

    fun toJson(): JsonObject = jsonObject {
        put("key", key)
        put("label", label)
        if (aliases.isNotEmpty()) putStrings("aliases", aliases)
        put("appliesWhen", appliesWhen)
    }

    companion object {
        /** Folded, whitespace collapsed, signs kept ("A+" and "A-" stay apart). */
        private fun fold(text: String): String =
            RomanianText.fold(text).split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

        /** An option as stored, or a plain string as older definitions listed them (its key and label). */
        fun read(json: JsonElement): ChoiceOption {
            if (json is JsonPrimitive && json.isString) return ChoiceOption(json.content, json.content)
            val record = JsonRecord.of(json)
            return ChoiceOption(
                record.string("key"),
                record.string("label"),
                record.stringsOrNull("aliases").orEmpty(),
                record.element("appliesWhen"),
            )
        }
    }
}

/**
 * One field of a category, as the iOS app's `FieldDefinition`. A type or role a newer build
 * wrote is kept as written (and reads as `text`, no role); its default, derivation and
 * condition are kept as written too, read where the importer needs them ([condition]).
 */
data class FieldDefinition(
    val key: String,
    val label: String,
    val type: String,
    val role: String? = null,
    val isEssential: Boolean = false,
    val isSensitive: Boolean = false,
    val options: List<ChoiceOption>? = null,
    val unit: String? = null,
    val placeholder: String? = null,
    val defaultValue: JsonElement? = null,
    val derivation: JsonElement? = null,
    val appliesWhen: JsonElement? = null,
    val footnote: String? = null,
) {
    /** A code kept sealed on the phone and never carried out of it (a PIN). */
    val isSecret: Boolean get() = type == SECRET

    /** The condition it is shown and kept under; none when it has none, or this build can't read it. */
    val condition: Condition? get() = appliesWhen?.let(Condition::read)

    /** Whether the field belongs on a section with these values. */
    fun applies(values: FieldValues): Boolean = condition?.isMet(values) ?: true

    /**
     * The stored key for a choice value: a key stays, an option's label or alias gives its key, other text stays as
     * written.
     */
    fun choiceKey(text: String): String =
        (options?.firstOrNull { it.key == text } ?: options?.firstOrNull { it.matches(text) })?.key ?: text

    companion object {
        const val SECRET = "secret"
        const val CHOICE = "choice"
        const val MULTI_CHOICE = "multiChoice"

        val codec: JsonCodec<FieldDefinition> = codec(
            read = { record ->
                FieldDefinition(
                    key = record.string("key"),
                    label = record.string("label"),
                    type = record.string("type"),
                    role = record.stringOrNull("role"),
                    isEssential = record.boolOrNull("isEssential") ?: false,
                    isSensitive = record.boolOrNull("isSensitive") ?: false,
                    options = record.element("options")?.let { JsonRecord.list(it).map(ChoiceOption::read) },
                    unit = record.stringOrNull("unit"),
                    placeholder = record.stringOrNull("placeholder"),
                    defaultValue = record.element("defaultValue"),
                    derivation = record.element("derivation"),
                    appliesWhen = record.element("appliesWhen"),
                    footnote = record.stringOrNull("footnote"),
                )
            },
            write = { field ->
                jsonObject {
                    put("key", field.key)
                    put("label", field.label)
                    put("type", field.type)
                    put("role", field.role)
                    put("isEssential", field.isEssential)
                    put("isSensitive", field.isSensitive)
                    put("options", field.options?.let { options -> JsonArray(options.map(ChoiceOption::toJson)) })
                    put("unit", field.unit)
                    put("placeholder", field.placeholder)
                    put("defaultValue", field.defaultValue)
                    put("derivation", field.derivation)
                    put("appliesWhen", field.appliesWhen)
                    put("footnote", field.footnote)
                }
            },
        )
    }
}

/** A titled group of fields: `key`, `title`, `fields`. */
data class FieldSection(val key: String, val title: String, val fields: List<FieldDefinition>) {
    companion object {
        val codec: JsonCodec<FieldSection> = codec(
            read = { record ->
                val fields = record.list("fields").map { FieldDefinition.codec.decode(it) ?: throw UnreadableRecord() }
                FieldSection(record.string("key"), record.string("title"), fields)
            },
            write = { section ->
                jsonObject {
                    put("key", section.key)
                    put("title", section.title)
                    put("fields", JsonArray(section.fields.map(FieldDefinition.codec::encode)))
                }
            },
        )
    }
}

/** A part or job a category knows (front brake pads): `key`, `name`, `group`, `synonyms`. */
data class ComponentDefinition(
    val key: String,
    val name: String,
    val group: String = "",
    val synonyms: List<String> = emptyList(),
) {
    companion object {
        val codec: JsonCodec<ComponentDefinition> = codec(
            read = { ComponentDefinition(
                it.string("key"),
                it.string("name"),
                it.stringOrNull("group").orEmpty(),
                it.stringsOrNull("synonyms").orEmpty(),
            ) },
            write = { component ->
                jsonObject {
                    put("key", component.key)
                    put("name", component.name)
                    put("group", component.group)
                    putStrings("synonyms", component.synonyms)
                }
            },
        )
    }
}

/**
 * One of a category's usual deadlines, as the archive writes it: its key, title, kind and how
 * it completes; its recurrence, first due date, reminders and facts are kept as written (the
 * engines that read them come in Phase 3).
 */
data class ObligationBlueprint(
    val key: String,
    val title: String,
    val kind: String,
    val completion: String? = null,
    val recurrence: JsonElement? = null,
    val firstDue: JsonElement? = null,
    val reminders: JsonElement? = null,
    val reminderVariants: JsonElement? = null,
    val appliesWhen: JsonElement? = null,
    val estimatedCost: Money? = null,
    val isSuggested: Boolean = false,
    val note: String? = null,
    val facts: JsonElement? = null,
) {
    companion object {
        val codec: JsonCodec<ObligationBlueprint> = codec(
            read = { record ->
                ObligationBlueprint(
                    key = record.string("key"),
                    title = record.string("title"),
                    kind = record.string("kind"),
                    completion = record.stringOrNull("completion"),
                    recurrence = record.element("recurrence"),
                    firstDue = record.element("firstDue"),
                    reminders = record.element("reminders"),
                    reminderVariants = record.element("reminderVariants"),
                    appliesWhen = record.element("appliesWhen"),
                    estimatedCost = record.moneyOrNull("estimatedCost"),
                    isSuggested = record.boolOrNull("isSuggested") ?: false,
                    note = record.stringOrNull("note"),
                    facts = record.element("facts"),
                )
            },
            write = { blueprint ->
                jsonObject {
                    put("key", blueprint.key)
                    put("title", blueprint.title)
                    put("kind", blueprint.kind)
                    put("completion", blueprint.completion)
                    put("recurrence", blueprint.recurrence)
                    put("firstDue", blueprint.firstDue)
                    put("reminders", blueprint.reminders)
                    put("reminderVariants", blueprint.reminderVariants)
                    put("appliesWhen", blueprint.appliesWhen)
                    put("estimatedCost", blueprint.estimatedCost)
                    put("isSuggested", blueprint.isSuggested)
                    put("note", blueprint.note)
                    put("facts", blueprint.facts)
                }
            },
        )
    }
}

/**
 * What a category does in the binder (`behavior`), as the archive writes it: each key as
 * written, so one a newer build wrote reads as the default where it is used and goes out again
 * unchanged. [singular] is what one of its sections is called; a category of one's own has none.
 */
data class CategoryBehavior(
    val box: String? = null,
    val listing: String? = null,
    val role: String? = null,
    val parentPocket: String? = null,
    val addedOnlyUnderParent: Boolean? = null,
    val defaultGrouping: String? = null,
    val sectionNoun: String? = null,
    val mayBelongTo: String? = null,
    val goesUnderTheOnlyOne: Boolean? = null,
    val visit: JsonElement? = null,
    val offerTitle: String? = null,
    val shortlistOrder: Int? = null,
    val singular: JsonElement? = null,
) {
    /** Says nothing: the standard behaviour. */
    val isStandard: Boolean get() = this == CategoryBehavior()

    companion object {
        val codec: JsonCodec<CategoryBehavior> = codec(
            read = { record ->
                CategoryBehavior(
                    box = record.stringOrNull("box"),
                    listing = record.stringOrNull("listing"),
                    role = record.stringOrNull("role"),
                    parentPocket = record.stringOrNull("parentPocket"),
                    addedOnlyUnderParent = record.boolOrNull("addedOnlyUnderParent"),
                    defaultGrouping = record.stringOrNull("defaultGrouping"),
                    sectionNoun = record.stringOrNull("sectionNoun"),
                    mayBelongTo = record.stringOrNull("mayBelongTo"),
                    goesUnderTheOnlyOne = record.boolOrNull("goesUnderTheOnlyOne"),
                    visit = record.element("visit"),
                    offerTitle = record.stringOrNull("offerTitle"),
                    shortlistOrder = record.intOrNull("shortlistOrder"),
                    singular = record.element("singular"),
                )
            },
            write = { behavior ->
                jsonObject {
                    put("box", behavior.box)
                    put("listing", behavior.listing)
                    put("role", behavior.role)
                    put("parentPocket", behavior.parentPocket)
                    put("addedOnlyUnderParent", behavior.addedOnlyUnderParent)
                    put("defaultGrouping", behavior.defaultGrouping)
                    put("sectionNoun", behavior.sectionNoun)
                    put("mayBelongTo", behavior.mayBelongTo)
                    put("goesUnderTheOnlyOne", behavior.goesUnderTheOnlyOne)
                    put("visit", behavior.visit)
                    put("offerTitle", behavior.offerTitle)
                    put("shortlistOrder", behavior.shortlistOrder)
                    put("singular", behavior.singular)
                }
            },
        )
    }
}
