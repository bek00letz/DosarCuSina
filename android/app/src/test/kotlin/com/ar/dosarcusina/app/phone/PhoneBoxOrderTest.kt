package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.app.graph.PhoneLog
import com.ar.dosarcusina.catalog.BinderBoxID
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.UUID

/** The box order on this phone, under the iOS app's key, each box as the saved order writes it. */
class PhoneBoxOrderTest {
    @TempDir
    lateinit var root: File

    private val file by lazy { File(root, "preferences.json") }
    private val golf = UUID.fromString("0a6f2f0e-6f39-4a39-9b0a-6c1b1f3a0001")
    private val flat = UUID.fromString("0a6f2f0e-6f39-4a39-9b0a-6c1b1f3a0002")

    private fun order() = PhoneBoxOrder(PhonePreferences(file, { it.run() }, PhoneLog {}))

    @Test
    fun `the order is kept as the person left it`() {
        val order = listOf(BinderBoxID.Section(flat), BinderBoxID.Agenda, BinderBoxID.Category("documents"))
        order().save(order)
        assertEquals(order, order().saved)
        val kept = MachineText.parse(file.readText()).toString()
        assertEquals(
            """{"binder.boxOrder":["asset:${flat}","agenda","category:documents"]}""",
            kept,
        )
    }

    @Test
    fun `a box this build can't read is left out`() {
        file.writeText("""{"binder.boxOrder":["asset:${golf}","shelf:new",3,"agenda"]}""")
        assertEquals(listOf(BinderBoxID.Section(golf), BinderBoxID.Agenda), order().saved)
    }

    @Test
    fun `a category grouped into one box keeps the order around it`() {
        val order = order()
        order.save(listOf(BinderBoxID.Section(flat), BinderBoxID.Section(golf), BinderBoxID.Agenda))
        order.keepAround("vehicle", members = listOf(BinderBoxID.Section(golf)), grouped = true)
        assertEquals(
            listOf(BinderBoxID.Section(flat), BinderBoxID.Category("vehicle"), BinderBoxID.Agenda),
            order().saved,
        )
    }

    @Test
    fun `forgetting it gives the boxes their own order back`() = runBlocking {
        val order = order()
        order.save(listOf(BinderBoxID.Agenda))
        order.reset()
        assertTrue(order().saved.isEmpty())
        assertEquals(emptyList<BinderBoxID>(), order.changes.first())
    }
}
