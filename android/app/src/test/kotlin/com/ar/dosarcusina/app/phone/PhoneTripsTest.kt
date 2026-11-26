package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.app.graph.PhoneLog
import com.ar.dosarcusina.core.readiness.TripPlan
import com.ar.dosarcusina.core.readiness.TripPlans
import com.ar.dosarcusina.core.readiness.TripRegion
import com.ar.dosarcusina.core.readiness.TripTraveller
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.UUID

/** The trips on this phone only, in the iOS app's shape, each until it is over. */
class PhoneTripsTest {
    @TempDir
    lateinit var root: File

    private val file by lazy { File(root, "preferences.json") }
    private val ana = UUID.fromString("0a6f2f0e-6f39-4a39-9b0a-6c1b1f3a0010")
    private val golf = UUID.fromString("0a6f2f0e-6f39-4a39-9b0a-6c1b1f3a0011")
    private val today = day("2027-06-20")

    private fun trips() = TripPlans(PhoneTrips(PhonePreferences(file, { it.run() }, PhoneLog {})))

    private fun day(text: String) = requireNotNull(CalendarDay.parse(text))

    private fun greece() = TripPlan(
        id = UUID.fromString("0a6f2f0e-6f39-4a39-9b0a-6c1b1f3a0001"),
        start = day("2027-07-01"),
        end = day("2027-07-10"),
        region = TripRegion.EUROPEAN_UNION,
        destination = "Grecia",
        travellers = setOf(TripTraveller.Member(ana), TripTraveller.Unfiled),
        vehicles = setOf(golf),
    )

    @Test
    fun `a trip is there the next time, as it was`() {
        trips().save(greece())
        assertEquals(listOf(greece()), trips().load(today))
    }

    @Test
    fun `a trip is kept in the iOS app's shape`() {
        trips().save(greece())
        val kept = (MachineText.parse(file.readText()) as JsonObject).getValue(PhoneTrips.KEY) as JsonArray
        val expected = """
            {"id":"0A6F2F0E-6F39-4A39-9B0A-6C1B1F3A0001","start":"2027-07-01","end":"2027-07-10",
            "region":"europeanUnion","destination":"Grecia",
            "travellers":[{"member":{"_0":"0A6F2F0E-6F39-4A39-9B0A-6C1B1F3A0010"}},{"unfiled":{}}],
            "vehicles":["0A6F2F0E-6F39-4A39-9B0A-6C1B1F3A0011"],"pets":[]}
        """.trimIndent().replace("\n", "")
        assertEquals(MachineText.parse(expected), kept.single())
    }

    @Test
    fun `a trip that is over is forgotten`() {
        trips().save(greece())
        assertTrue(trips().load(day("2027-07-11")).isEmpty())
        assertNull((MachineText.parse(file.readText()) as JsonObject)[PhoneTrips.KEY])
    }

    @Test
    fun `a destination search wouldn't keep is never kept`() {
        trips().save(greece().copy(destination = "Grecia 1800101990006"))
        assertEquals("", trips().load(today).single().destination)
        assertFalse(file.readText().contains("1800101990006"))
    }

    @Test
    fun `a trip that can't be read is left out`() {
        file.writeText("""{"readiness.trips":[{"id":"x","start":"2027-07-01"},3]}""")
        assertTrue(trips().load(today).isEmpty())
    }
}
