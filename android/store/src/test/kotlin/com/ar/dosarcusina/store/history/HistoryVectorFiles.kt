package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.Money
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.math.BigDecimal

/**
 * The iOS app's answers for a section's history (shared/test-vectors/history/, written by
 * ios/DosarCuSinaTests/HistoryVectorsTests.swift), read by the store's tests, and the small readers they share.
 */
internal object HistoryVectorFiles {
    fun cases(name: String): List<JsonObject> {
        val shared = requireNotNull(System.getProperty("dosar.shared")) { "The test task sets dosar.shared" }
        val file = File(shared, "test-vectors/history/$name.json")
        check(file.isFile) {
            "${file.path} is missing: run the iOS HistoryVectorsTests with TEST_RUNNER_HISTORY_VECTORS_WRITE=1"
        }
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    /** The case of [name] that carries the iOS words, and the others. */
    fun split(name: String): Pair<JsonObject, List<JsonObject>> {
        val all = cases(name)
        val words = all.single { "words" in it }.getValue("words").jsonObject
        return words to all.filter { "words" !in it }
    }
}

internal fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content

internal fun JsonObject.textOrNull(key: String): String? =
    this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

internal fun JsonObject.bool(key: String): Boolean = text(key).toBooleanStrict()

internal fun JsonObject.intOrNull(key: String): Int? = textOrNull(key)?.toInt()

internal fun JsonObject.doubleOrNull(key: String): Double? = textOrNull(key)?.toDouble()

internal fun JsonObject.obj(key: String): JsonObject? = this[key]?.takeUnless { it is JsonNull }?.jsonObject

internal fun JsonObject.objects(key: String): List<JsonObject> =
    this[key]?.takeUnless { it is JsonNull }?.jsonArray?.map { it.jsonObject }.orEmpty()

internal fun JsonObject.texts(key: String): List<String> =
    this[key]?.takeUnless { it is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content }.orEmpty()

/** An amount written as text in lei, as a case writes it. */
internal fun JsonObject.money(key: String): Money? = textOrNull(key)?.let { Money(BigDecimal(it)) }

/** A stored money object, as the archive writes one. */
internal fun money(json: JsonElement?): Money? = json?.takeUnless { it is JsonNull }?.let(Money::fromJson)

/** An amount as compared: one form for one value. */
internal fun amount(value: BigDecimal?): BigDecimal? = value?.stripTrailingZeros()

/** The words a record's title is written with, as the iOS app has them (titles.json's words). */
internal class VectorWording(private val words: JsonObject) : HistoryWording {
    override fun entryTitle(kind: VisitKind?): String = words.text(kind?.raw ?: "visit")

    override fun manyJobs(count: Int): String = requireNotNull(words.obj("manyJobs")).text(count.toString())
}

/** The iOS words of the titles, read once. */
internal val vectorWording: VectorWording by lazy { VectorWording(HistoryVectorFiles.split("titles").first) }
