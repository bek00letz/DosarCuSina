package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.search.SearchPrivacy
import com.ar.dosarcusina.core.values.CalendarDay
import java.util.UUID

/**
 * Where the trips are kept on this phone: the seam to the app's own storage (Phase 4), never the
 * binder, its backups or search. [trips] is the list as kept; [singleTrip] the one trip an earlier
 * version kept before there could be several, if it is still there.
 */
interface TripPlanStorage {
    fun trips(): List<TripPlan>

    fun singleTrip(): TripPlan?

    /** Keeps [trips] as the list (none: nothing kept), and lets go of the one trip of before. */
    fun write(trips: List<TripPlan>)
}

/**
 * The trips the person described, as the iOS app's `TripPlanStore`
 * (ios/DosarCuSina/Services/Readiness/TripPlanStore.swift): several at once, each kept until it is
 * over, so a checklist opens where they left it. They are plans, not records, and each is forgotten
 * the day after it ends. Their one line in the person's words, where to, is remembered only as
 * search would ([SearchPrivacy.mayRemember]): a destination that holds a CNP or a card number is
 * left out, when it is kept and when it is read back.
 */
class TripPlans(private val storage: TripPlanStorage) {
    /**
     * Every trip kept that isn't over by [today], the soonest first: trips that ended are forgotten,
     * the one of before is brought across.
     */
    fun load(today: CalendarDay): List<TripPlan> {
        val loaded = Companion.load(storage.trips(), storage.singleTrip(), today)
        if (loaded.writes) storage.write(loaded.kept)
        return loaded.kept
    }

    /** Keeps [plan]: a new trip, or the one with its id, changed. */
    fun save(plan: TripPlan) {
        storage.write(saving(stored(), plan))
    }

    /** Forgets the trip with this id. */
    fun remove(id: UUID) {
        storage.write(stored().filter { it.id != id }.map(::remembered))
    }

    /** Forgets every trip. */
    fun clear() {
        storage.write(emptyList())
    }

    /** The trips as kept, with the one of before, if it is still there and not in the list. */
    private fun stored(): List<TripPlan> = withSingle(storage.trips(), storage.singleTrip())

    /** What loading gives: the trips still ahead, and whether the list kept must be written again. */
    data class Loaded(val kept: List<TripPlan>, val writes: Boolean)

    companion object {
        /** Soonest first: by start, then end, then id as the iOS app writes it. */
        val soonestFirst: Comparator<TripPlan> =
            compareBy<TripPlan> { it.start }.thenBy { it.end }.thenBy { it.id.written }

        /** The plan as this phone may remember it: its destination only when search could keep it. */
        fun remembered(plan: TripPlan): TripPlan =
            if (SearchPrivacy.mayRemember(plan.destination)) plan else plan.copy(destination = "")

        fun withSingle(trips: List<TripPlan>, single: TripPlan?): List<TripPlan> =
            if (single != null && trips.none { it.id == single.id }) trips + single else trips

        /**
         * The trips still ahead of [today], remembered and soonest first; written again when that
         * isn't what is kept, or the one of before is still there.
         */
        fun load(trips: List<TripPlan>, single: TripPlan?, today: CalendarDay): Loaded {
            val stored = withSingle(trips, single)
            val kept = stored.filter { !it.isOver(today) }.map(::remembered).sortedWith(soonestFirst)
            return Loaded(kept, kept != stored || single != null)
        }

        /** [stored] with [plan] in place of the trip with its id, or added, each remembered, soonest first. */
        fun saving(stored: List<TripPlan>, plan: TripPlan): List<TripPlan> =
            (stored.filter { it.id != plan.id } + plan).map(::remembered).sortedWith(soonestFirst)
    }
}
