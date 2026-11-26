package com.ar.dosarcusina.core.attention

import com.ar.dosarcusina.core.text.StandardOrder
import com.ar.dosarcusina.core.urgency.AttentionUrgency
import com.ar.dosarcusina.core.urgency.DeadlineSnapshot
import com.ar.dosarcusina.core.urgency.NeedsAction
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MoneyTotals
import com.ar.dosarcusina.core.values.ObligationStatus
import java.util.UUID
import kotlin.math.log10

/** One ranked deadline, as every surface sees it (the iOS app's `AttentionEntry`). */
data class AttentionEntry(
    val deadline: DeadlineSnapshot,
    /** Whole days until it is due; negative once it has passed. */
    val daysRemaining: Int,
    /** How urgent it is, by the one rule (`UrgencyRule`, from its cycle's reminders). */
    val urgency: AttentionUrgency,
    /** Higher needs the person sooner. Only for ordering. */
    val score: Int,
) {
    val id: UUID get() = deadline.id
}

/** The deadlines of one section in „Curând”, gathered under it (the iOS app's `AttentionAssetGroup`). */
data class AttentionSectionGroup(
    /** The section; null for the household's own deadlines, which share one group. */
    val sectionId: UUID?,
    /** Its name, as the deadlines carry it; null for the household's own group, named by the screen. */
    val sectionName: String?,
    /** Soonest first. */
    val entries: List<AttentionEntry>,
) {
    /** The day the first of them is due. */
    val nextDay: CalendarDay? get() = entries.firstOrNull()?.deadline?.dueDay
}

/** Everything beyond „Curând”, said as counts instead of listed (the iOS app's `AttentionLaterSummary`). */
data class AttentionLaterSummary(
    val count: Int,
    /** The first of them to come; null with none. */
    val nextDay: CalendarDay?,
    /** What those with a cost of their own will cost, by currency. */
    val estimatedCost: MoneyTotals,
) {
    companion object {
        val EMPTY: AttentionLaterSummary = AttentionLaterSummary(0, null, MoneyTotals.EMPTY)
    }
}

/**
 * What needs the person now, shaped so Urmează stays short however much is tracked (the iOS app's
 * `AttentionDigest`): a few deadlines in [now] („Acum”), the rest of the near future gathered by
 * section in [soon] („Curând”), and everything further out as counts in [later].
 */
data class AttentionDigest(
    val now: List<AttentionEntry>,
    val soon: List<AttentionSectionGroup>,
    val later: AttentionLaterSummary,
    /** Deadlines that belonged in [now] but went into [soon] because [now] was full. */
    val overflowCount: Int,
    /** Snoozed and paused deadlines, not shown. */
    val hiddenCount: Int,
    /** Late past their grace or due today: the badge's count, [NeedsAction.count]. */
    val needsActionCount: Int,
) {
    /** Nothing needs the person: „Totul e în regulă”. */
    val isAllClear: Boolean get() = now.isEmpty() && needsActionCount == 0
}

/**
 * Ranks deadlines by what missing them costs, then by how soon, then by cost, as the iOS app's
 * `AttentionModel` (ios/DosarCuSina/Services/Attention/AttentionModel.swift): the list behind
 * Urmează ([digest]), one deadline as every surface sees it ([entry]), and the box lines' most
 * pressing deadline ([mostPressing], read by [BoxStatus]). The calm notes of „Din timp” are
 * [calmNotes] and [suggestionNote]. No words: what each part says is the screens' (Phase 4).
 */
object AttentionModel {
    /** How much „Acum” lists. */
    data class Limits(
        /** Most deadlines shown as needing the person now. */
        val maxNow: Int = STANDARD_MAX_NOW,
    ) {
        companion object {
            private const val STANDARD_MAX_NOW = 5
            val STANDARD: Limits = Limits()
        }
    }

    // How a deadline scores (`AttentionModel.score`): its consequence's weight in steps of ten,
    // then up to four of those steps for how close it is, then a small nudge for what it costs.
    private const val CONSEQUENCE_STEP = 10
    private const val LATE_PAST_GRACE = 400
    private const val LATE_DAYS_COUNTED = 30
    private const val LATE_WITHIN_GRACE = 200
    private const val CLOSENESS_RANGE = 280
    private const val COST_NUDGE_PER_DIGIT = 3
    private const val MOST_COST_NUDGE = 9

    /** The one order of „Acum” and of a section's deadlines on a day: the score, then the day, then the title. */
    internal val RANK: Comparator<AttentionEntry> =
        compareByDescending<AttentionEntry> { it.score }
            .thenBy { it.deadline.dueDay }
            .thenComparator { a, b -> StandardOrder.compare(a.deadline.title, b.deadline.title) }

    /**
     * Urmează's list on [today]: done and archived deadlines left out, paused and snoozed ones
     * counted as hidden, the rest by their urgency. „Acum” holds what needs the person now, ranked,
     * at most [Limits.maxNow]; what doesn't fit joins „Curând” with what is upcoming, gathered by
     * section, each section's soonest first and the sections by their first day, then their name.
     * The household's own deadlines share one group, ordered among the others under
     * [unassignedName], the name the screen gives it (the iOS app's „Fără secțiune”).
     */
    fun digest(
        deadlines: List<DeadlineSnapshot>,
        today: CalendarDay,
        unassignedName: String,
        limits: Limits = Limits.STANDARD,
    ): AttentionDigest {
        val shown = shown(deadlines, today)
        val nowCandidates = shown.entries.filter { it.urgency.needsAttentionNow }.sortedWith(RANK)
        val nowEntries = nowCandidates.take(limits.maxNow)
        val overflow = nowCandidates.drop(limits.maxNow)
        val soon = shown.entries.filter { it.urgency == AttentionUrgency.UPCOMING } + overflow
        val later = shown.entries.filter { it.urgency == AttentionUrgency.LATER }
        return AttentionDigest(
            now = nowEntries,
            soon = groups(soon, unassignedName),
            later = AttentionLaterSummary(
                count = later.size,
                nextDay = later.minOfOrNull { it.deadline.dueDay },
                estimatedCost = MoneyTotals.of(later.mapNotNull { it.deadline.estimatedCost }),
            ),
            overflowCount = overflow.size,
            hiddenCount = shown.hidden,
            needsActionCount = NeedsAction.count(deadlines, today),
        )
    }

    /**
     * The one deadline of [deadlines] that needs the person most on [today], ranked as „Acum” ranks
     * them; null when none needs them now (`BoxStatus.make`, the digest's first of „Acum”).
     */
    fun mostPressing(deadlines: List<DeadlineSnapshot>, today: CalendarDay): AttentionEntry? =
        shown(deadlines, today).entries.filter { it.urgency.needsAttentionNow }.sortedWith(RANK).firstOrNull()

    /**
     * One deadline as every surface sees it on [today]: days left, its urgency by the one rule (its
     * cycle's reminders' `UrgencyRule`) and its rank.
     */
    fun entry(deadline: DeadlineSnapshot, today: CalendarDay): AttentionEntry {
        val days = today.daysTo(deadline.dueDay)
        val rule = deadline.urgencyRule
        return AttentionEntry(
            deadline = deadline,
            daysRemaining = days,
            urgency = rule.urgency(deadline.dueDay, today),
            score = score(days, deadline, rule.windowDays(deadline.dueDay)),
        )
    }

    /**
     * What missing it costs carries the most weight. Closeness lifts a deadline by up to four
     * consequence steps: an overdue tax beats an ITP due in ten days, but not one due in two, and an
     * overdue chore never beats a legal deadline. Late within its grace counts like „due soon”, not
     * like overdue. Cost breaks ties.
     */
    internal fun score(daysRemaining: Int, deadline: DeadlineSnapshot, window: Int): Int {
        val profile = deadline.reminders
        val consequence = profile.consequence.weight * CONSEQUENCE_STEP
        val closeness = when {
            daysRemaining < 0 && -daysRemaining > profile.graceDays ->
                LATE_PAST_GRACE + minOf(-daysRemaining, LATE_DAYS_COUNTED)
            daysRemaining < 0 -> LATE_WITHIN_GRACE
            else -> {
                val days = maxOf(window, 1)
                maxOf(0, (days - minOf(daysRemaining, days)) * CLOSENESS_RANGE / days)
            }
        }
        val cost = deadline.estimatedCost?.amount?.toDouble() ?: 0.0
        val costNudge = if (cost > 0) minOf((log10(cost + 1) * COST_NUDGE_PER_DIGIT).toInt(), MOST_COST_NUDGE) else 0
        return consequence + closeness + costNudge
    }

    /** What the list shows of [deadlines] on [today], as entries, and how many it hides. */
    private class Shown(val entries: List<AttentionEntry>, val hidden: Int)

    private fun shown(deadlines: List<DeadlineSnapshot>, today: CalendarDay): Shown {
        val entries = mutableListOf<AttentionEntry>()
        var hidden = 0
        for (deadline in deadlines) {
            when {
                deadline.status == ObligationStatus.DONE || deadline.status == ObligationStatus.ARCHIVED -> Unit
                deadline.status == ObligationStatus.PAUSED || deadline.isSnoozed(today) -> hidden += 1
                else -> entries += entry(deadline, today)
            }
        }
        return Shown(entries, hidden)
    }

    /** [entries] gathered by section, as „Curând” lists them. */
    private fun groups(entries: List<AttentionEntry>, unassignedName: String): List<AttentionSectionGroup> {
        val byDay = compareBy<AttentionEntry> { it.deadline.dueDay }.then(RANK)
        val groups = entries.groupBy { it.deadline.sectionId }.map { (sectionId, members) ->
            val sorted = members.sortedWith(byDay)
            AttentionSectionGroup(sectionId, sorted.first().deadline.sectionName, sorted)
        }
        return groups.sortedWith(
            compareBy<AttentionSectionGroup> { it.nextDay }
                .thenComparator { a, b ->
                    StandardOrder.compare(a.sectionName ?: unassignedName, b.sectionName ?: unassignedName)
                }
                .thenBy { it.sectionId?.toString().orEmpty() },
        )
    }
}
