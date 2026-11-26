package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.readiness.BinderReading.Companion.notInBinder
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openDeadline
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openSection
import com.ar.dosarcusina.core.urgency.DueDayValidity
import com.ar.dosarcusina.core.values.CalendarDay

/**
 * A car going on a trip: its RCA, ITP, green card and vignette, and a licence among the people
 * going, as the iOS engine's `carChecks`.
 */
internal class VehicleTripChecks(private val reading: BinderReading) {
    private val keys get() = reading.keys

    /** What a deadline that must still be valid when the trip ends (RCA, ITP) says, for each outcome. */
    private class Valid(
        val title: ReadinessPhrase,
        val failing: ReadinessPhrase,
        val passed: ReadinessPhrase,
        val missing: ReadinessPhrase,
    )

    fun checks(car: ReadinessAsset, plan: TripPlan, assets: List<ReadinessAsset>, today: CalendarDay) = listOf(
        validThroughTrip(
            keys.vehicleRCA, car, plan.end, today,
            Valid(
                title = ReadinessPhrase.RcaTitle,
                failing = ReadinessPhrase.RcaEnds,
                passed = ReadinessPhrase.RcaExpired,
                missing = ReadinessPhrase.RcaMissing,
            ),
        ),
        validThroughTrip(
            keys.vehicleITP, car, plan.end, today,
            Valid(
                title = ReadinessPhrase.ItpTitle,
                failing = ReadinessPhrase.ItpEnds,
                passed = ReadinessPhrase.ItpExpired,
                missing = ReadinessPhrase.ItpMissing,
            ),
        ),
        greenCard(car, plan, assets, today),
        vignette(car, plan, today),
        drivingLicence(car, plan, assets, today),
    )

    private fun validThroughTrip(
        key: String,
        car: ReadinessAsset,
        end: CalendarDay,
        today: CalendarDay,
        words: Valid,
    ): ReadinessItem {
        val id = "$key.${car.id.written}"
        val obligation = car.obligations[key] ?: return notInBinder(id, words.title(), words.missing(), car, key)
        val ok = DueDayValidity.covers(end, obligation.due)
        val detail = when {
            ok -> ReadinessPhrase.ValidUntil(obligation.due)
            obligation.due < today -> words.passed(obligation.due)
            else -> words.failing(obligation.due)
        }
        val status = if (ok) ReadinessStatus.OK else ReadinessStatus.PROBLEM
        return ReadinessItem(id, status, title = words.title(), detail = detail, action = openDeadline(obligation.id))
    }

    /**
     * The green card comes with the RCA; a card filed on its own counts too, for the car whose
     * plate it names (one that names none counts for every car).
     */
    private fun greenCard(
        car: ReadinessAsset,
        plan: TripPlan,
        assets: List<ReadinessAsset>,
        today: CalendarDay,
    ): ReadinessItem {
        val rca = car.obligations[keys.vehicleRCA]
        val id = "trip.greenCard.${car.id.written}"
        val title = ReadinessPhrase.GreenCardTitle()
        val card = reading.documents(keys.greenCard, assets).filter { reading.covers(it, car) }
            .mapNotNull { card -> reading.expiry(card)?.let { card to it } }
            .maxWithOrNull(compareBy { it.second })
        return when {
            card != null && DueDayValidity.covers(plan.end, card.second) -> ReadinessItem(
                id, ReadinessStatus.OK, title = title, detail = ReadinessPhrase.ValidUntilFeminine(card.second),
                action = openSection(card.first.id),
            )
            rca != null && DueDayValidity.covers(plan.end, rca.due) -> ReadinessItem(
                id, ReadinessStatus.OK, title = title, detail = ReadinessPhrase.GreenCardWithRCA(),
                action = openDeadline(rca.id),
            )
            rca != null -> ReadinessItem(
                id, ReadinessStatus.PROBLEM, title = title,
                detail = if (rca.due < today) {
                    ReadinessPhrase.GreenCardRCAExpired()
                } else {
                    ReadinessPhrase.GreenCardRCAEnds()
                },
                action = openDeadline(rca.id),
            )
            else -> notInBinder(id, title, ReadinessPhrase.GreenCardNoRCA(), car, keys.vehicleRCA)
        }
    }

    /** The vignette is needed on Romanian roads: on the way to the border and on the way back. */
    private fun vignette(car: ReadinessAsset, plan: TripPlan, today: CalendarDay): ReadinessItem {
        val key = keys.vehicleVignette
        val id = "$key.${car.id.written}"
        val title = ReadinessPhrase.VignetteTitle()
        val vignette = car.obligations[key]
            ?: return notInBinder(id, title, ReadinessPhrase.VignetteMissing(), car, key)
        val due = vignette.due
        val (status, detail) = when {
            DueDayValidity.covers(plan.end, due) -> ReadinessStatus.OK to ReadinessPhrase.ValidUntilFeminine(due)
            DueDayValidity.covers(plan.start, due) ->
                ReadinessStatus.WARNING to ReadinessPhrase.VignetteEndsDuringTrip(due)
            due < today -> ReadinessStatus.PROBLEM to ReadinessPhrase.VignetteExpired(due)
            else -> ReadinessStatus.PROBLEM to ReadinessPhrase.VignetteEndsBeforeTrip(due)
        }
        return ReadinessItem(id, status, title = title, detail = detail, action = openDeadline(vignette.id))
    }

    /** Someone going has to drive: a licence valid until the trip ends. */
    private fun drivingLicence(
        car: ReadinessAsset,
        plan: TripPlan,
        assets: List<ReadinessAsset>,
        today: CalendarDay,
    ): ReadinessItem {
        val id = "trip.licence.${car.id.written}"
        val title = ReadinessWords.documentType(keys.drivingLicence)
        val going = plan.travellers.flatMap { reading.personalDocuments(it, assets) }
        val licence = reading.documents(keys.drivingLicence, going)
            .mapNotNull { licence -> reading.expiry(licence)?.let { licence to it } }
            .maxWithOrNull(compareBy { it.second })
        if (licence == null) {
            val firstMember = plan.travellers.filterIsInstance<TripTraveller.Member>()
                .map { it.id }.minByOrNull { it.written }
            return ReadinessItem(
                id, ReadinessStatus.MISSING, title = title, detail = ReadinessPhrase.LicenceMissing(),
                action = firstMember?.let { ReadinessAction.AddPersonalDocument(it) },
            )
        }
        val (document, until) = licence
        val (status, detail) = when {
            DueDayValidity.covers(plan.end, until) -> ReadinessStatus.OK to ReadinessPhrase.ValidUntil(until)
            until < today -> ReadinessStatus.PROBLEM to ReadinessPhrase.LicenceExpired(until)
            else -> ReadinessStatus.PROBLEM to ReadinessPhrase.LicenceEnds(until)
        }
        return ReadinessItem(id, status, title = title, detail = detail, action = openSection(document.id))
    }
}
