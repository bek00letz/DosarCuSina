package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.core.readiness.TripPlan
import com.ar.dosarcusina.core.readiness.TripPlanStorage
import com.ar.dosarcusina.core.readiness.TripPlans
import com.ar.dosarcusina.core.readiness.TripRegion
import com.ar.dosarcusina.core.readiness.TripTraveller
import com.ar.dosarcusina.core.values.CalendarDay
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.Locale
import java.util.UUID

/**
 * Where the trips are kept on this phone, never in the binder, its backups or search: the iOS app's
 * `TripPlanStore`, under its key and in the shape its JSON gives a trip. What is kept and for how long
 * is [TripPlans]'s. Android never kept the one trip of before there could be several, so there is
 * none to bring across. A trip that can't be read is left out.
 */
class PhoneTrips(private val preferences: PhonePreferences) : TripPlanStorage {
    override fun trips(): List<TripPlan> =
        (preferences[KEY] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(TripJson::plan) }

    override fun singleTrip(): TripPlan? = null

    override fun write(trips: List<TripPlan>) {
        preferences[KEY] = if (trips.isEmpty()) null else JsonArray(trips.map(TripJson::json))
    }

    companion object {
        /** The iOS app's key. */
        const val KEY = "readiness.trips"
    }
}

/** A trip in the shape the iOS app's JSON gives it: days as ISO text, ids in capitals, a traveller by its case. */
internal object TripJson {
    private const val MEMBER = "member"
    private const val UNFILED = "unfiled"

    /** The case's one value, as Swift names it. */
    private const val VALUE = "_0"

    fun json(plan: TripPlan): JsonObject = JsonObject(
        mapOf(
            "id" to JsonPrimitive(written(plan.id)),
            "start" to JsonPrimitive(plan.start.isoString),
            "end" to JsonPrimitive(plan.end.isoString),
            "region" to JsonPrimitive(plan.region.raw),
            "destination" to JsonPrimitive(plan.destination),
            "travellers" to JsonArray(plan.travellers.sortedBy { it.key }.map(::traveller)),
            "vehicles" to ids(plan.vehicles),
            "pets" to ids(plan.pets),
        ),
    )

    fun plan(json: JsonObject): TripPlan? {
        val start = PhoneJson.text(json["start"])?.let { CalendarDay.parse(it) } ?: return null
        val end = PhoneJson.text(json["end"])?.let { CalendarDay.parse(it) } ?: return null
        val region = PhoneJson.text(json["region"])?.let { raw -> TripRegion.entries.firstOrNull { it.raw == raw } }
            ?: return null
        return TripPlan(
            id = PhoneJson.text(json["id"])?.let(::id) ?: UUID.randomUUID(),
            start = start,
            end = end,
            region = region,
            destination = PhoneJson.text(json["destination"]).orEmpty(),
            travellers = (json["travellers"] as? JsonArray).orEmpty().mapNotNull(::traveller).toSet(),
            vehicles = PhoneJson.strings(json["vehicles"]).mapNotNull(::id).toSet(),
            pets = PhoneJson.strings(json["pets"]).mapNotNull(::id).toSet(),
        )
    }

    private fun traveller(traveller: TripTraveller): JsonObject = when (traveller) {
        is TripTraveller.Member -> case(MEMBER, mapOf(VALUE to JsonPrimitive(written(traveller.id))))
        TripTraveller.Unfiled -> case(UNFILED, emptyMap())
    }

    private fun case(name: String, values: Map<String, JsonElement>) = JsonObject(mapOf(name to JsonObject(values)))

    private fun traveller(json: JsonElement): TripTraveller? {
        val case = json as? JsonObject ?: return null
        if (UNFILED in case) return TripTraveller.Unfiled
        val member = case[MEMBER] as? JsonObject ?: return null
        return PhoneJson.text(member[VALUE])?.let(::id)?.let(TripTraveller::Member)
    }

    private fun ids(ids: Set<UUID>): JsonArray = PhoneJson.list(ids.map(::written).sorted())

    private fun written(id: UUID): String = id.toString().uppercase(Locale.ROOT)

    private fun id(text: String): UUID? = runCatching { UUID.fromString(text) }.getOrNull()
}
