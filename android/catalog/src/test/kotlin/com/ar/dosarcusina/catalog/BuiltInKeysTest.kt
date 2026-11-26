package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.lang.reflect.Modifier

/**
 * The keys Android code names (BuiltInKeys.kt) are the ones the iOS app names, as it exported
 * them in shared/catalog/keys.json: each Swift type an object of the same name, each constant its
 * Swift name in capitals, both ways, so a key added or renamed on iOS fails here.
 */
class BuiltInKeysTest {
    @Test
    fun theConstantsAreTheExportedKeys() {
        val exported = exported()
        for ((type, keys) in exported) {
            val constants = constants(type)
            assertEquals(
                keys.mapKeys { (name, _) -> constantName(name) },
                constants,
                "$type: BuiltInKeys.kt names what keys.json does",
            )
        }
        assertEquals(
            setOf(
                "VehicleFields", "HomeFields", "DocumentFields", "MemberFields", "PetFields", "PurchaseFieldKeys",
                "SubscriptionFields", "BuiltInBlueprints", "BuiltInTemplates.Key",
            ),
            exported.keys,
            "Every type keys.json lists has its object here",
        )
    }

    @Test
    fun aSwiftNameInCapitals() {
        assertEquals("POLICY_NUMBER", constantName("policyNumber"))
        assertEquals("HEALTH_EU_CARD", constantName("healthEUCard"))
        assertEquals("VEHICLE_ITP", constantName("vehicleITP"))
        assertEquals("HOME_PAD", constantName("homePAD"))
        assertEquals("VIN", constantName("vin"))
    }

    companion object {
        /** keys.json: each Swift type's constants, by name. */
        fun exported(): Map<String, Map<String, String>> {
            val keys = (MachineText.parse(committed(Catalog.File.KEYS)) as JsonObject).getValue("keys") as JsonObject
            return keys.mapValues { (_, constants) ->
                (constants as JsonObject).mapValues { (_, key) -> (key as JsonPrimitive).content }
            }
        }

        /** A Swift constant's name as a Kotlin constant's: `cascoPolicyNumber` is `CASCO_POLICY_NUMBER`. */
        fun constantName(swift: String): String =
            swift.replace(Regex("(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"), "_").uppercase()

        /** The string constants of the object named after a Swift type (`BuiltInTemplates.Key` is nested). */
        private fun constants(type: String): Map<String, String> {
            val kind = Class.forName("com.ar.dosarcusina.catalog." + type.replace('.', '$'))
            return kind.declaredFields
                .filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }
                .associate { it.name to it.get(null) as String }
        }
    }
}
