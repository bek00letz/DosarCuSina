package com.ar.dosarcusina.core.urgency

/**
 * What missing a deadline costs, as the iOS app's `Consequence`
 * (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift). Ranking, urgency and how loudly
 * reminders speak all follow from it. The stored texts are part of the `.dosar` contract.
 */
enum class Consequence(
    val stored: String,
    /** Relative weight in the ranking, and which deadline keeps its next reminder first when there are too many. */
    val weight: Int,
    /**
     * The most days ahead a deadline of this consequence asks for the person now (30 is a
     * calendar month, like a reminder's lead). Earlier reminders still go out by its leads.
     */
    val maxAttentionWindowDays: Int,
) {
    /** Fines, a suspended registration, driving uninsured: ITP, RCA, rovinietă. */
    LEGAL(stored = "legal", weight = 100, maxAttentionWindowDays = 30),

    /** Penalties or money lost: local tax installments, a trial that turns paid. */
    FINANCIAL(stored = "financial", weight = 80, maxAttentionWindowDays = 21),

    /** Health and prevention: vaccines, check-ups. */
    HEALTH(stored = "health", weight = 60, maxAttentionWindowDays = 7),

    /** Nice to keep up with; nothing bad happens if it slips: watering, grooming. */
    COMFORT(stored = "comfort", weight = 10, maxAttentionWindowDays = 3),
    ;

    /** Whether its last reminders may break through Do Not Disturb. */
    val allowsTimeSensitiveReminders: Boolean get() = this != COMFORT

    /** Whether it follows up the day after it lapses when the profile doesn't say: legal and financial. */
    val followsUpByDefault: Boolean get() = this == LEGAL || this == FINANCIAL

    companion object {
        /**
         * What an unknown stored value (from a newer build or archive) behaves as: the loudest,
         * so a deadline never goes quiet because this build can't read its value.
         */
        val LOUDEST: Consequence = LEGAL

        /** A stored value: unknown or missing reads as [LOUDEST]. The stored text itself is kept as it was. */
        fun stored(raw: String?): Consequence = entries.firstOrNull { it.stored == raw } ?: LOUDEST
    }
}
