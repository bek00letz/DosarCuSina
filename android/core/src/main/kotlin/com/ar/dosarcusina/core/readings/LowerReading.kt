package com.ar.dosarcusina.core.readings

import com.ar.dosarcusina.core.values.MeasurementUnit
import java.time.Instant

/**
 * The person's answer when a counter reading is lower than an earlier one, as the iOS app's
 * `LowerReadingAnswer`. [entries] is every answer there is, in the iOS `allCases` order; a question
 * offers the ones that fit its counter, the likelier first ([offered]). A kind only: the app words each
 * answer's button and what it does from its strings ("Era o estimare", "Contor nou", "Corectează citirea
 * veche", "Lasă citirea veche").
 */
enum class LowerReadingAnswer {
    /**
     * "Era o estimare": the earlier, higher readings were estimates. They stay as history, marked as
     * estimates ([ReadingBasis.ESTIMATED]), and count no more; the new one counts. Offered on a counter
     * whose readings may be estimated ([MeasurementKind.mayBeEstimated]), in place of "Corectează citirea
     * veche": a bill's printed index is never thrown away.
     */
    WAS_ESTIMATE,

    /**
     * "Contor nou": the meter or the dashboard was replaced, or the counter went round. The new reading
     * starts a new counter: the older readings stay as the old counter's history, and nothing after it is
     * compared with them again.
     */
    NEW_COUNTER,

    /**
     * "Corectează citirea veche": the earlier, higher readings were wrong (a typo). They go, and the new
     * one counts. Offered on a counter that is always read (a car's kilometres).
     */
    CORRECT_OLD,

    /**
     * "Lasă citirea veche": the new reading is kept aside. It stays in the list but doesn't count while
     * the readings before it are higher. Offered beside "Corectează citirea veche".
     */
    KEEP_ASIDE,
    ;

    companion object {
        /**
         * The answers a lower reading on a counter of [kind] offers, the likelier first: on a counter whose
         * readings may be estimated, "Era o estimare" and "Contor nou"; on one that is always read,
         * "Corectează citirea veche", "Lasă citirea veche" and "Contor nou". "Contor nou" comes first when
         * the drop looks like a new counter ([ReadingDrop.Size.LARGE]). The one rule for every counter; the
         * order within each group is [entries]'.
         */
        fun offered(kind: MeasurementKind, likelyNewCounter: Boolean): List<LowerReadingAnswer> {
            val corrections = entries.filter { answer ->
                when (answer) {
                    WAS_ESTIMATE -> kind.mayBeEstimated
                    NEW_COUNTER -> false
                    CORRECT_OLD, KEEP_ASIDE -> !kind.mayBeEstimated
                }
            }
            return if (likelyNewCounter) listOf(NEW_COUNTER) + corrections else corrections + NEW_COUNTER
        }
    }
}

/**
 * What a counter reading lower than one recorded before it asks, before the step writes anything, as
 * the iOS app's `LowerReadingQuestion`: the highest earlier reading and its moment, the new value and
 * its unit, and what the person may answer, the likelier first. Data only: the app words the question
 * from [asks] and whether [unit] is kilometres, and the explanation from both numbers and each answer.
 */
data class LowerReadingQuestion(
    val previous: Double,
    val previousAt: Instant,
    val value: Double,
    val unit: MeasurementUnit?,
    val answers: List<LowerReadingAnswer>,
) {
    /** The answer the question asks about: the likelier, the first. */
    val asks: LowerReadingAnswer? get() = answers.firstOrNull()
}

/**
 * How far a lower reading falls below the highest one before it on its counter, measured in the
 * counter's own use ([ReadingSeries.progress]): whether it asks at all, and which answer it offers first,
 * as the iOS app's `ReadingDrop`. The one rule for every counter, a car's kilometres and a meter's index
 * alike; only the answers differ, by whether the counter's readings may be estimated.
 */
class ReadingDrop(highest: Double, value: Double, series: ReadingSeries) {
    enum class Size {
        /** Within a few months of use: an estimate corrected, or a typo. */
        SMALL,

        /** Between the two, or too little history to tell. */
        UNSURE,

        /**
         * Down to about nothing, or more than about a year of use: a new meter or dashboard, or one that
         * went round (99999 to 00000).
         */
        LARGE,
    }

    val size: Size = when {
        value <= highest * NEAR_ZERO_SHARE -> Size.LARGE
        else -> measured(highest - value, series.progress())
    }

    private fun measured(drop: Double, progress: Progress?): Size {
        if (progress == null || progress.days < SHORTEST_HISTORY_DAYS || progress.distance <= 0) return Size.UNSURE
        val perDay = progress.distance / progress.days
        return when {
            drop <= perDay * CORRECTION_DAYS -> Size.SMALL
            drop > perDay * NEW_COUNTER_DAYS -> Size.LARGE
            else -> Size.UNSURE
        }
    }

    companion object {
        /**
         * A few months of use, in days: about half a year. Distributors read a meter at least every few
         * months and bill estimates between, so a regularisation corrects at most the months since the last
         * real reading. A drop within this, below estimates, is that correction.
         */
        const val CORRECTION_DAYS: Double = 183.0

        /** About a year of use, in days: a drop larger than this makes a new counter the likelier answer. */
        const val NEW_COUNTER_DAYS: Double = 365.0

        /** A reading at most this share of the one before it is about nothing: a new meter starts at 0. */
        const val NEAR_ZERO_SHARE: Double = 0.01

        /** The least time the counter's readings must cover before its use is known: two months. */
        const val SHORTEST_HISTORY_DAYS: Double = 60.0
    }
}
