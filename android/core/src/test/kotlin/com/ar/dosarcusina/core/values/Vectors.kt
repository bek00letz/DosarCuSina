package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.DynamicTest
import java.io.File

/**
 * A folder of the iOS app's answers in shared/test-vectors/, written by one iOS test. Every
 * Kotlin test of a rule reads its file and must give the same answer for every case
 * (docs/ANDROID_PLAN.md, "How parity is kept").
 */
open class VectorFolder(
    private val folderName: String,
    /** Every file the Kotlin tests read; a test of the folder fails for one in it that isn't here. */
    val files: Set<String>,
    /** How to write the files again, said when one is missing. */
    private val writtenBy: String,
) {
    val folder: File
        get() {
            val shared = System.getProperty("dosar.shared")
                ?: error("The test task sets dosar.shared to the repository's shared/")
            return File(shared, "test-vectors/$folderName")
        }

    /** The cases of [name]. */
    fun cases(name: String): List<JsonObject> {
        require(name in files) { "$name isn't in the files of test-vectors/$folderName" }
        val file = File(folder, "$name.json")
        check(file.isFile) { "${file.path} is missing: run $writtenBy" }
        return MachineText.parse(file.readText()).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    /** One test per case of [name], named by what it reads. */
    fun tests(name: String, label: (JsonObject) -> String, check: (JsonObject) -> Unit): List<DynamicTest> =
        cases(name).mapIndexed { index, case ->
            DynamicTest.dynamicTest("$name #$index: ${label(case)}") { check(case) }
        }
}

/** The value rules' answers, in shared/test-vectors/values/, by ios/DosarCuSinaTests/ValueVectorsTests.swift. */
object Vectors : VectorFolder(
    folderName = "values",
    files = setOf(
        "app-calendar", "calendar-day-days", "calendar-day-months", "calendar-day-order", "calendar-day-parse",
        "calendar-day-valid", "json-doubles", "json-laying", "json-mapping-kept", "json-numbers", "kept-list",
        "kept-object", "machine-json-write", "machine-moment-read", "machine-moment-write", "machine-text",
        "measurement-unit", "money", "month-day", "romanian-number-canonical", "romanian-number-format",
        "romanian-number-read", "romanian-text-fold", "three-way",
    ),
    writtenBy = "the iOS ValueVectorsTests with TEST_RUNNER_VALUE_VECTORS_WRITE=1",
)

fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content

fun JsonObject.textOrNull(key: String): String? = this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

fun JsonObject.int(key: String): Int = getValue(key).jsonPrimitive.content.toInt()

fun JsonObject.long(key: String): Long = getValue(key).jsonPrimitive.content.toLong()

fun JsonObject.bool(key: String): Boolean = getValue(key).jsonPrimitive.content.toBooleanStrict()

fun JsonObject.isNull(key: String): Boolean = this[key] == null || this[key] is JsonNull

fun JsonObject.ints(key: String): List<Int> = getValue(key).jsonArray.map { it.jsonPrimitive.content.toInt() }

fun JsonObject.texts(key: String): List<String> = getValue(key).jsonArray.map { it.jsonPrimitive.content }

fun JsonElement.asTextOrNull(): String? = (this as? JsonPrimitive)?.takeUnless { this is JsonNull }?.content

fun JsonElement?.isNullOrMissing(): Boolean = this == null || this is JsonNull

/** A short name for a case: its input or name, shown in the test report. */
fun label(case: JsonObject, vararg keys: String): String =
    keys.firstNotNullOfOrNull { key ->
        case[key]?.let { if (it is JsonArray || it is JsonObject) it.toString() else it.asTextOrNull() }
    }
        ?.replace("\n", "\\n")?.take(60) ?: case.toString().take(60)
