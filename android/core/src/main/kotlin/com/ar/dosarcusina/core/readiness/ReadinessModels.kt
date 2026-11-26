package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import java.util.Locale
import java.util.UUID

// What the readiness checks take in and give back, as the iOS app's ReadinessModels.swift
// (ios/DosarCuSina/Services/Readiness/). The rules live in ReadinessEngine; screens only draw what
// it returns. Inputs are plain types the store fills from the binder (Phase 4 reads them from Room).

/** A UUID as the iOS app writes it into an item's id ("trip.person.<id>"): in capitals. */
internal val UUID.written: String get() = toString().uppercase(Locale.ROOT)

/** The situations the binder helps prepare for, listed once, as the iOS app's `ReadinessSituation`. */
enum class ReadinessSituation(val raw: String) {
    /** „Pleci din țară”: the people going, the car, the pets. */
    TRIP("trip"),

    /** „Vinzi mașina”: what the buyer asks for, what to cancel after, what is owed. */
    SALE("sale"),

    /** „Ai avut o daună”: the right policy's number and phone, what to photograph. */
    CLAIM("claim"),
    ;

    /** Whether it is about the whole household too, so it is offered outside a section (Urmează). */
    val isHouseholdWide: Boolean get() = this == TRIP

    /**
     * Whether a section of a category offers it: a trip on a household member (the holder part), a
     * sale on a category with an RCA, a claim on one with a deadline that keeps a policy's number or
     * claims phone. [role] is the category's part, [blueprints] its deadlines' keys, [policyFacts]
     * whether any of them keeps one of those facts.
     */
    fun isOffered(
        role: ReadinessRole?,
        blueprints: Collection<String>,
        policyFacts: Boolean,
        keys: ReadinessKeys,
    ): Boolean =
        when (this) {
            TRIP -> role == ReadinessRole.HOLDER
            SALE -> keys.vehicleRCA in blueprints
            CLAIM -> policyFacts
        }
}

/** A checklist screen, as the iOS app's `ReadinessRoute`: the situation and the section it opened from. */
sealed interface ReadinessRoute {
    /** The trip, for the household (no [holderID]) or starting from one member's page. */
    data class Trip(val holderID: UUID?) : ReadinessRoute

    data class Sale(val assetID: UUID) : ReadinessRoute

    data class Claim(val assetID: UUID) : ReadinessRoute
}

/** A situation, with what the person told the checklist about it, as the iOS app's `ReadinessScenario`. */
sealed interface ReadinessScenario {
    data class Trip(val plan: TripPlan) : ReadinessScenario

    data class Sale(val assetID: UUID) : ReadinessScenario

    /** A claim on one of the section's policies: the one [blueprintKey] names, or, when null, the first it follows. */
    data class Claim(val assetID: UUID, val blueprintKey: String? = null) : ReadinessScenario
}

/** Who goes on a trip: a household member, or the documents filed under no one. */
sealed interface TripTraveller {
    /** A stable text for item ids, as the iOS app writes it. */
    val key: String

    data class Member(val id: UUID) : TripTraveller {
        override val key: String get() = id.written
    }

    /** Personal documents not filed under anyone („Fără titular”). */
    data object Unfiled : TripTraveller {
        override val key: String = "unfiled"
    }
}

/** Where a trip goes, as the travel rules tell places apart, by the iOS app's raw value. */
enum class TripRegion(val raw: String) {
    /** The EU and the rest of the Schengen area, where an EU citizen travels with an identity card. */
    EUROPEAN_UNION("europeanUnion"),

    /** The Republic of Moldova and the Western Balkans, which take a Romanian identity card. */
    MOLDOVA_AND_WESTERN_BALKANS("moldovaAndWesternBalkans"),

    /** Anywhere else. */
    OUTSIDE_EU("outsideEU"),
    ;

    companion object {
        fun of(raw: String): TripRegion? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * A trip as the person describes it, as the iOS app's `TripPlan`: kept on the phone only while it
 * is ahead ([TripPlans]), never in the binder.
 */
data class TripPlan(
    val id: UUID,
    val start: CalendarDay,
    val end: CalendarDay,
    val region: TripRegion,
    /** Where to, in the person's words ("Grecia"); empty when not said. */
    val destination: String = "",
    val travellers: Set<TripTraveller> = emptySet(),
    /** The cars going; none when not driving. */
    val vehicles: Set<UUID> = emptySet(),
    val pets: Set<UUID> = emptySet(),
) {
    /** Whether it can be checked: it ends on or after the day it starts. */
    val isValid: Boolean get() = end >= start

    /** Whether it is over by [today]: it ended the day before or earlier. */
    fun isOver(today: CalendarDay): Boolean = end < today
}

/** Who and what can go on a trip, from what the binder holds. */
data class TripCandidates(val travellers: List<Traveller>, val vehicles: List<Option>, val pets: List<Option>) {
    data class Option(val id: UUID, val name: String)

    /** A traveller, with what the row says: the member's name, or „Acte fără titular”. */
    data class Traveller(val traveller: TripTraveller, val name: ReadinessWords)
}

/** How one check came out, as the iOS app's `ReadinessStatus`; problems sort first. */
enum class ReadinessStatus {
    /** Something will go wrong (an expired passport for a trip outside the EU). */
    PROBLEM,

    /** Something the binder doesn't know yet; worth adding. */
    MISSING,

    /** Fine but worth a look (a vignette that ends during the trip). */
    WARNING,
    OK,

    /** Something optional that isn't in the binder or isn't current: an invitation, never counted as missing. */
    SUGGESTED,

    /** Something to do or bring that the binder can't check: ticked off by hand. */
    REMINDER,
    ;

    /** Needs the person before the day: a problem or something worth a look. */
    val needsAttention: Boolean get() = this == PROBLEM || this == WARNING
}

/** Whether a situation asks for something, or only invites it, as the iOS app's `ReadinessNeed`. */
enum class ReadinessNeed {
    /** The situation can't go well without it. */
    REQUIRED,

    /** Worth having, never required: service invoices for a sale, the health card for a trip. */
    OPTIONAL,
}

/** What a row opens: the part of the iOS app's `AppRoute` the checks use, which the app's routes take on (Phase 4). */
sealed interface ReadinessTarget {
    val id: UUID

    data class Section(override val id: UUID) : ReadinessTarget

    data class Deadline(override val id: UUID) : ReadinessTarget
}

/** What a check's row does when tapped, as the iOS app's `ReadinessAction`. */
sealed interface ReadinessAction {
    /** Whether it adds something rather than opening what is there. */
    val adds: Boolean get() = this !is Open

    /** See it: the document, the deadline, the section. */
    data class Open(val target: ReadinessTarget) : ReadinessAction

    /** Add a personal document for a household member, photo first. */
    data class AddPersonalDocument(val holderID: UUID) : ReadinessAction

    /** File a paper on the section, photo first (the policy). */
    data class AddDocument(val assetID: UUID) : ReadinessAction

    /** Add one of the section's usual deadlines (RCA, ITP, the rabies vaccine). */
    data class AddDeadline(val assetID: UUID, val blueprintKey: String) : ReadinessAction

    /** Fill in a value the section doesn't have yet (the CIV, the pet's passport). */
    data class EditSection(val assetID: UUID) : ReadinessAction

    /** Ask a household member's citizenship, kept on them (`MemberFields.citizenship`). */
    data class ChooseCitizenship(val holderID: UUID) : ReadinessAction
}

/** One check, as the iOS app's `ReadinessItem`. */
class ReadinessItem(
    val id: String,
    found: ReadinessStatus,
    val need: ReadinessNeed = ReadinessNeed.REQUIRED,
    val title: ReadinessWords,
    /** Why, as a kind of sentence. An optional check that isn't ready says what it would add. */
    val detail: ReadinessWords,
    val action: ReadinessAction? = null,
) {
    /** How it came out: what its rule [found], by the one rule for an optional check ([status]). */
    val status: ReadinessStatus = status(found, need)

    companion object {
        /**
         * The one rule for an optional check: ready stays ready and something to bring stays
         * something to bring; anything else its rule found is an invitation ([ReadinessStatus.SUGGESTED]).
         */
        fun status(found: ReadinessStatus, need: ReadinessNeed): ReadinessStatus =
            if (need != ReadinessNeed.OPTIONAL || found == ReadinessStatus.OK || found == ReadinessStatus.REMINDER) {
                found
            } else {
                ReadinessStatus.SUGGESTED
            }
    }
}

/** Problems first; otherwise the order the checks were written in. */
internal fun List<ReadinessItem>.problemsFirst(): List<ReadinessItem> = sortedBy { it.status.ordinal }

/** The checks about one thing: a person, the car, a pet, what to photograph. */
class ReadinessGroup(val id: String, val title: ReadinessWords, val symbol: String, items: List<ReadinessItem>) {
    val items: List<ReadinessItem> = items.problemsFirst()
}

/** One policy a claim can go to, with the facts its deadline keeps, as the iOS app's `ReadinessPolicy`. */
data class ReadinessPolicy(
    val blueprintKey: String,
    /** The deadline's title: "RCA", "CASCO", "Asigurare obligatorie (PAD)". */
    val title: String,
    /** When this policy is the one to call, as a kind of sentence. */
    val whenToUse: ReadinessWords?,
    val insurer: String?,
    val policyNumber: String?,
    val claimsPhone: String?,
    /** The policy's deadline, when the binder follows it. */
    val deadlineID: UUID?,
    val validUntil: CalendarDay?,
    /** The bonus-malus class of the person it insures, read from them ("B6"). */
    val policyholderClass: String?,
)

/** What a situation's screen shows: groups of checks, and for a claim the policy to call. */
class ReadinessChecklist(
    groups: List<ReadinessGroup>,
    /** A claim's policy: the one asked for, or the first the binder follows. */
    val policy: ReadinessPolicy? = null,
    /** Every policy the claim could go to, for choosing another. */
    val policyOptions: List<ReadinessPolicy> = emptyList(),
) {
    val groups: List<ReadinessGroup> = groups.filter { it.items.isNotEmpty() }

    /** Every check, problems first. */
    val items: List<ReadinessItem> get() = groups.flatMap { it.items }.problemsFirst()

    /** How many checks need the person, and how many aren't in the binder. */
    val attentionCount: Int get() = items.count { it.status.needsAttention }
    val missingCount: Int get() = items.count { it.status == ReadinessStatus.MISSING }

    /** Whether everything the binder can check is ready. */
    val isAllReady: Boolean get() = attentionCount == 0 && missingCount == 0
}

// What the checks read

/** A value of a section, as the checks read it: the part of the iOS app's `FieldValue` they use. */
sealed interface ReadinessValue {
    data class Text(val text: String) : ReadinessValue

    data class Day(val day: CalendarDay) : ReadinessValue

    data class Choices(val keys: List<String>) : ReadinessValue

    /** A value of another kind (a number, money, a yes or no): the checks read none of these. */
    data object Other : ReadinessValue
}

/** A section's values by field key, read as the iOS app's `textValue` and `dateValue` do. */
data class ReadinessValues(val values: Map<String, ReadinessValue> = emptyMap()) {
    operator fun get(key: String): ReadinessValue? = values[key]

    fun text(key: String): String? = (values[key] as? ReadinessValue.Text)?.text

    fun day(key: String): CalendarDay? = (values[key] as? ReadinessValue.Day)?.day

    /** Whether [key] holds text that isn't only spaces. */
    fun hasText(key: String): Boolean = text(key)?.isNotBlank() == true

    fun with(key: String, value: ReadinessValue): ReadinessValues = ReadinessValues(values + (key to value))
}

/** The part a section's category plays, of the ones the checks read (the iOS app's `CategoryBehavior.Role`). */
enum class ReadinessRole(val raw: String) {
    /** A person things are filed under: a household member. */
    HOLDER("holder"),

    /** A personal document of a holder: an identity card, a passport. */
    PERSONAL_DOCUMENT("personalDocument"),

    /** A home: a claim's papers are a home's. */
    HOME("home"),

    SUBSCRIPTION("subscription"),

    VEHICLE("vehicle"),
    ;

    companion object {
        fun of(raw: String?): ReadinessRole? = entries.firstOrNull { it.raw == raw }
    }
}

/** An active deadline as the checks see it, as the iOS app's `ReadinessObligation`. */
data class ReadinessObligation(
    val id: UUID,
    val due: CalendarDay,
    /** The last time it was done. */
    val lastDone: CalendarDay? = null,
    /** The due day of the cycle the last time closed: done on or before it, it was renewed on time. */
    val lastCycleDue: CalendarDay? = null,
    /** Policy or contract number. */
    val reference: String? = null,
    val title: String = "",
    /** Its kind, by its stored raw value (`ObligationKind`: "insurance", "tax", "payment"…). */
    val kind: String = "routine",
    val amount: Money? = null,
)

/** One deadline's facts as the checks read them: the field each role is kept in, as the iOS app's `ReadinessFacts`. */
data class ReadinessFacts(
    val blueprintKey: String,
    /** The deadline's title ("RCA", "CASCO"). */
    val title: String,
    /** The field each fact is kept in, by its role's raw value (`BlueprintFactRole`: "insurer", "policyNumber"…). */
    val fields: Map<String, String>,
)

/** What the checks read about one section, as the iOS app's `ReadinessAsset`. */
data class ReadinessAsset(
    val id: UUID,
    val name: String,
    val templateKey: String,
    /** The part its category plays: a household member, a personal document. */
    val role: ReadinessRole? = null,
    /** The section it is filed under (a document's holder). */
    val parentId: UUID? = null,
    /** Whether its category is locked, by the one answer (`BinderLocks`): a check of it then names nothing. */
    val isSensitive: Boolean = false,
    /** A personal document replaced by a new one (`Asset.wasReplaced`): never picked for a check. */
    val wasReplaced: Boolean = false,
    val values: ReadinessValues = ReadinessValues(),
    /** Active deadlines by blueprint key. */
    val obligations: Map<String, ReadinessObligation> = emptyMap(),
    /** Active deadlines of the person's own, with no blueprint. */
    val otherObligations: List<ReadinessObligation> = emptyList(),
    val historyCount: Int = 0,
    /** Kinds of current (not archived) documents filed on it, by raw value (`DocumentKind`: "invoice", "policy"…). */
    val documentKinds: List<String> = emptyList(),
    /** The facts each of its category's deadlines keeps, in the category's order. */
    val facts: List<ReadinessFacts> = emptyList(),
) {
    /** A personal document still its holder's current one: the only kind a check picks. */
    val isCurrentDocument: Boolean get() = role == ReadinessRole.PERSONAL_DOCUMENT && !wasReplaced

    /** Every active deadline, the category's (soonest first) and the person's own. */
    val allObligations: List<ReadinessObligation> get() = obligations.values.sortedBy { it.due } + otherObligations
}

/**
 * The bonus-malus class of the person a policy insures, among the household's people: the seam to
 * the iOS app's `Policyholders.bonusMalus(ofPolicyholder:among:)`, the rule capture's filing and
 * the deadline page share, which comes with capture. [policyholder] is the name the policy's facts
 * keep; null when no one, or more than one, matches.
 */
fun interface PolicyholderClasses {
    fun of(policyholder: String?, among: List<ReadinessAsset>): String?
}
