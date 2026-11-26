package com.ar.dosarcusina.core.values

/**
 * What kind of duty a deadline is, as the iOS app's `ObligationKind`
 * (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift). [raw] is stored (`Obligation.kindRaw`)
 * and part of the `.dosar` contract.
 */
enum class ObligationKind(val raw: String) {
    /** A legal requirement with penalties: ITP, gas installation checks, rovinietă. */
    LEGAL("legal"),

    /** Taxes and declarations to the state: local taxes, Declarația Unică. */
    TAX("tax"),

    /** Insurance that lapses: RCA, PAD, CASCO. */
    INSURANCE("insurance"),

    /** Health and prevention: vaccines, screenings, prescriptions. */
    HEALTH("health"),

    /** Documents that expire and take time to renew: ID card, passport. */
    RENEWAL("renewal"),

    /** Bills and recurring payments: rent, subscriptions, utilities. */
    PAYMENT("payment"),

    /** Upkeep that prevents bigger costs: oil change, boiler service. */
    MAINTENANCE("maintenance"),

    /** Everyday chores: watering plants, cleaning filters. */
    ROUTINE("routine"),
    ;

    companion object {
        /**
         * What an unknown stored kind (from a newer build or archive) behaves as: the loudest, so a
         * deadline never goes quiet because this build can't read its kind.
         */
        val LOUDEST: ObligationKind = LEGAL

        /** A stored value: unknown or missing reads as [LOUDEST]; the stored text is kept as it was. */
        fun stored(raw: String?): ObligationKind = entries.firstOrNull { it.raw == raw } ?: LOUDEST
    }
}
