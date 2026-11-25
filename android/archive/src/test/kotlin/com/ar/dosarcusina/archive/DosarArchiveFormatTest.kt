package com.ar.dosarcusina.archive

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

class DosarArchiveFormatTest {
    private val shared = File(requireNotNull(System.getProperty("dosar.shared")) { "dosar.shared is set by the build" })

    @Test
    fun `the schema version is the specification's`() {
        val specification = shared.resolve("schemas/dosar-v${DosarArchiveFormat.SCHEMA_VERSION}.md")
        assertTrue(specification.isFile, "No specification at ${specification.path}")
        assertTrue(
            specification.readText().contains("\"schemaVersion\": ${DosarArchiveFormat.SCHEMA_VERSION},"),
            "The specification's manifest names another schema version",
        )
    }
}
