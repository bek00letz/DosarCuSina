package com.ar.dosarcusina.core.subscriptions

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Every file of the iOS app's subscription answers is read by a Kotlin test, so a rule it adds can't go untested here.
 */
class SubscriptionVectorFilesTest {
    @Test
    fun `every file of answers is read by a test`() {
        val files = SubscriptionVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
        assertEquals(SubscriptionVectors.files, files.map { it.nameWithoutExtension }.toSet())
    }
}
