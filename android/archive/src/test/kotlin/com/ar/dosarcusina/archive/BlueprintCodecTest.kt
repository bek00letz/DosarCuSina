package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** A deadline's blueprint read from a backup reads as the iPhone reads it (`ObligationBlueprint.init(from:)`). */
class BlueprintCodecTest {
    private fun read(json: String): ObligationBlueprint =
        requireNotNull(ObligationBlueprint.codec.decode(Json.parseToJsonElement(json)))

    @Test
    fun aBlueprintThatDoesntSayWhetherItIsSuggestedIsSuggested() {
        val blueprint = read("""{"key": "itp", "title": "ITP", "kind": "legal"}""")
        assertTrue(blueprint.isSuggested, "A missing isSuggested reads as true, as on the iPhone")
    }

    @Test
    fun aBlueprintKeepsWhatItSays() {
        assertFalse(read("""{"key": "itp", "title": "ITP", "kind": "legal", "isSuggested": false}""").isSuggested)
        val suggested = read("""{"key": "itp", "title": "ITP", "kind": "legal", "isSuggested": true}""")
        assertEquals(true, suggested.isSuggested)
    }
}
