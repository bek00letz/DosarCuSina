package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.label
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.texts
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.util.UUID

/**
 * What a subscription costs a month, its bills' trend, the bill that hasn't come and the bill reminder, as the iOS app
 * answers.
 */
class BillVectorsTest {
    @TestFactory
    fun monthly(): List<DynamicTest> =
        SubscriptionVectors.tests("monthly", { label(it, "price", "equivalentOf") }) { case ->
            val expected = case["monthly"].money()
            val equivalent = case["equivalentOf"]?.jsonObject
            val worked = if (equivalent == null) {
                SubscriptionMath.monthly(checkNotNull(case["price"].money()), case.getValue("every").interval())
            } else {
                SubscriptionMath.monthlyEquivalent(
                    price = equivalent["price"].money(), lastBill = equivalent["lastBill"].money(),
                    cycle = equivalent.optionalText("cycle"), usingLastBill = equivalent.bool("usingLastBill"),
                )
            }
            assertEquals(expected, worked)
        }

    private fun bills(case: JsonObject): List<BillRecord> =
        case.getValue("bills").jsonArray.map { it.jsonObject }.map { BillRecord(it.day("day"), it["amount"].money()) }

    @TestFactory
    fun `bill trends`(): List<DynamicTest> = SubscriptionVectors.tests("bill-trend", { label(it, "bills") }) { case ->
        val trend = BillHistory.trend(bills(case), case.day("today"))
        if (case.isNull("trend")) {
            assertNull(trend)
            return@tests
        }
        val expected = case.getValue("trend").jsonObject
        val last = expected.getValue("last").jsonObject
        checkNotNull(trend)
        assertEquals(BillRecord(last.day("day"), last["amount"].money()), trend.last)
        assertEquals(expected["change"].money(), trend.change)
        assertEquals(expected.optionalText("direction"), trend.direction?.name?.lowercase())
        val averages = expected.getValue("averageLastYear").jsonArray.map { checkNotNull(it.money()) }
        assertEquals(averages, trend.averageLastYear)
    }

    private fun days(case: JsonObject): List<BillRecord> =
        case.texts("days").map { BillRecord(checkNotNull(CalendarDay.parse(it)), null) }

    @TestFactory
    fun `the missing bill`(): List<DynamicTest> =
        SubscriptionVectors.tests("missing-bill", { label(it, "days") }) { case ->
            val cycle = case.getValue("cycle").interval()
            val missing = BillHistory.missing(days(case), cycle, case.day("today"))
            val expected = case["missing"]?.takeUnless { it is JsonNull }?.jsonObject
            assertEquals(expected?.let { MissingBill(it.day("lastDay"), it.day("expectedDay"), cycle) }, missing)
        }

    @TestFactory
    fun `the missing bills of a binder`(): List<DynamicTest> =
        SubscriptionVectors.tests("missing-bills", { label(it, "today") }) { case ->
            val watches = case.getValue("subscriptions").jsonArray.map { it.jsonObject }.map {
                BillWatch(
                    id = it.uuid("id"), service = it.optionalText("service"), cycle = it.getValue("cycle").interval(),
                    bills = days(it), isSensitive = it.bool("isSensitive"), isExample = it.bool("isExample"),
                )
            }
            val found = MissingBills.find(watches, case.day("today"))
            val expected = case.getValue("missing").jsonArray.map { it.jsonObject }
                .map { it.uuid("id") to it.day("expectedDay") }
            assertEquals(expected, found.map { it.id to it.missing.expectedDay })
            val sensitive = watches.filter { it.isSensitive }.map { it.id }.toSet()
            assertEquals(found.map { it.id in sensitive }, found.map { it.isSensitive })
        }

    @TestFactory
    fun `the bill reminder follows direct debit`(): List<DynamicTest> =
        SubscriptionVectors.tests("bill-reminders", { label(it, "reminders") }) { case ->
            val reminders = case.getValue("reminders").jsonArray.map { it.jsonObject }
            val bills = reminders.mapIndexed { index, reminder ->
                val status = ObligationStatus.stored(reminder.text("status"))
                BillReminders.BillDeadline(UUID(0, index.toLong()), status, reminder.day("due"))
            }
            val before = case.optionalText("directDebitBefore")?.toBooleanStrict() ?: false
            val followed = BillReminders.follow(before, case.bool("directDebitAfter"), bills, case.day("today"))
            assertEquals(case.optionalText("change"), followed?.change?.name?.lowercase())
            val after = bills.map { bill ->
                when {
                    followed == null || bill.id !in followed.deadlines -> bill.status
                    followed.change == BillReminders.Change.PAUSED -> ObligationStatus.PAUSED
                    else -> ObligationStatus.ACTIVE
                }
            }
            assertEquals(case.texts("statusesAfter"), after.map { it.raw })
        }
}
