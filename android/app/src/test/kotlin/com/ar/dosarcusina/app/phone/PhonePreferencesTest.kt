package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.app.graph.PhoneLog
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.Executor

/** This phone's own small things: one file, read once, written whole, the latest values each time. */
class PhonePreferencesTest {
    @TempDir
    lateinit var root: File

    private val file by lazy { File(root, "preferences.json") }
    private val lines = ArrayList<String>()
    private val direct = Executor { it.run() }

    private fun preferences(writer: Executor = direct) = PhonePreferences(file, writer, PhoneLog(lines::add))

    @Test
    fun `what is kept is there the next time`() {
        preferences()["a"] = JsonPrimitive("one")
        assertEquals(JsonPrimitive("one"), preferences()["a"])
    }

    @Test
    fun `a key this build doesn't know is kept`() {
        file.writeText("""{"newer.key":{"deep":[1,2]},"a":"one"}""")
        val preferences = preferences()
        preferences["a"] = null
        assertEquals(MachineText.parse("""{"newer.key":{"deep":[1,2]}}"""), MachineText.parse(file.readText()))
    }

    @Test
    fun `a file that can't be read reads as empty, and the next change writes a good one`() {
        file.writeText("not json")
        val preferences = preferences()
        assertNull(preferences["a"])
        preferences["a"] = JsonPrimitive("one")
        assertEquals(JsonObject(mapOf("a" to JsonPrimitive("one"))), MachineText.parse(file.readText()))
    }

    @Test
    fun `a change is in memory at once and on disk when the writer gets to it, with the latest values`() {
        val waiting = ArrayList<Runnable>()
        val preferences = preferences { waiting += it }
        preferences["a"] = JsonPrimitive("one")
        preferences["a"] = JsonPrimitive("two")
        assertEquals(JsonPrimitive("two"), preferences["a"])
        assertFalse(file.exists())
        waiting.first().run()
        assertEquals(JsonObject(mapOf("a" to JsonPrimitive("two"))), MachineText.parse(file.readText()))
        waiting.last().run()
        assertEquals(JsonPrimitive("two"), preferences()["a"])
    }

    @Test
    fun `making it reads nothing, the first read does`() {
        val preferences = preferences()
        file.writeText("""{"a":"one"}""")
        assertEquals(JsonPrimitive("one"), preferences["a"])
    }

    @Test
    fun `a write that fails is logged by its kind and the value stays in memory`() {
        root.resolve("blocked").writeText("a file, not a folder")
        val preferences = PhonePreferences(File(root, "blocked/preferences.json"), direct, PhoneLog(lines::add))
        preferences["a"] = JsonPrimitive("one")
        assertEquals(JsonPrimitive("one"), preferences["a"])
        assertEquals(1, lines.size)
        assertTrue(lines.single().startsWith("ERROR Keeping this phone's preferences: "), lines.single())
    }
}
