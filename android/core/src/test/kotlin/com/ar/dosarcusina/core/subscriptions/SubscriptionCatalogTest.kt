package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.RecurrenceInterval
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/** What a subscription can be is the iOS app's, read whole from shared/catalog/subscriptions/. */
class SubscriptionCatalogTest {
    private val committed: File
        get() = File(checkNotNull(System.getProperty("dosar.shared")), "catalog/subscriptions/subscriptions.json")

    @Test
    fun `the build carries the committed catalog`() {
        val built = SubscriptionCatalog.read(committed.readText())
        val carried = SubscriptionCatalog.builtIn
        assertEquals(built.services, carried.services)
        assertEquals(built.codes, carried.codes)
        assertEquals(built.groups, carried.groups)
        assertEquals(built.billingCycles, carried.billingCycles)
    }

    @Test
    fun `every service names its group, its codes and its meter from the catalog`() {
        val catalog = SubscriptionCatalog.builtIn
        assertTrue(catalog.services.isNotEmpty())
        for (service in catalog.services) {
            assertTrue(service.group in catalog.groups, service.key)
            assertTrue(catalog.codes.containsAll(service.codes), service.key)
            service.meter?.let { assertTrue(it.defaultUnit != null, "${service.key}'s meter has a unit") }
        }
        assertTrue(catalog.unspecifiedService in catalog.services)
        assertEquals(RecurrenceInterval.months(1), catalog.unknownCycle)
    }

    @Test
    fun `each code's edit form condition is what its services say`() {
        for (code in SubscriptionCode.all) {
            val condition = code.editFormCondition
            val oneOf = condition.getValue("oneOf").jsonArray.map { it.jsonPrimitive.content }
            assertEquals(ServiceKind.keys(carrying = code), oneOf, code.name)
            val orWhenEmpty = condition["orWhenEmpty"]?.jsonPrimitive?.boolean ?: false
            assertEquals(code in ServiceKind.codes(null), orWhenEmpty, code.name)
        }
    }

    @Test
    fun `a catalog this build can't read is a broken build`() {
        val whole = MachineText.parse(committed.readText()).jsonObject
        assertThrows<SubscriptionCatalogError> { SubscriptionCatalog.read("not json") }
        val withoutServices = MachineText.json(JsonObject(whole - "services"))
        assertThrows<SubscriptionCatalogError> { SubscriptionCatalog.read(withoutServices) }
        val services = whole.getValue("services").jsonArray
        val strangeMeter = JsonObject(services[0].jsonObject + ("meter" to JsonPrimitive("thermometer")))
        val withStrangeMeter = JsonObject(whole + ("services" to JsonArray(listOf(strangeMeter) + services.drop(1))))
        assertThrows<SubscriptionCatalogError> { SubscriptionCatalog.read(MachineText.json(withStrangeMeter)) }
        val strangeCode = JsonObject(services[0].jsonObject + ("codes" to JsonArray(listOf(JsonPrimitive("iban")))))
        val withStrangeCode = JsonObject(whole + ("services" to JsonArray(listOf(strangeCode) + services.drop(1))))
        assertThrows<SubscriptionCatalogError> { SubscriptionCatalog.read(MachineText.json(withStrangeCode)) }
    }
}
