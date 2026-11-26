package com.ar.dosarcusina.store.examples

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.StepQuestion
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID

/**
 * Whether one of a category's sections is spoken of as feminine („mașina”) or not („actul”), as the iOS
 * app's `GrammaticalGender`.
 */
enum class GrammaticalGender(val raw: String) {
    FEMININE("feminine"),
    MASCULINE_OR_NEUTER("masculineOrNeuter"),
}

/**
 * The person added something of their own (a deadline, a document, a record of history, a reading, a
 * section) to an example section, as the iOS app's `ExampleSectionQuestion`. Nothing is saved: the
 * screen asks whether to keep [name] as the person's, worded by [gender], and on yes adopts the example
 * and saves again.
 */
class ExampleSectionQuestion(
    /** The topmost example the new thing would sit in: the one that becomes the person's. */
    val sectionId: UUID,
    val name: String,
    val gender: GrammaticalGender,
) : Exception("Something of the person's would go into an example"), StepQuestion

/**
 * Only the example loader makes examples. Anything the person adds is theirs, and it never lands inside
 * an example without the person saying so, as the iOS app's `ExampleOwnership`
 * (ios/DosarCuSina/Services/Examples/ExampleOwnership.swift): every action that makes a record asks here
 * before its unit of work opens.
 */
object ExampleOwnership {
    /** The topmost example a record under [asset] would sit in, if any. */
    fun exampleSection(view: BinderView, asset: Asset?): Asset? {
        var current = asset
        var topmost: Asset? = null
        val seen = HashSet<Long>()
        while (current != null && seen.add(current.pk)) {
            if (current.isExample) topmost = current
            current = current.parent?.let { view.row(Tables.assets, it) }
        }
        return topmost
    }

    /**
     * Whether the record about to be made under [asset] is an example: only when the example loader says
     * so ([creatingExample]). Throws [ExampleSectionQuestion] when it would be the person's own inside an
     * example. Changes nothing.
     */
    fun requireReal(view: BinderView, asset: Asset?, builtIns: BuiltIns, creatingExample: Boolean = false): Boolean {
        if (creatingExample) return true
        val section = exampleSection(view, asset) ?: return false
        throw ExampleSectionQuestion(section.id, section.name, gender(section.templateKey, builtIns))
    }

    /**
     * The gender of one section of a built-in category, as the category declares it (its `singular`):
     * only built-ins hold examples; any other reads as a thing („al tău”).
     */
    fun gender(templateKey: String, builtIns: BuiltIns): GrammaticalGender {
        val singular = builtIns.definition(templateKey)?.behavior?.singular as? JsonObject
        val raw = (singular?.get("gender") as? JsonPrimitive)?.takeIf { it.isString }?.content
        return GrammaticalGender.entries.firstOrNull { it.raw == raw } ?: GrammaticalGender.MASCULINE_OR_NEUTER
    }
}
