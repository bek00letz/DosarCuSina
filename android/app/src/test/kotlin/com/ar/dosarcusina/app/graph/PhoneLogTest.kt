package com.ar.dosarcusina.app.graph

import com.ar.dosarcusina.store.PersistenceLog
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import java.io.IOException

/** The phone's log keeps how bad, which step and the kind of error: never a value of the household's. */
class PhoneLogTest {
    private val lines = ArrayList<String>()
    private val log = PhoneLog(lines::add)

    @Test
    fun `a line is the level, the step and the kind`() {
        log.write(PersistenceLog.Entry(PersistenceLog.Level.FAULT, "A question asked after its unit wrote", "Kind"))
        assertEquals(listOf("FAULT A question asked after its unit wrote: Kind"), lines)
    }

    @Test
    fun `a failure's message never reaches the log`() {
        val values = listOf("1800101990006", "B-123-ABC", "nume@exemplu.ro", "4111 1111 1111 1111")
        log.attempt("Refreshing the repair list") {
            throw IOException("Could not keep ${values.joinToString()}")
        }
        assertEquals(listOf("ERROR Refreshing the repair list: java.io.IOException"), lines)
        for (value in values) assertFalse(lines.single().contains(value), value)
    }
}
