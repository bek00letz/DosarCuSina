package com.ar.dosarcusina.store.learning

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.locks.BinderLocks
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.IssuerLesson
import com.ar.dosarcusina.store.schema.keptBehavior
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues

/**
 * What the binder keeps that names the household, wherever it is kept, as the iOS app's
 * `HouseholdValues`: the people's names (the sections whose category plays a holder), and every value
 * of a field that says where the household lives or what it drives (an address, with its locality; a
 * plate; an email), whatever section keeps it. A label capture would learn holding one of their words
 * is the person's, never an issuer's (`CaptureLessonLearner`), and a lesson kept from before that rule
 * holding one is offered to be forgotten (`PersonalLessonLabelsStep`).
 *
 * By the field's type and the category's part, never by a built-in's key, so a category of one's own
 * is read the same way.
 */
object HouseholdValues {
    /** The kinds of field whose values name the household. */
    val fieldTypes: Set<String> = setOf("address", "plate", "email")

    /** The part a category plays whose sections are people. */
    private const val HOLDER = "holder"

    /** The shortest word a label is checked against (`CaptureLessonLearner.shortestText`). */
    const val SHORTEST_WORD = 3

    /** The folded words of every such value in the binder [view] holds. */
    fun words(view: BinderView): Set<String> {
        val categories = LinkedHashMap<String, CategoryTemplate>()
        for (template in view.all(Tables.templates)) categories.putIfAbsent(template.key, template)
        val texts = ArrayList<String>()
        for (asset in view.all(Tables.assets)) {
            val template = categories[asset.templateKey]
            if (template?.keptBehavior?.value?.role == HOLDER) texts += asset.name
            val values = asset.keptValues.value
            val fields = template?.keptSections?.items.orEmpty().flatMap { it.fields }
            for (field in fields) {
                if (field.type !in fieldTypes) continue
                (values[field.key] as? FieldValue.Text)?.value?.let { texts += it }
            }
        }
        return words(texts)
    }

    /**
     * The folded words of [texts] a label is checked against: each of [SHORTEST_WORD] letters or more
     * (`CaptureLessonLearner.words`), so a word as short as a preposition never counts.
     */
    fun words(texts: Iterable<String>): Set<String> =
        texts.flatMapTo(mutableSetOf()) { text ->
            RomanianText.words(text).filter { it.codePointCount(0, it.length) >= SHORTEST_WORD }
        }
}

/** Whether what a lesson keeps is behind the person's confirmation on this phone, as the iOS app's `IssuerLessons`. */
object LessonLocks {
    /**
     * Whether [lesson] is protected under [locks]: the category it was learned in is locked; a lesson
     * whose category isn't known (one learned before lessons kept it) is, while any lock is on. Locks
     * fail closed (`IssuerLessons.isProtected`).
     */
    fun isProtected(lesson: IssuerLesson, locks: BinderLocks): Boolean {
        val key = lesson.categoryKey ?: return locks.anySectionLocked
        return key in locks.lockedKeys
    }

    /**
     * The binder's locks as lessons read them: every category's record, and every category a section
     * or a lesson names.
     */
    fun of(view: BinderView, locks: (List<CategoryTemplate>, Iterable<String>) -> BinderLocks): BinderLocks =
        locks(
            view.all(Tables.templates),
            view.all(Tables.assets).map { it.templateKey } + view.all(Tables.lessons).mapNotNull { it.categoryKey },
        )
}
