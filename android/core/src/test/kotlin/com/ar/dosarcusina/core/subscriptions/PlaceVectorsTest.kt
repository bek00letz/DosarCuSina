package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/** Addresses, the homes they name and where a bill or a contract belongs, as the iOS app answers. */
class PlaceVectorsTest {
    @TestFactory
    fun `postal addresses`(): List<DynamicTest> =
        SubscriptionVectors.tests("postal-address", { label(it, "text", "isMarker", "namesOnlyThePlace") }) { case ->
            when {
                case.containsKey("isMarker") ->
                    assertEquals(case.bool("answer"), PostalAddress.isMarker(case.text("isMarker")))
                case.containsKey("namesOnlyThePlace") ->
                    assertEquals(case.bool("answer"), PostalAddress.namesOnlyThePlace(case.text("namesOnlyThePlace")))
                else -> {
                    val address = PostalAddress.read(case.text("text"))
                    if (case.isNull("address")) {
                        assertNull(address)
                    } else {
                        assertEquals(parts(case.getValue("address").jsonObject), address)
                    }
                }
            }
        }

    private fun parts(json: JsonObject) = PostalAddress(
        street = json.texts("street"), streetType = json.optionalText("streetType"),
        number = json.optionalText("number"), block = json.optionalText("block"),
        staircase = json.optionalText("staircase"), apartment = json.optionalText("apartment"),
        sector = json.optionalText("sector"), locality = json.texts("locality"), county = json.texts("county"),
    )

    @TestFactory
    fun `address agreements`(): List<DynamicTest> =
        SubscriptionVectors.tests("address-agreement", { label(it, "a") }) { case ->
            val a = checkNotNull(PostalAddress.read(case.text("a")))
            val b = checkNotNull(PostalAddress.read(case.text("b")))
            assertEquals(case.text("agreement"), a.agreement(b).name.lowercase())
        }

    private fun homes(case: JsonObject): List<SubscriptionMatcher.Home> =
        case.getValue("homes").jsonArray.map { it.jsonObject }.map {
        SubscriptionMatcher.Home(it.uuid("id"), it.optionalText("address"), texts(it.getValue("fields")))
    }

    private fun texts(element: JsonElement): Map<String, String> =
        element.jsonObject.mapValues { it.value.jsonPrimitive.content }

    private fun check(value: SubscriptionMatcher.HouseCheck?): String? = value?.let {
        when (it) {
            SubscriptionMatcher.HouseCheck.ADDRESS_PARTLY_AGREES -> "addressPartlyAgrees"
            SubscriptionMatcher.HouseCheck.ADDRESS_DIFFERS -> "addressDiffers"
        }
    }

    private fun picked(pick: SubscriptionMatcher.HousePick): Pair<String, String?> =
        pick.id.toString() to check(pick.check)

    private fun pick(element: JsonElement?): Pair<String, String?>? =
        element?.takeUnless { it is JsonNull }?.jsonObject?.let { it.uuid("id").toString() to it.optionalText("check") }

    @TestFactory
    fun homes(): List<DynamicTest> = SubscriptionVectors.tests("homes", { label(it, "address") }) { case ->
        val homes = homes(case)
        val address = case.optionalText("address")
        assertEquals(pick(case["house"]), SubscriptionMatcher.house(address, homes)?.let(::picked))
        assertEquals(pick(case["home"]), SubscriptionMatcher.home(address, homes)?.let(::picked))
    }

    @TestFactory
    fun `where a paper belongs`(): List<DynamicTest> =
        SubscriptionVectors.tests("matcher", { label(it, "name") }) { case ->
            val read = case.getValue("reading").jsonObject
            val reading = SubscriptionMatcher.Reading(
                provider = read.optionalText("provider"), service = read.optionalText("service"),
                codes = texts(read.getValue("codes")).mapKeys { checkNotNull(SubscriptionCode.named(it.key)) },
                isBill = read.bool("isBill"), supplyAddress = read.optionalText("supplyAddress"),
            )
            val subscriptions = case.getValue("subscriptions").jsonArray.map { it.jsonObject }.map {
                val fields = texts(it.getValue("fields"))
                SubscriptionMatcher.Subscription(
                    id = it.uuid("id"), parentId = it.optionalUuid("parentID"), provider = it.optionalText("provider"),
                    service = it.optionalText("service"), codes = SubscriptionCode.kept { key -> fields[key] },
                )
            }
            assertEquals(case.texts("keptCodes"), SubscriptionCode.all.filter { it in reading.codes }.map { it.name })
            assertEquals(case.bool("isTiedToHome"), reading.isTiedToHome)
            val placement = SubscriptionMatcher.place(reading, subscriptions, homes(case), case.optionalUuid("within"))
            val decision = case.getValue("decision").jsonObject
            assertEquals(decision.text("type") to decision.optionalUuid("id")?.toString(), written(placement.decision))
            assertEquals(case.optionalText("check"), check(placement.check))
        }

    private fun written(decision: SubscriptionMatcher.Decision): Pair<String, String?> = when (decision) {
        is SubscriptionMatcher.Decision.Existing -> "existing" to decision.id.toString()
        is SubscriptionMatcher.Decision.NewUnder -> "newUnder" to decision.home.toString()
        SubscriptionMatcher.Decision.NewStandalone -> "newStandalone" to null
        SubscriptionMatcher.Decision.Undecided -> "undecided" to null
    }

    @TestFactory
    fun `provider names`(): List<DynamicTest> =
        SubscriptionVectors.tests("provider-names", { label(it, "name") }) { case ->
            val name = case.text("name")
            assertEquals(case.text("short"), SubscriptionMatcher.shortProviderName(name))
            assertEquals(case.texts("words"), SubscriptionMatcher.providerWords(name).sorted())
        }
}
