package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.text.StandardOrder
import com.ar.dosarcusina.core.urgency.UrgencyRule
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.RomanianText
import java.util.UUID

/**
 * Pure checks, as the iOS app's `ReadinessEngine` (ios/DosarCuSina/Services/Readiness/ReadinessEngine.swift):
 * given a situation and what the binder holds, a checklist with problems first. Every rule of the
 * readiness screens lives here (which document a trip needs, which policy a claim goes to, what a
 * buyer asks for, which sentence each check says); the screens only draw it. It reads the travel
 * data the iOS app exported ([TravelData]) and asks [PolicyholderClasses] for the class of the
 * person a policy insures.
 */
class ReadinessEngine(val data: TravelData = TravelData.builtIn, policyholders: PolicyholderClasses) {
    internal val reading = BinderReading(data)
    private val trip = TripChecks(reading)
    private val sale = SaleChecks(reading)
    private val claim = ClaimChecks(reading, policyholders)

    /**
     * The checklist for [scenario]. [today] matters for a sale and a claim (is the ITP still valid
     * now?); a trip is checked for its own days, and says a day already passed as passed.
     */
    fun checklist(scenario: ReadinessScenario, assets: List<ReadinessAsset>, today: CalendarDay): ReadinessChecklist =
        when (scenario) {
            is ReadinessScenario.Trip -> ReadinessChecklist(trip.groups(scenario.plan, assets, today))
            is ReadinessScenario.Sale -> assets.firstOrNull { it.id == scenario.assetID }
                ?.let { ReadinessChecklist(sale.groups(it, today)) }
                ?: ReadinessChecklist(emptyList())
            is ReadinessScenario.Claim -> assets.firstOrNull { it.id == scenario.assetID }
                ?.let { claim.checklist(it, scenario.blueprintKey, today, assets) }
                ?: ReadinessChecklist(emptyList())
        }

    /** Every check of [scenario] in one list, problems first. */
    fun check(scenario: ReadinessScenario, assets: List<ReadinessAsset>, today: CalendarDay): List<ReadinessItem> =
        checklist(scenario, assets, today).items

    /** Whether the checklist for [route] reads anything from a locked category: while one is, it names nothing. */
    fun readsSensitive(route: ReadinessRoute, assets: List<ReadinessAsset>): Boolean = when (route) {
        is ReadinessRoute.Trip -> assets.any { it.isSensitive && reading.readByTrip(it) }
        is ReadinessRoute.Sale -> assets.any { it.id == route.assetID && it.isSensitive }
        is ReadinessRoute.Claim -> assets.any { it.id == route.assetID && it.isSensitive }
    }

    /** Who and what can go: the household's members (and documents filed under no one), its cars and its pets. */
    fun tripCandidates(assets: List<ReadinessAsset>): TripCandidates = reading.tripCandidates(assets)

    /**
     * A plan for the days given, with who goes chosen the usual way: the member it was opened
     * from, or everyone; no car and no pet until the person says so; in the EU until they say otherwise.
     */
    fun defaultTrip(
        start: CalendarDay,
        end: CalendarDay,
        holderID: UUID?,
        assets: List<ReadinessAsset>,
        id: UUID = UUID.randomUUID(),
    ): TripPlan {
        val everyone = tripCandidates(assets).travellers.map { it.traveller }.toSet()
        val opened = holderID?.let { TripTraveller.Member(it) }
        val travellers = if (opened != null && opened in everyone) setOf(opened) else everyone
        return TripPlan(id, start, end, TripRegion.EUROPEAN_UNION, travellers = travellers)
    }

    /**
     * The personal documents of one type: only those still current ([ReadinessAsset.isCurrentDocument]),
     * never one replaced by a new one, whatever its printed date says. Every check that picks a
     * document picks it here.
     */
    fun documents(type: String, assets: List<ReadinessAsset>): List<ReadinessAsset> = reading.documents(type, assets)
}

/** What every check reads of the binder the same way, as the iOS engine's shared readings. */
internal class BinderReading(val data: TravelData) {
    val keys: ReadinessKeys get() = data.keys
    val wording = TravelWording(data.keys)

    fun isVehicle(asset: ReadinessAsset): Boolean = asset.templateKey == keys.vehicle

    fun isPet(asset: ReadinessAsset): Boolean = asset.templateKey == keys.pet

    fun documents(type: String, assets: List<ReadinessAsset>): List<ReadinessAsset> =
        assets.filter { it.isCurrentDocument && data.documents.type(it.values) == type }

    fun tripCandidates(assets: List<ReadinessAsset>): TripCandidates {
        val byName = compareBy<ReadinessAsset, String>(StandardOrder) { it.name }
        val travellers = assets.filter { it.role == ReadinessRole.HOLDER }.sortedWith(byName)
            .map { TripCandidates.Traveller(TripTraveller.Member(it.id), ReadinessWords.text(it.name)) }
        // Documents filed under no one travel only while one of them is still current.
        val unfiled = if (unfiledDocuments(assets).any { it.isCurrentDocument }) {
            listOf(TripCandidates.Traveller(TripTraveller.Unfiled, ReadinessPhrase.UnfiledTraveller()))
        } else {
            emptyList()
        }
        fun options(list: List<ReadinessAsset>) = list.sortedWith(byName).map { TripCandidates.Option(it.id, it.name) }
        val vehicles = options(assets.filter(::isVehicle))
        return TripCandidates(travellers + unfiled, vehicles, options(assets.filter(::isPet)))
    }

    /** Whether a green card is this car's: it names the car's plate, or one of the two has no plate written down. */
    fun covers(greenCard: ReadinessAsset, car: ReadinessAsset): Boolean {
        fun plate(text: String?): String? = text?.let(RomanianText::compact)?.takeIf { it.isNotEmpty() }
        val named = plate(greenCard.values.text(keys.documentPlate))
        val own = plate(car.values.text(keys.plate))
        return named == null || own == null || named == own
    }

    fun expiry(asset: ReadinessAsset): CalendarDay? = asset.values.day(keys.expiry)

    fun hasValue(key: String, asset: ReadinessAsset): Boolean = asset.values.text(key)?.let { isSpaces(it) } == false

    /**
     * The last day a document expiring on [expiry] is good for travel: its type's travel margin
     * before it (a passport: six months), by the one urgency rule; the expiry itself for a type without one.
     */
    fun goodForTravelUntil(document: ReadinessAsset, expiry: CalendarDay): CalendarDay {
        val margin = data.documents.travelMarginDays(document.values)
        return UrgencyRule(0, 0, 0, travelMarginDays = margin).travelCutoff(expiry) ?: expiry
    }

    fun unfiledDocuments(assets: List<ReadinessAsset>): List<ReadinessAsset> {
        val holders = assets.filter { it.role == ReadinessRole.HOLDER }.map { it.id }.toSet()
        return assets.filter { it.role == ReadinessRole.PERSONAL_DOCUMENT && it.parentId !in holders }
    }

    /**
     * Every personal document filed for the traveller, those replaced by a new one included: what a
     * document says of its holder (their citizenship) outlives it. A check picks among them with
     * [documents], which keeps only the current ones.
     */
    fun personalDocuments(traveller: TripTraveller, assets: List<ReadinessAsset>): List<ReadinessAsset> =
        when (traveller) {
            is TripTraveller.Member ->
                assets.filter { it.role == ReadinessRole.PERSONAL_DOCUMENT && it.parentId == traveller.id }
            TripTraveller.Unfiled -> unfiledDocuments(assets)
        }

    /** Whether a trip reads this section: people, their documents and health, cars, pets. */
    fun readByTrip(asset: ReadinessAsset): Boolean =
        asset.role == ReadinessRole.HOLDER || asset.role == ReadinessRole.PERSONAL_DOCUMENT ||
            isVehicle(asset) || isPet(asset) || asset.obligations.containsKey(keys.healthEUCard)

    companion object {
        /** Whether [text] is only spaces and tabs, as the iOS app's `.whitespaces` reads it (not a line break). */
        fun isSpaces(text: String): Boolean = text.all { it.isWhitespace() && it != '\n' && it != '\r' }

        /** A deadline the section doesn't have: add it. */
        fun notInBinder(
            id: String,
            title: ReadinessWords,
            detail: ReadinessWords,
            asset: ReadinessAsset,
            blueprintKey: String,
        ) = ReadinessItem(
            id, ReadinessStatus.MISSING, title = title, detail = detail,
            action = ReadinessAction.AddDeadline(asset.id, blueprintKey),
        )

        /** Something to do or bring that the binder can't check. */
        fun reminder(id: String, title: ReadinessPhrase, detail: ReadinessPhrase) =
            ReadinessItem(id, ReadinessStatus.REMINDER, title = title(), detail = detail())

        fun openSection(id: UUID) = ReadinessAction.Open(ReadinessTarget.Section(id))

        fun openDeadline(id: UUID) = ReadinessAction.Open(ReadinessTarget.Deadline(id))
    }
}
