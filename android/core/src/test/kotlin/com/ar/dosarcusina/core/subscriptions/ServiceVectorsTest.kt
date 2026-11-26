package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/**
 * What a service is, how often a subscription is paid, where it is listed and the codes a paper keeps, as the iOS app
 * answers.
 */
class ServiceVectorsTest {
    @TestFactory
    fun services(): List<DynamicTest> =
        SubscriptionVectors.tests("services", { label(it, "text", "carrying") }) { case ->
            if (case.containsKey("carrying")) {
                val code = checkNotNull(SubscriptionCode.named(case.text("carrying")))
                assertEquals(case.texts("services"), ServiceKind.keys(carrying = code))
                return@tests
            }
            val text = case.optionalText("text")
            assertEquals(case.optionalText("service"), ServiceKind.service(text)?.key)
            assertEquals(case.bool("isTiedToHome"), ServiceKind.isTiedToHome(text))
            assertEquals(case.bool("sendsRegularBills"), ServiceKind.sendsRegularBills(text))
            assertEquals(case.optionalText("meter"), ServiceKind.meterKind(text)?.raw)
            assertEquals(case.texts("codes"), ServiceKind.codes(text).map { it.name })
            assertEquals(case.text("group"), SubscriptionGroup.of(text).key)
        }

    @TestFactory
    fun `billing cycles`(): List<DynamicTest> =
        SubscriptionVectors.tests("billing-cycle", { label(it, "text") }) { case ->
            assertEquals(case.getValue("interval").interval(), BillingCycle.interval(case.optionalText("text")))
        }

    @TestFactory
    fun groups(): List<DynamicTest> = SubscriptionVectors.tests("groups", { label(it, "service", "items") }) { case ->
        if (case.containsKey("listedIn")) {
            val stored = SubscriptionGroup.Stored(case.optionalText("group"), case.optionalText("service"))
            assertEquals(case.text("listedIn"), SubscriptionGroup.listedIn(stored).key)
            return@tests
        }
        val items = case.getValue("items").jsonArray.map { it.jsonObject }
        val listing = SubscriptionGroup.listing(items, case.bool("keepsGroups")) {
            SubscriptionGroup.Stored(it.optionalText("group"), it.optionalText("service"))
        }
        val expected = case.getValue("listing").jsonArray.map { it.jsonObject }
        assertEquals(expected.map { it.optionalText("group") }, listing.map { it.group?.key })
        assertEquals(expected.map { it.texts("items") }, listing.map { listed -> listed.items.map { it.text("name") } })
        for (rows in case.getValue("firstRows").jsonArray.map { it.jsonObject }) {
            val shown = SubscriptionGroup.firstRows(listing, rows.int("limit"))
            val wanted = rows.getValue("rows").jsonArray.map { it.jsonObject }
            assertEquals(
                wanted.map { it.optionalText("opens") to it.text("item") },
                shown.map { it.opens?.key to it.item.text("name") },
            )
        }
    }

    /** A field a paper read, as capture keeps it: its key and value. */
    private data class Field(val key: String, val value: String)

    private fun fields(case: JsonObject, name: String): List<Field> =
        case.getValue(name).jsonArray.map { it.jsonObject }.map { Field(it.text("key"), it.text("value")) }

    @TestFactory
    fun `codes a paper keeps`(): List<DynamicTest> =
        SubscriptionVectors.tests("codes-kept", { label(it, "service") }) { case ->
            val read = fields(case, "fields")
            val kept = SubscriptionCode.keeping(read, case.optionalText("service"), { it.key }) { field, key ->
                field.copy(key = key)
            }
            assertEquals(fields(case, "kept"), kept)
        }

    @Test
    fun `a code compares as the catalog says`() {
        val phone = SubscriptionCode.all.first { it.comparison == SubscriptionCode.Comparison.NATIONAL_PHONE_NUMBER }
        assertEquals("0712345678", phone.normalized("+40 712 345 678"))
        assertEquals("0712345678", phone.normalized("0040 712-345-678"))
        assertEquals("0712345678", phone.normalized("0712 345 678"))
        assertEquals("40712345", phone.normalized("40712345"), "Too short to be a number with its country code")
        val compact = SubscriptionCode.all.first { it.comparison == SubscriptionCode.Comparison.COMPACT }
        assertEquals("DEG0000000000001", compact.normalized("deg 0000-0000-0000-1"))
    }
}
