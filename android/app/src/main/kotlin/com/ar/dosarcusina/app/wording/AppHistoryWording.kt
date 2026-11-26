package com.ar.dosarcusina.app.wording

import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.store.history.HistoryWording

/**
 * The words a record of history is titled with, the iOS app's own (`VisitShape.entryTitle`,
 * `HistoryActions.visitTitle`, `VisitForm.entryTitle`), each by its String Catalog key through
 * [Word]. Every kind is named here, with no default: a kind left unnamed doesn't build.
 */
object AppHistoryWording : HistoryWording {
    /** The key of a visit's title, „Vizită”. */
    const val VISIT = "Vizită"

    /** The key of a service of many jobs, „Revizie: 3 lucrări”. */
    const val MANY_JOBS = "Revizie: %lld lucrări"

    override fun entryTitle(kind: VisitKind?): String = Word.app(key(kind)).written()

    override fun manyJobs(count: Int): String = Word.app(MANY_JOBS, Word.count(count)).written()

    /** The catalog key of a kind's title. */
    fun key(kind: VisitKind?): String = when (kind) {
        VisitKind.SERVICE -> "Vizită la service"
        VisitKind.JOB -> "Lucrare"
        VisitKind.REPAIR -> "Reparație"
        VisitKind.UPKEEP -> "Revizie"
        VisitKind.DOCTOR -> "Vizită la medic"
        VisitKind.VET -> "Vizită la veterinar"
        // A note's and a visit of no kind have no form of their own: a visit's title.
        VisitKind.NOTE, VisitKind.NONE, null -> VISIT
    }
}
