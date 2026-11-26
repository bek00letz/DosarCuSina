package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.values.CalendarDay
import kotlinx.serialization.json.JsonObject

/** What a traveller must carry, as the iOS app's `TravelRequirement.Need`, by its raw value. */
enum class TravelNeed(val raw: String) {
    /** An identity card or a passport, whichever is valid: an EU citizen in the EU. */
    IDENTITY("identity"),
    PASSPORT("passport"),

    /** A valid residence permit: a citizen of a country outside the EU who lives in Romania. */
    RESIDENCE_PERMIT("residencePermit"),
    ;

    companion object {
        fun of(raw: String): TravelNeed? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * One thing a traveller must carry, as the iOS app's `TravelRequirement`: a need, the document
 * types that meet it (any one, the first preferred and the one a check asks to add), whether a
 * passport counts only until its travel cut-off, and how many months after the trip the
 * document must still be valid.
 */
data class TravelRequirement(
    val need: TravelNeed,
    val accepted: List<String>,
    val countsTravelCutoff: Boolean = false,
    val monthsValidAfterReturn: Int = 0,
) {
    /** The last day the trip needs the document valid through: the day back, or the months after it the place asks. */
    fun lastDayNeeded(end: CalendarDay): CalendarDay =
        if (monthsValidAfterReturn > 0) end.addingMonths(monthsValidAfterReturn) else end

    companion object {
        fun read(json: JsonObject): TravelRequirement = TravelRequirement(
            need = TravelNeed.of(json.string("need")) ?: throw TravelError("rules.json: a need this build can't read"),
            accepted = json.strings("accepted"),
            countsTravelCutoff = json.bool("countsTravelCutoff"),
            monthsValidAfterReturn = json.int("monthsValidAfterReturn"),
        )
    }
}

/**
 * What each traveller carries, by their citizenship and where they go, as the iOS app's
 * `TravelRules` (ios/DosarCuSina/Services/Readiness/TravelRules.swift), read from
 * shared/travel/rules.json: by [CitizenshipGroup] and [TripRegion], the citizenships whose identity
 * card a region's countries take instead (with where that rule comes from), where the health card
 * is checked and where everyone is reminded of the visa. Never a country in code.
 */
class TravelRules(
    private val byGroup: Map<CitizenshipGroup, Map<TripRegion, List<TravelRequirement>>>,
    val identityCards: Map<TripRegion, IdentityCards>,
    private val healthCardRegions: Set<TripRegion>,
    private val visaRegions: Set<TripRegion>,
    /** The days a first rabies vaccine takes before it counts for crossing a border. */
    val petRabiesWaitDays: Int,
    private val citizenship: Citizenship,
) {
    /** The citizenships (by ISO code) whose identity card a region takes, the requirement it sets, and its source. */
    data class IdentityCards(val citizens: Set<String>, val requirement: TravelRequirement, val source: String)

    /** What a traveller of [group] carries in [region], in the order the check lists it. */
    fun requirements(group: CitizenshipGroup, region: TripRegion): List<TravelRequirement> =
        byGroup[group]?.get(region).orEmpty()

    /** What a citizen of [citizenship] (a stored key; null when not known) carries in [region]. */
    fun requirementsOf(citizenship: String?, region: TripRegion): List<TravelRequirement> {
        val code = this.citizenship.country(citizenship)?.code
        val cards = identityCards[region]
        if (code != null && cards != null && code in cards.citizens) return listOf(cards.requirement)
        return requirements(this.citizenship.group(citizenship), region)
    }

    /** Whether the check reminds everyone going to look up the destination's visa rules. */
    fun remindsOfVisa(region: TripRegion): Boolean = region in visaRegions

    /** Whether the European health card is checked. */
    fun checksHealthCard(region: TripRegion): Boolean = region in healthCardRegions

    companion object {
        private fun region(raw: String): TripRegion =
            TripRegion.of(raw) ?: throw TravelError("rules.json: a region this build doesn't know, $raw")

        private fun group(raw: String): CitizenshipGroup =
            CitizenshipGroup.of(raw) ?: throw TravelError("rules.json: a group this build doesn't know, $raw")

        fun read(json: JsonObject, citizenship: Citizenship): TravelRules {
            val groups = json.strings("groups").map(::group)
            val regions = json.strings("regions").map(::region)
            if (groups.toSet() != CitizenshipGroup.entries.toSet() || regions.toSet() != TripRegion.entries.toSet()) {
                throw TravelError("rules.json's groups or regions aren't this build's")
            }
            val table = json.obj("byGroup")
            val byGroup = groups.associateWith { group ->
                val row = table.obj(group.raw)
                regions.associateWith { region ->
                    row.list(region.raw).map { TravelRequirement.read(it.obj(region.raw)) }
                }
            }
            val cards = json.list("identityCards").map { it.obj("identityCards") }.associate {
                val requirement = TravelRequirement.read(it.obj("requirement"))
                val citizens = it.strings("citizens").toSet()
                region(it.string("region")) to IdentityCards(citizens, requirement, it.string("source"))
            }
            return TravelRules(
                byGroup = byGroup,
                identityCards = cards,
                healthCardRegions = json.strings("healthCardRegions").map(::region).toSet(),
                visaRegions = json.strings("visaRegions").map(::region).toSet(),
                petRabiesWaitDays = json.int("petRabiesWaitDays"),
                citizenship = citizenship,
            )
        }
    }
}

/**
 * What the trip check says about a need, as the iOS app's `TravelWording`: which sentence, as a
 * [ReadinessWords] kind. Declared once per need and document type.
 */
internal class TravelWording(private val keys: ReadinessKeys) {
    /** The title of a need nothing in the binder meets yet. */
    fun title(requirement: TravelRequirement): ReadinessWords = when (requirement.need) {
        TravelNeed.IDENTITY -> ReadinessPhrase.IdentityOrPassport()
        TravelNeed.PASSPORT -> ReadinessWords.documentType(keys.passport)
        TravelNeed.RESIDENCE_PERMIT -> ReadinessWords.documentType(keys.residencePermit)
    }

    /** A document that covers the whole trip; [instead] when an earlier choice of the need is there but doesn't. */
    fun valid(requirement: TravelRequirement, type: String, until: CalendarDay, instead: Boolean): ReadinessWords {
        val months = requirement.monthsValidAfterReturn
        val past = months > 0
        return when (requirement.need) {
            TravelNeed.IDENTITY -> when {
                type == keys.idCard && past -> ReadinessPhrase.IdCardValidPastReturn(until, months)
                type == keys.idCard -> ReadinessPhrase.IdCardValid(until)
                instead && past -> ReadinessPhrase.PassportInsteadPastReturn(until, months)
                instead -> ReadinessPhrase.PassportInstead(until)
                past -> ReadinessPhrase.PassportValidPastReturn(until, months)
                else -> ReadinessPhrase.PassportValidInEU(until)
            }
            TravelNeed.PASSPORT -> if (requirement.countsTravelCutoff) {
                ReadinessPhrase.PassportGoodForTravel(until)
            } else {
                ReadinessPhrase.ValidUntil(until)
            }
            TravelNeed.RESIDENCE_PERMIT -> ReadinessPhrase.ResidencePermitValid(until)
        }
    }

    /**
     * The best document of the need doesn't last: it ended before [today], stops being good for
     * travel by its kind ([goodUntil] before its expiry), ends before the trip does, or before the
     * months after it the destination asks. A day already passed is said as passed.
     */
    fun ends(
        requirement: TravelRequirement,
        type: String,
        expiry: CalendarDay,
        goodUntil: CalendarDay,
        today: CalendarDay,
    ): ReadinessWords {
        val expired = expiry < today
        val months = requirement.monthsValidAfterReturn
        val past = months > 0
        return when (requirement.need) {
            TravelNeed.IDENTITY -> if (type == keys.idCard) {
                when {
                    expired -> ReadinessPhrase.IdCardExpired(expiry)
                    goodUntil < expiry -> ReadinessPhrase.IdCardWithoutChipEnds(goodUntil)
                    past -> ReadinessPhrase.IdCardEndsPastReturn(expiry, months)
                    else -> ReadinessPhrase.IdCardEnds(expiry)
                }
            } else {
                identityPassportEnds(expiry, expired, months)
            }
            TravelNeed.PASSPORT -> when {
                expired -> ReadinessPhrase.PassportExpired(expiry)
                !requirement.countsTravelCutoff -> ReadinessPhrase.PassportEnds(expiry)
                goodUntil < today -> ReadinessPhrase.PassportCutoffPassed(goodUntil, expiry)
                else -> ReadinessPhrase.PassportCutoffBeforeReturn(goodUntil, expiry)
            }
            TravelNeed.RESIDENCE_PERMIT -> if (expired) {
                ReadinessPhrase.ResidencePermitExpired(expiry)
            } else {
                ReadinessPhrase.ResidencePermitEnds(expiry)
            }
        }
    }

    /** A passport, an EU citizen's only identity document, that doesn't last. */
    private fun identityPassportEnds(expiry: CalendarDay, expired: Boolean, months: Int): ReadinessWords = when {
        expired -> ReadinessPhrase.IdentityPassportExpired(expiry)
        months > 0 -> ReadinessPhrase.IdentityPassportEndsPastReturn(expiry, months)
        else -> ReadinessPhrase.IdentityPassportEnds(expiry)
    }

    /** Nothing in the binder meets the need. */
    fun missing(requirement: TravelRequirement): ReadinessWords = when (requirement.need) {
        TravelNeed.IDENTITY -> if (requirement.monthsValidAfterReturn > 0) {
            ReadinessPhrase.IdentityMissingPastReturn(requirement.monthsValidAfterReturn)
        } else {
            ReadinessPhrase.IdentityMissing()
        }
        TravelNeed.PASSPORT -> if (requirement.countsTravelCutoff) {
            ReadinessPhrase.PassportMissingForTravel()
        } else {
            ReadinessPhrase.PassportMissingInEU()
        }
        TravelNeed.RESIDENCE_PERMIT -> ReadinessPhrase.ResidencePermitMissing()
    }
}
