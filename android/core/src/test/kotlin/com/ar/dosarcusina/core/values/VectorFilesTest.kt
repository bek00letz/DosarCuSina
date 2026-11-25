package com.ar.dosarcusina.core.values

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** Every file of the iOS app's answers is read by a Kotlin test, so a rule it adds can't go untested here. */
class VectorFilesTest {
    @Test
    fun `every file of answers is read by a test`() {
        val files = Vectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
        val present = files.map { it.nameWithoutExtension }.toSet()
        assertEquals(Vectors.files, present, "Each file of answers needs its test, and each test its file")
    }
}
