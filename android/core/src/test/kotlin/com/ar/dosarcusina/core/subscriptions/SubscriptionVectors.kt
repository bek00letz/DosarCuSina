package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RecurrenceInterval
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.int
import com.ar.dosarcusina.core.values.text
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID

/**
 * The subscription engines' answers, in shared/test-vectors/subscriptions/, by
 * ios/DosarCuSinaTests/SubscriptionVectorsTests.swift.
 */
object SubscriptionVectors : VectorFolder(
    folderName = "subscriptions",
    files = setOf(
        "address-agreement", "bill-reminders", "bill-trend", "billing-cycle", "codes-kept", "groups", "homes",
        "matcher", "meter", "missing-bill", "missing-bills", "monthly", "postal-address", "provider-names", "services",
    ),
    writtenBy = "the iOS SubscriptionVectorsTests with TEST_RUNNER_SUBSCRIPTION_VECTORS_WRITE=1",
)

/** A case's text, or null for none (JSON null or missing). */
fun JsonObject.optionalText(key: String): String? = this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

fun JsonObject.day(key: String): CalendarDay = checkNotNull(CalendarDay.parse(text(key))) { "$key isn't a day" }

/** A money object as a case writes it (`{"amount": "12.5", "currency": "RON"}`), or null. */
fun JsonElement?.money(): Money? {
    val fields = this?.takeUnless { it is JsonNull }?.jsonObject ?: return null
    return checkNotNull(Money.of(fields.text("amount"), fields.text("currency"))) { "$fields isn't money" }
}

/** An interval as a case writes it (`{"every": 3, "unit": "month"}`). */
fun JsonElement.interval(): RecurrenceInterval {
    val fields = jsonObject
    return RecurrenceInterval.of(fields.int("every"), checkNotNull(RecurrenceInterval.Unit.stored(fields.text("unit"))))
}

fun JsonObject.uuid(key: String): UUID = UUID.fromString(text(key))

fun JsonObject.optionalUuid(key: String): UUID? = optionalText(key)?.let(UUID::fromString)
