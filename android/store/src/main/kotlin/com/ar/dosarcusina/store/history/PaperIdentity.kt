package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import java.time.ZoneId
import java.util.UUID

/**
 * What makes a paper the same paper, whichever photo or PDF of it is filed, as the iOS app's `PaperIdentity`
 * (ios/DosarCuSina/Services/History/PaperIdentity.swift): a bill in its subscription, a visit's, a repair's
 * or a purchase's invoice on its section. The one rule the review, the filing plan, the visit form, the
 * filer and the repair list use. A paper is known within the section it belongs to:
 *
 * - by its number, when both papers have one. A different number is another paper. The same number is the
 *   same paper for certain only when it can only be one issuer's: a bill's, whose subscription is its
 *   provider, or an invoice from the same firm on the same day; with a firm on one of them only, or on
 *   another day, it may be the same paper or another, and the person can say which.
 * - else by its day and its total together, in the same currency, and by who issued it when both name
 *   someone. A paper with neither a number nor a total is never taken for another.
 */
data class PaperIdentity(
    /** The number as printed ("EXM 0000001"); none when it wasn't read. */
    val number: String?,
    /** The day it was issued (a bill's), or a visit's day. */
    val day: CalendarDay,
    /** What it came to. */
    val total: Money?,
    /** Who issued it. */
    val issuer: Issuer = Issuer.Named(null),
) {
    /** Who issued a paper, as far as the rule can tell. */
    sealed interface Issuer {
        /** The section it is filed in names the issuer: a bill, whose subscription is one provider's. */
        data object Section : Issuer

        /** Named on the paper or the record (a visit's firm); none when nobody was named. */
        data class Named(val name: String?) : Issuer
    }

    /** How two papers were found to be the same one. */
    enum class Match {
        /** The same number, from the same issuer: certain. */
        NUMBER,

        /** The same number, nothing more to say it is the same issuer's: likely, the person can say otherwise. */
        NUMBER_ONLY,

        /** No number on one of them, the same day and total (and firm, when both name one): very likely. */
        DAY_AND_TOTAL,
    }

    /** Whether [other] is this same paper, and how that is known; none when it is another one. */
    fun match(other: PaperIdentity): Match? {
        val firms = firms(issuer, other.issuer)
        val mine = comparable(number)
        val theirs = comparable(other.number)
        val sameDayAndTotal = total != null && total == other.total && day == other.day
        return when {
            mine == null || theirs == null ->
                if (sameDayAndTotal && firms != Firms.DIFFERENT) Match.DAY_AND_TOTAL else null
            mine != theirs -> null
            else -> byNumber(firms, day == other.day)
        }
    }

    /** How two papers with the same number are the same paper, by what their issuers say. */
    private fun byNumber(firms: Firms, sameDay: Boolean): Match? = when (firms) {
        Firms.SAME_SECTION -> Match.NUMBER
        Firms.SAME -> if (sameDay) Match.NUMBER else Match.NUMBER_ONLY
        Firms.DIFFERENT -> null
        Firms.UNKNOWN -> Match.NUMBER_ONLY
    }

    /**
     * The paper among [papers] that this one is, by the rule above, the most certain match first (the same
     * number from the same issuer, then the same number alone, then the same day and total). [identity] reads
     * each candidate.
     */
    fun <P> filed(papers: List<P>, identity: (P) -> PaperIdentity): Pair<P, Match>? {
        val matches = papers.mapNotNull { paper -> match(identity(paper))?.let { paper to it } }
        return matches.firstOrNull { it.second == Match.NUMBER }
            ?: matches.firstOrNull { it.second == Match.NUMBER_ONLY }
            ?: matches.firstOrNull()
    }

    private enum class Firms { SAME_SECTION, SAME, DIFFERENT, UNKNOWN }

    companion object {
        /** A bill of a subscription: its provider is the subscription's. */
        fun bill(number: String?, day: CalendarDay, total: Money?): PaperIdentity =
            PaperIdentity(number, day, total, Issuer.Section)

        /**
         * A paper already logged in a section's history, as the rule reads it: its number, its day, its total
         * and who issued it (a bill's subscription, a visit's first firm by name).
         */
        fun of(view: BinderView, entry: HistoryEntry, zone: ZoneId): PaperIdentity {
            val issuer = if (entry.kindRaw == HistoryKind.PAYMENT.raw) {
                Issuer.Section
            } else {
                Issuer.Named(HistoryRecords.providerNames(view, entry).firstOrNull())
            }
            return PaperIdentity(entry.reference, CalendarDay.of(entry.occurredAt, zone), entry.totalCost, issuer)
        }

        /** The bills logged in [subscription]'s history: what capture logged, never a completion's "paid" record. */
        fun bills(view: BinderView, subscription: Asset): List<HistoryEntry> =
            HistoryRecords.of(view, subscription).filter { it.kindRaw == HistoryKind.PAYMENT.raw && !it.isCompletion }

        /**
         * The visits, repairs and purchases logged in [section]'s history, whose invoice another photo may be:
         * never a bill, and never a record a deadline's completion wrote.
         */
        fun visits(view: BinderView, section: Asset): List<HistoryEntry> =
            HistoryRecords.of(view, section).filter { it.kindRaw != HistoryKind.PAYMENT.raw && !it.isCompletion }

        /**
         * The entry a paper being filed is already logged as, in one order for every paper: the entry its own
         * document is filed with ([keptDocumentEntry], the same photo or file filed again), else the entry
         * among [entries] the rule finds for [paper] (another photo or PDF of it). [paper] is none when there is
         * nothing to compare: no document, or the person said it is another paper ("E altă factură").
         */
        fun filed(
            view: BinderView,
            keptDocumentEntry: HistoryEntry?,
            paper: PaperIdentity?,
            entries: List<HistoryEntry>,
            zone: ZoneId,
        ): Pair<HistoryEntry, FiledPaper>? {
            val kept = keptDocumentEntry?.let { it to FiledPaper.of(view, it, FiledPaper.Match.SAME_DOCUMENT, zone) }
            return kept ?: paper?.filed(entries) { of(view, it, zone) }?.let { (entry, match) ->
                entry to FiledPaper.of(view, entry, FiledPaper.Match.of(match), zone)
            }
        }

        /**
         * A number or a name as compared: letters and digits only, folded, in capitals ("EXM-0000001" and
         * "exm 0000001" are the same, so are "Service Exemplu S.R.L." and "SERVICE EXEMPLU SRL"); none when
         * nothing is left.
         */
        fun comparable(text: String?): String? = text?.let(RomanianText::compact)?.takeIf { it.isNotEmpty() }

        private fun firms(one: Issuer, other: Issuer): Firms = when {
            one is Issuer.Section && other is Issuer.Section -> Firms.SAME_SECTION
            one is Issuer.Named && other is Issuer.Named -> {
                val mine = comparable(one.name)
                val theirs = comparable(other.name)
                when {
                    mine == null || theirs == null -> Firms.UNKNOWN
                    mine == theirs -> Firms.SAME
                    else -> Firms.DIFFERENT
                }
            }
            else -> Firms.UNKNOWN
        }
    }
}

/**
 * A paper being filed that is already in the binder, as the iOS app's `FiledPaper`: the same document filed
 * again, or another photo or PDF of the same paper ([PaperIdentity]). Saving updates its entry instead of
 * logging a second one.
 */
data class FiledPaper(
    /** The paper's entry in its section's history. */
    val entryId: UUID,
    val match: Match,
    /** The section the entry is in now, and its name. */
    val sectionId: UUID?,
    val section: String,
    /** The day the entry is logged on. */
    val day: CalendarDay,
) {
    enum class Match {
        /** The same document (the same photo or file) filed again. */
        SAME_DOCUMENT,

        /** The same number from the same issuer in the same section. */
        NUMBER,

        /** The same number in the same section, nothing more to confirm it. */
        NUMBER_ONLY,

        /** No number to compare, the same day and total (and firm) in the same section. */
        DAY_AND_TOTAL,
        ;

        companion object {
            fun of(match: PaperIdentity.Match): Match = when (match) {
                PaperIdentity.Match.NUMBER -> NUMBER
                PaperIdentity.Match.NUMBER_ONLY -> NUMBER_ONLY
                PaperIdentity.Match.DAY_AND_TOTAL -> DAY_AND_TOTAL
            }
        }
    }

    /**
     * Whether the person may say it is another paper ("E altă factură"): when the match rests on the day and
     * total, or on the number alone. The same document, or the same number from the same issuer, is certain.
     */
    val mayBeAnother: Boolean get() = match == Match.DAY_AND_TOTAL || match == Match.NUMBER_ONLY

    companion object {
        fun of(view: BinderView, entry: HistoryEntry, match: Match, zone: ZoneId): FiledPaper {
            val section = entry.asset?.let { view.row(Tables.assets, it) }
            val day = CalendarDay.of(entry.occurredAt, zone)
            return FiledPaper(entry.id, match, section?.id, section?.name.orEmpty(), day)
        }
    }
}
