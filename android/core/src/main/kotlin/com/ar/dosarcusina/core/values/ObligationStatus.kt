package com.ar.dosarcusina.core.values

/**
 * Where a deadline stands, as the iOS app's `ObligationStatus`
 * (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift).
 * [raw] is stored (`Obligation.statusRaw`) and part of the `.dosar` contract.
 */
enum class ObligationStatus(val raw: String) {
    ACTIVE("active"),

    /** Temporarily off: no reminders, hidden from attention, kept in the list. */
    PAUSED("paused"),

    /** A one-off deadline that was completed. */
    DONE("done"),

    /** Kept for history only. */
    ARCHIVED("archived"),
    ;

    companion object {
        /**
         * What an unknown stored status (from a newer build or archive) behaves as: the loudest, so a deadline
         * never goes quiet because this build can't read its status.
         */
        val LOUDEST: ObligationStatus = ACTIVE

        /**
         * A stored value: unknown or missing reads as [LOUDEST]; the stored text is kept as it was, never downgraded.
         */
        fun stored(raw: String?): ObligationStatus = entries.firstOrNull { it.raw == raw } ?: LOUDEST
    }
}
