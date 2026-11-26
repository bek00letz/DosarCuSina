package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.keptSections
import java.util.Locale
import java.util.UUID

/**
 * What a finding is about, as the iOS app's `DataRepairFinding.Subject`: what applying it needs, and
 * the data the app words its sentence from (the names it shows, never with a card number in them).
 * The sentences are the iOS app's, which the app's strings carry; each subject says which.
 */
sealed interface DataRepairSubject {
    /**
     * A deadline from a first-version backup gets its blueprint and that blueprint's rule: „[deadline]”
     * la [section] a venit dintr-o copie de siguranță veche, fără regula lui. Îi pun regula obișnuită?
     */
    data class Blueprint(
        val obligationId: UUID,
        val blueprintKey: String,
        val deadline: String,
        val section: String,
    ) : DataRepairSubject

    /**
     * A record whose words hold a whole card number is kept with its last four digits: „[name]”
     * păstrează un număr de card întreg…, after „La [section],” when it belongs to a section.
     */
    data class CardNumbers(val record: RecordKey, val name: String, val section: String?) : DataRepairSubject

    /**
     * A day kept that can't be ([verdict]), set to [to] when that is known: worded by its verdict, with
     * where it is kept ([name], under [section] when there is one).
     */
    data class DayYear(
        val place: DayYearsStep.Place,
        val from: CalendarDay,
        val to: CalendarDay?,
        val verdict: DayYearsStep.Verdict,
        val name: String,
        val section: String?,
    ) : DataRepairSubject

    /**
     * A lesson capture learned whose label holds a value of the household's is forgotten: with its
     * issuer and label when [named], else without naming either (a locked category's paper, or no
     * issuer's name).
     */
    data class LessonLabel(val lessonId: UUID, val named: Named?) : DataRepairSubject {
        data class Named(val issuerName: String, val label: String)
    }
}

/** A record by its kind and its key (`Table.keyOf`: its id, a category's key), as the iOS app's `RecordRef`. */
data class RecordKey(val type: String, val key: String)

/** What the steps read alike. */
internal object RepairReading {
    /** The categories by key, the first by row when a key repeats (`TemplateStore.templatesByKey`). */
    fun categories(view: BinderView): Map<String, CategoryTemplate> {
        val byKey = LinkedHashMap<String, CategoryTemplate>()
        for (template in view.all(Tables.templates)) byKey.putIfAbsent(template.key, template)
        return byKey
    }

    /** Every field of [template], in its sections' order (`TemplateDefinition.allFields`). */
    fun fields(template: CategoryTemplate): List<FieldDefinition> = template.keptSections.items.flatMap { it.fields }

    /** An id as a finding names it: the iOS app's `uuidString`, in capitals. */
    fun key(id: UUID): String = id.toString().uppercase(Locale.ROOT)
}
