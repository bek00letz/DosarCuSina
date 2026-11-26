package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.readiness.BinderReading.Companion.notInBinder
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openDeadline
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openSection
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.reminder
import com.ar.dosarcusina.core.urgency.DueDayValidity
import com.ar.dosarcusina.core.values.CalendarDay

/** „Pleci din țară”: what each traveller carries, and the cars and pets going, as the iOS engine's trip. */
internal class TripChecks(private val reading: BinderReading) {
    private val keys get() = reading.keys
    private val rules get() = reading.data.rules
    private val citizenship get() = reading.data.citizenship
    private val documents = TravellerDocuments(reading)
    private val vehicle = VehicleTripChecks(reading)

    fun groups(plan: TripPlan, assets: List<ReadinessAsset>, today: CalendarDay): List<ReadinessGroup> {
        val candidates = reading.tripCandidates(assets)
        val people = candidates.travellers.filter { it.traveller in plan.travellers }.map { candidate ->
            val items = travellerChecks(candidate.traveller, plan, assets, candidates.travellers.size, today)
            ReadinessGroup("trip.person.${candidate.traveller.key}", candidate.name, "person.crop.circle", items)
        }
        val cars = assets.filter { reading.isVehicle(it) && it.id in plan.vehicles }.map { car ->
            val items = vehicle.checks(car, plan, assets, today)
            ReadinessGroup("trip.vehicle.${car.id.written}", ReadinessWords.text(car.name), "car.fill", items)
        }
        val pets = assets.filter { reading.isPet(it) && it.id in plan.pets }.map { pet ->
            val items = petChecks(pet, plan, today)
            ReadinessGroup("trip.pet.${pet.id.written}", ReadinessWords.text(pet.name), "pawprint.fill", items)
        }
        return people + cars + pets
    }

    /** A traveller's citizenships: every one kept on the member, else every one their documents print. */
    private fun citizenships(traveller: TripTraveller, assets: List<ReadinessAsset>): List<String> {
        val documents = reading.personalDocuments(traveller, assets).map { it.values }
        return when (traveller) {
            is TripTraveller.Member -> citizenship.of(assets.firstOrNull { it.id == traveller.id }?.values, documents)
            TripTraveller.Unfiled -> citizenship.read(documents)
        }
    }

    /** The documents that can stand for a citizenship: those that print it, and those that print none. */
    private fun standingFor(own: List<ReadinessAsset>, key: String): List<ReadinessAsset> =
        own.filter { document -> citizenship.printed(document.values)?.let { it == key } ?: true }

    /**
     * What one traveller needs, by their citizenship and the region: the citizenship asked first
     * when none is known, each document the rules ask for, the health card in the EU, the visa
     * rules outside it. A person with several citizenships travels on the most favourable for this
     * trip: the one that leaves the least to fix, then the one that asks for less, then a
     * free-movement citizenship, then the first.
     */
    private fun travellerChecks(
        traveller: TripTraveller,
        plan: TripPlan,
        assets: List<ReadinessAsset>,
        holderCount: Int,
        today: CalendarDay,
    ): List<ReadinessItem> {
        val own = reading.personalDocuments(traveller, assets)
        val items = mutableListOf<ReadinessItem>()
        val known = citizenships(traveller, assets)
        if (known.isEmpty()) {
            items += citizenshipQuestion(traveller)
            items += rules.requirementsOf(null, plan.region).map { documents.check(it, own, traveller, plan, today) }
        } else {
            val ways = known.mapIndexed { index, key ->
                val standing = standingFor(own, key)
                val checks = rules.requirementsOf(key, plan.region)
                    .map { documents.check(it, standing, traveller, plan, today) }
                val freeFirst = if (citizenship.group(key) == CitizenshipGroup.FREE_MOVEMENT) 0 else 1
                checks to listOf(checks.count { it.status != ReadinessStatus.OK }, checks.size, freeFirst, index)
            }
            items += ways.minWithOrNull { a, b -> compareRanks(a.second, b.second) }?.first.orEmpty()
        }
        if (rules.checksHealthCard(plan.region)) items += healthCard(traveller, assets, holderCount, plan.end, today)
        if (rules.remindsOfVisa(plan.region)) {
            items += reminder("trip.visa.${traveller.key}", ReadinessPhrase.VisaTitle, ReadinessPhrase.VisaDetail)
        }
        return items
    }

    private fun compareRanks(a: List<Int>, b: List<Int>): Int =
        a.zip(b).firstOrNull { (x, y) -> x != y }?.let { (x, y) -> x.compareTo(y) } ?: a.size.compareTo(b.size)

    /** No citizenship known: a member is asked it (kept on them, so only once); unfiled documents can't keep it yet. */
    private fun citizenshipQuestion(traveller: TripTraveller): ReadinessItem {
        val id = "trip.citizenship.${traveller.key}"
        val title = ReadinessPhrase.CitizenshipTitle()
        return when (traveller) {
            is TripTraveller.Member -> ReadinessItem(
                id, ReadinessStatus.MISSING, title = title, detail = ReadinessPhrase.CitizenshipAsked(),
                action = ReadinessAction.ChooseCitizenship(traveller.id),
            )
            TripTraveller.Unfiled ->
                ReadinessItem(
                    id, ReadinessStatus.MISSING, title = title, detail = ReadinessPhrase.CitizenshipOfUnfiled(),
                )
        }
    }

    /**
     * The European health card, as a document or as the renewal on a health profile filed under the
     * person (or, in a household of one, on its own).
     */
    private fun healthCard(
        traveller: TripTraveller,
        assets: List<ReadinessAsset>,
        holderCount: Int,
        end: CalendarDay,
        today: CalendarDay,
    ): ReadinessItem {
        val id = "trip.ehic.${traveller.key}"
        val title = ReadinessWords.documentType(keys.euHealthCard)
        val profiles = assets.filter { asset ->
            asset.obligations.containsKey(keys.healthEUCard) && when (traveller) {
                is TripTraveller.Member ->
                    asset.parentId == traveller.id || (asset.parentId == null && holderCount <= 1)
                TripTraveller.Unfiled -> asset.parentId == null
            }
        }
        val own = reading.personalDocuments(traveller, assets)
        val fromCards = reading.documents(keys.euHealthCard, own)
            .mapNotNull { card -> reading.expiry(card)?.let { it to openSection(card.id) } }
        val fromProfiles = profiles.mapNotNull { profile ->
            profile.obligations[keys.healthEUCard]?.let { it.due to openDeadline(it.id) }
        }
        val (until, action) = (fromCards + fromProfiles).maxWithOrNull(compareBy { it.first })
            ?: return ReadinessItem(
                id, ReadinessStatus.MISSING, ReadinessNeed.OPTIONAL, title, ReadinessPhrase.HealthCardMissing(),
                documents.addDocument(traveller),
            )
        val (status, detail) = when {
            DueDayValidity.covers(end, until) -> ReadinessStatus.OK to ReadinessPhrase.ValidUntil(until)
            until < today -> ReadinessStatus.WARNING to ReadinessPhrase.HealthCardExpired(until)
            else -> ReadinessStatus.WARNING to ReadinessPhrase.HealthCardEnds(until)
        }
        return ReadinessItem(id, status, ReadinessNeed.OPTIONAL, title, detail, action)
    }

    private fun petChecks(pet: ReadinessAsset, plan: TripPlan, today: CalendarDay): List<ReadinessItem> {
        val hasPassport = reading.hasValue(keys.petPassport, pet)
        val passport = ReadinessItem(
            "trip.petPassport.${pet.id.written}", if (hasPassport) ReadinessStatus.OK else ReadinessStatus.MISSING,
            title = ReadinessPhrase.PetPassportTitle(),
            detail = if (hasPassport) ReadinessPhrase.PetPassportKept() else ReadinessPhrase.PetPassportMissing(),
            action = if (hasPassport) openSection(pet.id) else ReadinessAction.EditSection(pet.id),
        )
        val rabiesID = "trip.rabies.${pet.id.written}"
        val rabies = pet.obligations[keys.petRabies]?.let { rabies(rabiesID, it, plan, today) }
            ?: notInBinder(
                rabiesID, ReadinessPhrase.RabiesTitle(), ReadinessPhrase.RabiesMissing(), pet, keys.petRabies,
            )
        val rules = if (plan.region != TripRegion.EUROPEAN_UNION) {
            val id = "trip.petTiter.${pet.id.written}"
            listOf(reminder(id, ReadinessPhrase.PetRulesTitle, ReadinessPhrase.PetRulesDetail))
        } else {
            emptyList()
        }
        return listOf(passport, rabies) + rules
    }

    /**
     * A pet's rabies vaccine for a trip. It must still be valid on the day back. A vaccine given
     * less than the wait before leaving counts only if it was a booster given before the one before
     * ran out (done on or before the due day of the cycle it closed); a first one, or one after a
     * lapse, waits. When the binder can't tell which it was, the person is asked to look in the passport.
     */
    private fun rabies(id: String, rabies: ReadinessObligation, plan: TripPlan, today: CalendarDay): ReadinessItem {
        val latestAllowed = plan.start.addingDays(-rules.petRabiesWaitDays)
        val done = rabies.lastDone
        val due = rabies.due
        val (status, detail) = when {
            !DueDayValidity.covers(plan.end, due) ->
                ReadinessStatus.PROBLEM to
                    if (due < today) ReadinessPhrase.RabiesExpired(due) else ReadinessPhrase.RabiesEnds(due)
            done != null && done > latestAllowed -> when (rabies.lastCycleDue?.let { done <= it }) {
                true -> ReadinessStatus.OK to ReadinessPhrase.RabiesBoosterOnTime(done, due)
                false -> ReadinessStatus.PROBLEM to ReadinessPhrase.RabiesAfterLapse(done, latestAllowed)
                null -> ReadinessStatus.WARNING to ReadinessPhrase.RabiesTooClose(done)
            }
            done == null -> ReadinessStatus.WARNING to ReadinessPhrase.RabiesUndated(due)
            else -> ReadinessStatus.OK to ReadinessPhrase.ValidUntil(due)
        }
        val action = openDeadline(rabies.id)
        return ReadinessItem(id, status, title = ReadinessPhrase.RabiesTitle(), detail = detail, action = action)
    }
}

/** What a traveller carries, one requirement at a time, as the iOS engine's `check(_:own:…)`. */
internal class TravellerDocuments(private val reading: BinderReading) {
    private val documentTypes get() = reading.data.documents

    /** One document of a requirement, as the check weighs it: its type's place in the rule's order, its last day. */
    private class Dated(
        val document: ReadinessAsset,
        val type: String,
        val order: Int,
        val expiry: CalendarDay,
        val countsUntil: CalendarDay,
    )

    /** What a requirement's documents are: dated ones, and those that are no travel document or have no expiry. */
    private class Found(
        val dated: List<Dated>,
        val travelling: List<ReadinessAsset>,
        val notForTravel: List<ReadinessAsset>,
    )

    /** Where a missing personal document is added: under the member, photo first. */
    fun addDocument(traveller: TripTraveller): ReadinessAction? =
        (traveller as? TripTraveller.Member)?.let { ReadinessAction.AddPersonalDocument(it.id) }

    private fun found(requirement: TravelRequirement, own: List<ReadinessAsset>): Found {
        val travelling = mutableListOf<ReadinessAsset>()
        val notForTravel = mutableListOf<ReadinessAsset>()
        val dated = mutableListOf<Dated>()
        requirement.accepted.forEachIndexed { order, type ->
            for (document in reading.documents(type, own)) {
                if (documentTypes.travels(document.values)) {
                    travelling += document
                    reading.expiry(document)?.let { dated += dated(requirement, document, type, order, it) }
                } else {
                    notForTravel += document
                }
            }
        }
        return Found(dated, travelling, notForTravel)
    }

    /** Until when a document counts: its expiry, a passport's travel cut-off, or the last day its kind travels. */
    private fun dated(
        requirement: TravelRequirement,
        document: ReadinessAsset,
        type: String,
        order: Int,
        expiry: CalendarDay,
    ): Dated {
        val cutoff = if (requirement.countsTravelCutoff) reading.goodForTravelUntil(document, expiry) else expiry
        val countsUntil = documentTypes.travelEnd(document.values)?.let { minOf(cutoff, it) } ?: cutoff
        return Dated(document, type, order, expiry, countsUntil)
    }

    /**
     * One requirement, met by any of its document types: the first type (in the rule's order)
     * that covers the whole trip and the months after it the destination asks; else the one that
     * lasts longest, which ends too early; else a document that is no travel document (the simple
     * identity card); else one with no expiry written down; else nothing in the binder, to add.
     */
    fun check(
        requirement: TravelRequirement,
        own: List<ReadinessAsset>,
        traveller: TripTraveller,
        plan: TripPlan,
        today: CalendarDay,
    ): ReadinessItem {
        val id = "trip.${requirement.need.raw}.${traveller.key}"
        val found = found(requirement, own)
        val lastDay = requirement.lastDayNeeded(plan.end)
        val covering = found.dated.filter { DueDayValidity.covers(lastDay, it.countsUntil) }
        // The most preferred type first, then the one that lasts longest.
        val best = covering.minWithOrNull(compareBy<Dated> { it.order }.thenByDescending { it.countsUntil })
        if (best != null) {
            // An earlier choice is in the binder but doesn't last: say why this one is taken.
            val instead = found.dated.any { it.order < best.order }
            return ReadinessItem(
                id, ReadinessStatus.OK, title = ReadinessWords.documentType(best.type),
                detail = reading.wording.valid(requirement, best.type, best.countsUntil, instead),
                action = openSection(best.document.id),
            )
        }
        // The one that lasts longest, the most preferred type on a tie.
        val longest = found.dated.minWithOrNull(compareByDescending<Dated> { it.countsUntil }.thenBy { it.order })
            ?: return withoutADate(requirement, id, found, traveller)
        return ReadinessItem(
            id, ReadinessStatus.PROBLEM, title = ReadinessWords.documentType(longest.type),
            detail = reading.wording.ends(requirement, longest.type, longest.expiry, longest.countsUntil, today),
            action = openSection(longest.document.id),
        )
    }

    private fun withoutADate(
        requirement: TravelRequirement,
        id: String,
        found: Found,
        traveller: TripTraveller,
    ): ReadinessItem {
        val simple = found.notForTravel.firstOrNull()
        val undated = found.travelling.firstOrNull()
        return when {
            simple != null && undated == null -> ReadinessItem(
                id, ReadinessStatus.PROBLEM, title = ReadinessWords.text(simple.name),
                detail = ReadinessPhrase.NotATravelDocument(),
                action = addDocument(traveller) ?: openSection(simple.id),
            )
            undated != null -> ReadinessItem(
                id, ReadinessStatus.MISSING, title = ReadinessWords.text(undated.name),
                detail = ReadinessPhrase.Undated(),
                action = ReadinessAction.EditSection(undated.id),
            )
            else -> ReadinessItem(
                id, ReadinessStatus.MISSING, title = reading.wording.title(requirement),
                detail = reading.wording.missing(requirement),
                action = addDocument(traveller),
            )
        }
    }
}
