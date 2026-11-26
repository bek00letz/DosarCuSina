package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.deadlines.CompletionKind
import com.ar.dosarcusina.core.deadlines.CompletionRecord
import com.ar.dosarcusina.core.deadlines.CompletionShape
import com.ar.dosarcusina.core.deadlines.HistoryKind

/**
 * What one record's page in Istoric shows, by the record's kind ([HistoryKind]) laid over its category's
 * visit kind, as the iOS app's `HistoryEntryShape` (ios/DosarCuSina/Services/History/HistoryEntryShape.swift),
 * the way [VisitForm] lays a visit's shape over its category: a car's service lists what was done and who
 * serviced it, a bill what it holds and no stars. A record that closed a deadline reads its deadline's
 * completion instead ([completing]), whatever kind the record was stored as.
 *
 * Kinds and data only: each header is a kind of words, worded by the screens (Phase 4); one that is the
 * visit's own ([Items.VISIT_WORK], [Who.VisitProvider], [RatingHeader.VISIT]) takes the words of [visit]'s shape.
 */
data class HistoryEntryShape(
    /** Above the rows of what was done. */
    val items: Items,
    /** Above who did it; none when the record names no one (a note). */
    val provider: Who?,
    /** Before the number printed on its paper. */
    val reference: Reference,
    val rating: Rating,
    /** Above the stars. */
    val ratingHeader: RatingHeader,
    /** The visit kind of the record's category, whose words the visit's own headers take. */
    val visit: VisitKind?,
    /** Whether its rows are a vehicle's parts („Piesele și prețurile…” when it is deleted). */
    val rowsAreParts: Boolean = false,
) {
    /** What the rows of a record are called. */
    enum class Items {
        /** The visit's own words for what was done: „Ce s-a făcut”, „Ce i s-a făcut”. */
        VISIT_WORK,
        WHAT_WAS_DONE,
        WHAT_WAS_REPAIRED,
        WHAT_WAS_CHECKED,
        WHAT_WAS_BOUGHT,
        WHAT_THE_BILL_HOLDS,
        WHAT_WAS_PAID,
        WHAT_IT_COVERS,
        WHAT_WAS_NOTED,
    }

    /** Who did it, as a record's page says it. */
    sealed interface Who {
        /** The visit's own words for who did it: „Service-ul”, „Veterinarul”. */
        data object VisitProvider : Who
        data object WhoWorked : Who
        data object WhoChecked : Who
        data object WhoGaveIt : Who
        data object BoughtFrom : Who
        data object PaidTo : Who
        data object Insurer : Who

        /** Who a renewed paper comes from, by its noun and how it comes („Cine l-a emis”, „Cu cine l-ai semnat”). */
        data class From(val paper: CompletionShape.Paper?) : Who
    }

    /** Which paper the number printed on it belongs to, said before it. */
    enum class Reference {
        /** „Nr. 0001”. */
        NUMBER,

        /** „Factura nr. 0001”: a bill, a purchase. */
        INVOICE,

        /** „Polița nr. 0001”. */
        POLICY,
    }

    /** When the page asks how it went, with its stars. */
    enum class Rating {
        /** A job: always, unless it is a deadline's completion no one did (watering). */
        JOB,

        /** Only when someone did it (an inspection, a vaccine given by a vet). */
        WITH_SOMEONE,

        /** Never: a bill, a purchase, a note. */
        NEVER,
    }

    /** Above the stars. */
    enum class RatingHeader {
        /** The visit's own words: „Cum a lucrat?”, „Cum a fost?”. */
        VISIT,
        HOW_IT_WENT,
    }

    /** Whether the page asks how it went: [isCompletion] when it closed a deadline, [hasSomeone] when it names who. */
    fun asksRating(isCompletion: Boolean, hasSomeone: Boolean): Boolean = when (rating) {
        Rating.JOB -> hasSomeone || !isCompletion
        Rating.WITH_SOMEONE -> hasSomeone
        Rating.NEVER -> false
    }

    companion object {
        /** The page for a record of [kind], in a category whose visits are [visit] and list parts when [listsParts]. */
        fun of(kind: HistoryKind, visit: VisitKind?, listsParts: Boolean): HistoryEntryShape {
            val isJob = kind == HistoryKind.VISIT || kind == HistoryKind.MAINTENANCE || kind == HistoryKind.REPAIR
            return base(kind, visit).copy(rowsAreParts = isJob && listsParts)
        }

        /**
         * The page for a record that closed a deadline whose completion is [completion]: what the completion is
         * ([CompletionRecord]), never the kind the record was stored as, so records written before each completion
         * stated its record read right too.
         */
        fun completing(completion: CompletionKind, visit: VisitKind?, listsParts: Boolean): HistoryEntryShape =
            when (completion.record) {
                CompletionRecord.JOB -> of(HistoryKind.MAINTENANCE, visit, listsParts)
                CompletionRecord.CHECK -> of(HistoryKind.INSPECTION, visit, listsParts)
                CompletionRecord.CARE, CompletionRecord.VACCINATION ->
                    of(completion.record.historyKind, visit, listsParts)
                CompletionRecord.BILL -> of(HistoryKind.PAYMENT, visit, listsParts)
                CompletionRecord.PURCHASE -> of(HistoryKind.PURCHASE, visit, listsParts)
                // Done at home, or by whoever: never the category's visit provider (a groomer isn't the vet).
                CompletionRecord.AT_HOME -> HistoryEntryShape(
                    if (hasWork(visit)) Items.VISIT_WORK else Items.WHAT_WAS_DONE, Who.WhoGaveIt,
                    Reference.NUMBER, Rating.WITH_SOMEONE, RatingHeader.HOW_IT_WENT, visit,
                )
                CompletionRecord.TAX -> HistoryEntryShape(
                    Items.WHAT_WAS_PAID, Who.PaidTo, Reference.NUMBER, Rating.NEVER, RatingHeader.HOW_IT_WENT, visit,
                )
                CompletionRecord.POLICY -> HistoryEntryShape(
                    Items.WHAT_IT_COVERS, Who.Insurer, Reference.POLICY, Rating.NEVER, RatingHeader.HOW_IT_WENT, visit,
                )
                CompletionRecord.RENEWAL -> HistoryEntryShape(
                    Items.WHAT_WAS_DONE, Who.From(completion.shape.paper), Reference.NUMBER, Rating.NEVER,
                    RatingHeader.HOW_IT_WENT, visit,
                )
                CompletionRecord.ACKNOWLEDGED -> of(HistoryKind.NOTE, visit, listsParts)
            }

        private fun base(kind: HistoryKind, visit: VisitKind?): HistoryEntryShape = when (kind) {
            HistoryKind.VISIT, HistoryKind.MAINTENANCE -> job(visit, Items.WHAT_WAS_DONE, Who.WhoWorked, Rating.JOB)
            HistoryKind.REPAIR -> job(visit, Items.WHAT_WAS_REPAIRED, Who.WhoWorked, Rating.JOB)
            HistoryKind.VACCINATION, HistoryKind.TREATMENT ->
                job(visit, Items.WHAT_WAS_DONE, Who.WhoGaveIt, Rating.WITH_SOMEONE)
            else -> plain(kind, visit)
        }

        /**
         * A record of work done to the section, in its visit's own words where the visit has them (what was done,
         * who did it, the stars), else in [items]' and [who]'s.
         */
        private fun job(visit: VisitKind?, items: Items, who: Who, rating: Rating): HistoryEntryShape {
            val asksWho = visit?.let(VisitShape::of)?.providerTrade != null
            return HistoryEntryShape(
                items = if (hasWork(visit)) Items.VISIT_WORK else items,
                provider = if (asksWho) Who.VisitProvider else who,
                reference = Reference.NUMBER,
                rating = rating,
                ratingHeader = if (asksWho) RatingHeader.VISIT else RatingHeader.HOW_IT_WENT,
                visit = visit,
            )
        }

        /** A record that is no job: a check, a purchase, a bill, a note. */
        private fun plain(kind: HistoryKind, visit: VisitKind?): HistoryEntryShape {
            return when (kind) {
                HistoryKind.INSPECTION -> HistoryEntryShape(
                    Items.WHAT_WAS_CHECKED, Who.WhoChecked, Reference.NUMBER, Rating.WITH_SOMEONE,
                    RatingHeader.HOW_IT_WENT, visit,
                )
                HistoryKind.PURCHASE -> HistoryEntryShape(
                    Items.WHAT_WAS_BOUGHT, Who.BoughtFrom, Reference.INVOICE, Rating.NEVER, RatingHeader.HOW_IT_WENT,
                    visit,
                )
                HistoryKind.PAYMENT -> HistoryEntryShape(
                    Items.WHAT_THE_BILL_HOLDS, Who.PaidTo, Reference.INVOICE, Rating.NEVER, RatingHeader.HOW_IT_WENT,
                    visit,
                )
                else -> HistoryEntryShape(
                    Items.WHAT_WAS_NOTED, null, Reference.NUMBER, Rating.NEVER, RatingHeader.HOW_IT_WENT, visit,
                )
            }
        }

        /** Whether [visit]'s shape has words of its own for what was done. */
        private fun hasWork(visit: VisitKind?): Boolean = visit?.let(VisitShape::of)?.asksWork == true
    }
}
