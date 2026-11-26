package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.learning.HouseholdValues
import com.ar.dosarcusina.store.learning.LessonLocks
import com.ar.dosarcusina.store.schema.IssuerLesson

/**
 * Before capture refused a label that holds what the binder keeps that names the household
 * ([HouseholdValues]: a person's name, a home's address or locality, a plate), a lesson could keep one
 * as the label an issuer prints a value under. Each such lesson is offered to be forgotten, as the iOS
 * app's `PersonalLessonLabelsStep`; an issuer learned of from a locked category's papers isn't named
 * ([LessonLocks.isProtected]). It asks, because it changes what Settings › Ce am învățat lists.
 */
object PersonalLessonLabelsStep : DataRepairStep {
    override val id = DataRepairStepId.PERSONAL_LESSON_LABELS
    override val group = DataRepairGroup.LEARNED_LABELS
    override val applyVerb = ApplyVerb.FORGET_LABEL

    /** The lessons whose label holds a word of the household's, by id. */
    fun candidates(view: BinderView): List<IssuerLesson> {
        val household = HouseholdValues.words(view)
        if (household.isEmpty()) return emptyList()
        return view.all(Tables.lessons)
            .filter { lesson -> RomanianText.words(lesson.label).any { it in household } }
            .sortedBy { RepairReading.key(it.id) }
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val candidates = candidates(scan.view)
        if (candidates.isEmpty()) return emptyList()
        val locks = LessonLocks.of(scan.view, scan.context.locks::binder)
        return candidates.map { lesson ->
            val unnamed = LessonLocks.isProtected(lesson, locks) || lesson.issuerName.isEmpty()
            DataRepairFinding(
                id = DataRepairFinding.id(id, RepairReading.key(lesson.id)),
                step = id,
                subject = DataRepairSubject.LessonLabel(
                    lessonId = lesson.id,
                    named = if (unnamed) null else DataRepairSubject.LessonLabel.Named(lesson.issuerName, lesson.label),
                ),
            )
        }
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNullTo(mutableSetOf()) {
            (it.subject as? DataRepairSubject.LessonLabel)?.lessonId
        }
        // Checked again: a lesson changed since the list was made stays.
        for (lesson in candidates(step)) if (lesson.id in approved) step.delete(lesson)
    }
}
