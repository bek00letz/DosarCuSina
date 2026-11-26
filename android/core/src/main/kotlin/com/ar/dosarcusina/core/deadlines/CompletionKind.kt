package com.ar.dosarcusina.core.deadlines

import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.core.deadlines.CompletionShape.Cost
import com.ar.dosarcusina.core.deadlines.CompletionShape.Counter
import com.ar.dosarcusina.core.deadlines.CompletionShape.NewEnd
import com.ar.dosarcusina.core.deadlines.CompletionShape.Paper

/** The document type of the European health card (`DocumentType.euHealthCard`). */
private const val EU_HEALTH_CARD = "documentType.euHealthCard"

/**
 * What closing one deadline asks, as the iOS app's `CompletionKind`
 * (ios/DosarCuSina/Models/Obligations/CompletionKind.swift): stated by every blueprint (its
 * `completion`) and described once here, by its [shape] and its [record]. A chore is one tap, an
 * ITP asks its fee and the ITP report, a renewed document the new one and its expiry, a bill what
 * was paid. A deadline of one's own takes it from its importance ([own]).
 *
 * These are kinds and data only: what each says on screen is Phase 4's, from the app's strings, by
 * the kind. [raw] is part of the `.dosar` contract (a blueprint's `completion`).
 */
enum class CompletionKind(val raw: String, val record: CompletionRecord, val shape: CompletionShape) {
    /** A chore: done today in one tap, a note offered after. Watering, cleaning the chain. */
    CHORE("chore", CompletionRecord.AT_HOME, CompletionShape.ONE_TAP),

    /** An end that only needs knowing: done in one tap. A warranty's, a minimum term's. */
    ACKNOWLEDGED("acknowledged", CompletionRecord.ACKNOWLEDGED, CompletionShape.ONE_TAP),

    /** A car's service: the cost, the service's invoice, the kilometres. */
    VEHICLE_SERVICE(
        "vehicleService", CompletionRecord.JOB,
        CompletionShape(cost = Cost.COST, paper = Paper.INVOICE, counter = Counter.SECTION),
    ),

    /** Changing a car's tyres: the cost, the tyre shop's invoice, the kilometres. */
    TYRE_CHANGE(
        "tyreChange", CompletionRecord.JOB,
        CompletionShape(cost = Cost.COST, paper = Paper.INVOICE, counter = Counter.SECTION),
    ),

    /** A bike's service: the cost, the shop's invoice if it went to one, the kilometres. */
    BIKE_SERVICE(
        "bikeService", CompletionRecord.JOB,
        CompletionShape(cost = Cost.COST, paper = Paper.INVOICE, counter = Counter.SECTION),
    ),

    /** A chimney swept: the cost, the firm's invoice. */
    CHIMNEY_SWEEP("chimneySweep", CompletionRecord.JOB, CompletionShape(cost = Cost.COST, paper = Paper.INVOICE)),

    /**
     * Upkeep done at home (descaling, a new filter, deworming): the day and what it cost; the
     * counter only where the deadline counts on it.
     */
    DONE_AT_HOME(
        "doneAtHome", CompletionRecord.AT_HOME, CompletionShape(cost = Cost.COST, counter = Counter.COUNTED_ON),
    ),

    /** The periodic service of a category of one's own: the cost, the invoice, its counter. */
    OWN_SERVICE(
        "ownService", CompletionRecord.JOB,
        CompletionShape(cost = Cost.COST, paper = Paper.INVOICE, counter = Counter.SECTION),
    ),

    /** A bill paid: what was paid and the bill, filed as a bill. */
    BILL("bill", CompletionRecord.BILL, CompletionShape(cost = Cost.PAID, paper = Paper.BILL)),

    /** The building tax: what was paid and the receipt. */
    BUILDING_TAX("buildingTax", CompletionRecord.TAX, CompletionShape(cost = Cost.PAID, paper = Paper.RECEIPT)),

    /** The rental income declaration: what was paid and the filing's receipt. */
    RENTAL_DECLARATION(
        "rentalDeclaration", CompletionRecord.TAX, CompletionShape(cost = Cost.PAID, paper = Paper.RECEIPT),
    ),

    /** A tax of one's own: what was paid and the receipt. */
    OWN_TAX("ownTax", CompletionRecord.TAX, CompletionShape(cost = Cost.PAID, paper = Paper.RECEIPT)),

    /**
     * Something renewed with a new end (a renewal of one's own): the new paper and when it expires,
     * the deadline going on from that day.
     */
    NEW_DOCUMENT(
        "newDocument", CompletionRecord.RENEWAL,
        CompletionShape(paper = Paper.NEW_DOCUMENT, newEnd = NewEnd.EXPIRES),
    ),

    /**
     * A personal document (an identity card, a passport, a licence) renewed: a new one has another
     * series and number, so it is a document of its own, added on its own. Closing asks no new
     * expiry: the deadline closes, the old one shows as expired.
     */
    DOCUMENT_REPLACED(
        "documentReplaced", CompletionRecord.RENEWAL,
        CompletionShape(
            cost = Cost.COST,
            replacement = CompletionShape.Replacement(CompletionShape.Replaces.ThisSection),
        ),
    ),

    /** The European health card on a health file renewed: a new card, added to the person's documents. */
    NEW_HEALTH_CARD(
        "newHealthCard", CompletionRecord.RENEWAL,
        CompletionShape(
            replacement = CompletionShape.Replacement(CompletionShape.Replaces.HoldersDocument(EU_HEALTH_CARD)),
        ),
    ),

    /** A subscription's contract renewed: the new contract and when it ends. */
    NEW_CONTRACT(
        "newContract", CompletionRecord.RENEWAL, CompletionShape(paper = Paper.CONTRACT, newEnd = NewEnd.ENDS),
    ),

    /** A tenancy renewed: the new contract and when it ends. */
    NEW_LEASE("newLease", CompletionRecord.RENEWAL, CompletionShape(paper = Paper.CONTRACT, newEnd = NewEnd.ENDS)),

    /** An insurance renewed: the price and the new policy. */
    POLICY("policy", CompletionRecord.POLICY, CompletionShape(cost = Cost.COST, paper = Paper.NEW_POLICY)),

    /** A car's ITP: the fee and the ITP report. */
    ITP("itp", CompletionRecord.CHECK, CompletionShape(cost = Cost.COST, paper = Paper.ITP_REPORT)),

    /** The rovinietă: the price and the rovinietă. */
    VIGNETTE("vignette", CompletionRecord.PURCHASE, CompletionShape(cost = Cost.COST, paper = Paper.VIGNETTE)),

    /** A car's first-aid kit and extinguisher: the price and the day the new ones expire. */
    SAFETY_KIT("safetyKit", CompletionRecord.PURCHASE, CompletionShape(cost = Cost.COST, newEnd = NewEnd.EXPIRES)),

    /** A boiler's check: the fee and the report. */
    BOILER_CHECK("boilerCheck", CompletionRecord.CHECK, CompletionShape(cost = Cost.COST, paper = Paper.REPORT)),

    /** A gas installation's check or revision: the fee and the report. */
    GAS_CHECK("gasCheck", CompletionRecord.CHECK, CompletionShape(cost = Cost.COST, paper = Paper.REPORT)),

    /** A legal deadline of one's own: the fee and the proof. */
    OWN_LEGAL("ownLegal", CompletionRecord.CHECK, CompletionShape(cost = Cost.COST, paper = Paper.PROOF)),

    /** A pet's vaccine: the cost and the pet's health booklet. */
    PET_VACCINE(
        "petVaccine", CompletionRecord.VACCINATION, CompletionShape(cost = Cost.COST, paper = Paper.HEALTH_BOOKLET),
    ),

    /** Yearly tests: the cost, the results and what the doctor said. */
    CHECKUP(
        "checkup", CompletionRecord.CARE,
        CompletionShape(cost = Cost.COST, paper = Paper.RESULTS, asksNote = true),
    ),

    /** A dentist's check-up: the cost and what was done. */
    DENTIST("dentist", CompletionRecord.CARE, CompletionShape(cost = Cost.COST, asksNote = true)),

    /** A person's vaccine: the cost and the vaccination certificate. */
    VACCINE("vaccine", CompletionRecord.VACCINATION, CompletionShape(cost = Cost.COST, paper = Paper.CERTIFICATE)),

    /** A health deadline of one's own: the cost, the result and a note. */
    OWN_HEALTH(
        "ownHealth", CompletionRecord.CARE,
        CompletionShape(cost = Cost.COST, paper = Paper.RESULT, asksNote = true),
    ),
    ;

    companion object {
        /**
         * A deadline with no blueprint (one of the person's own, from "Termen nou") by its kind, which
         * its importance gave it. The kinds the answers don't give (a deadline from an older backup)
         * are read the same way, each named here.
         */
        fun own(kind: ObligationKind): CompletionKind = when (kind) {
            ObligationKind.ROUTINE -> CHORE
            ObligationKind.LEGAL -> OWN_LEGAL
            ObligationKind.PAYMENT -> BILL
            ObligationKind.HEALTH -> OWN_HEALTH
            ObligationKind.TAX -> OWN_TAX
            ObligationKind.INSURANCE -> POLICY
            ObligationKind.RENEWAL -> NEW_DOCUMENT
            ObligationKind.MAINTENANCE -> OWN_SERVICE
        }

        /**
         * A stored `completion`: null when it is missing (a blueprint from before blueprints stated
         * one) or from a newer version; the deadline then completes as one of the person's own ([own]).
         */
        fun stored(raw: String?): CompletionKind? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * What a completion is, as Istoric keeps it, as the iOS app's `CompletionRecord`: a job someone did,
 * upkeep done at home, a check, care from a doctor, a vaccine, a bill, a tax, a policy, something
 * bought, a renewal, or an end only noted. Every completion kind states one ([CompletionKind.record]),
 * so the history kind a completion writes ([historyKind]) comes from the deadline's declared
 * completion, never from its importance.
 */
enum class CompletionRecord(val historyKind: HistoryKind) {
    /** Work someone did on it: a car's service, a tyre change, a chimney swept. */
    JOB(HistoryKind.MAINTENANCE),

    /** Upkeep done at home, or a chore: deworming, descaling, watering. */
    AT_HOME(HistoryKind.MAINTENANCE),

    /** A check that leaves a report: an ITP, a boiler's or a gas installation's. */
    CHECK(HistoryKind.INSPECTION),

    /** Care from a doctor: yearly tests, a dentist. */
    CARE(HistoryKind.TREATMENT),

    /** A vaccine, a person's or a pet's. */
    VACCINATION(HistoryKind.VACCINATION),

    /** A bill paid. */
    BILL(HistoryKind.PAYMENT),

    /** A tax or a declaration paid. */
    TAX(HistoryKind.PAYMENT),

    /** An insurance policy renewed. */
    POLICY(HistoryKind.PAYMENT),

    /** Something bought: a rovinietă, a new first-aid kit. */
    PURCHASE(HistoryKind.PURCHASE),

    /** A document, a card or a contract renewed. */
    RENEWAL(HistoryKind.NOTE),

    /** An end that was only noted: a warranty's, a minimum term's. */
    ACKNOWLEDGED(HistoryKind.NOTE),
}

/**
 * What happened in a record of history, as the iOS app's `HistoryKind`
 * (ios/DosarCuSina/Models/Schema/HistoryModel.swift). [raw] is stored (`HistoryEntry.kindRaw`) and
 * part of the `.dosar` contract.
 */
enum class HistoryKind(val raw: String) {
    /** A service visit or a check-up. */
    VISIT("visit"),
    REPAIR("repair"),

    /** Planned upkeep: a revision, a filter change. */
    MAINTENANCE("maintenance"),

    /** An official inspection: ITP, VTP, gas check. */
    INSPECTION("inspection"),

    /** Something bought for the section (parts, an accessory) or the section itself. */
    PURCHASE("purchase"),

    /** A bill, a tax, a premium paid. */
    PAYMENT("payment"),
    VACCINATION("vaccination"),
    TREATMENT("treatment"),

    /** Anything else worth remembering. */
    NOTE("note"),
    ;

    companion object {
        /**
         * The history kind written when a deadline is completed: its completion's record
         * ([CompletionRecord.historyKind], from the kind its blueprint declares), so a rovinietă is
         * something bought and a policy a payment, whatever their importance.
         */
        fun forCompleting(completion: CompletionKind): HistoryKind = completion.record.historyKind

        /** A stored kind; null for one this build doesn't know, which stays as stored. */
        fun stored(raw: String?): HistoryKind? = entries.firstOrNull { it.raw == raw }
    }
}
