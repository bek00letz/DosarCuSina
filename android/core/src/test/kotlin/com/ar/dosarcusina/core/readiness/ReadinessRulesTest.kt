package com.ar.dosarcusina.core.readiness

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/** The checks' own rules, beside the iOS answers: the sentences are the iOS app's, and the travel data reads whole. */
class ReadinessRulesTest {
    private val repository: File
        get() = File(requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" })
            .parentFile

    @Test
    fun `every sentence is one the iOS app says, and every one it says is here`() {
        val source = File(repository, "ios/DosarCuSina/Services/Readiness/ReadinessWords.swift").readText()
        val cases = Regex("""^ {4}case (\w+)""", RegexOption.MULTILINE).findAll(source)
            .map { it.groupValues[1] }.toList()
        assertTrue(cases.isNotEmpty(), "No cases found in ReadinessWords.swift")
        assertEquals(cases, ReadinessPhrase.entries.map { it.raw }, "ReadinessPhrase lists the iOS cases, in order")
    }

    @Test
    fun `an optional check that isn't ready is only suggested`() {
        for (found in ReadinessStatus.entries) {
            val ready = found == ReadinessStatus.OK || found == ReadinessStatus.REMINDER
            val expected = if (ready) found else ReadinessStatus.SUGGESTED
            assertEquals(expected, ReadinessItem.status(found, ReadinessNeed.OPTIONAL), "$found, optional")
            assertEquals(found, ReadinessItem.status(found, ReadinessNeed.REQUIRED), "$found, required")
        }
        assertFalse(ReadinessStatus.SUGGESTED.needsAttention)
    }

    @Test
    fun `the travel data this build carries reads whole`() {
        val data = TravelData.builtIn
        for (group in CitizenshipGroup.entries) {
            for (region in TripRegion.entries) {
                for (requirement in data.rules.requirements(group, region)) {
                    assertTrue(requirement.accepted.isNotEmpty(), "$group in $region")
                }
            }
        }
        // A citizen whose group is known always carries something outside the EU.
        for (group in CitizenshipGroup.entries - CitizenshipGroup.UNKNOWN) {
            assertTrue(data.rules.requirements(group, TripRegion.OUTSIDE_EU).isNotEmpty(), "$group")
        }
        assertTrue(data.rules.identityCards.values.all { it.source.isNotBlank() }, "Each card rule has a source")
        assertEquals(data.citizenship.stateless, data.citizenship.options.last().key, "„Fără cetățenie” comes last")
    }

    @Test
    fun `a file this build can't read fails the build, never the binder`() {
        val files = TravelData.File.entries.associateWith(TravelData::resource)
        val rules = files.getValue(TravelData.File.RULES).replace("\"europeanUnion\"", "\"atlantis\"")
        val broken = files + (TravelData.File.RULES to rules)
        assertThrows<TravelError> { TravelData.read { broken.getValue(it) } }
    }

    @Test
    fun `travel data for a type the catalog doesn't declare is an export out of step`() {
        val files = TravelData.File.entries.associateWith(TravelData::resource)
        val documents = files.getValue(TravelData.File.DOCUMENTS)
            .replace("\"documentType.passport\"", "\"documentType.atlantis\"")
        val broken = files + (TravelData.File.DOCUMENTS to documents)
        assertThrows<TravelError> { TravelData.read { broken.getValue(it) } }
    }
}
