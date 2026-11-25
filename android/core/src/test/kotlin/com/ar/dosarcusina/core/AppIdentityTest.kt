package com.ar.dosarcusina.core

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class AppIdentityTest {
    @Test
    fun `the app is known by the iPhone app's id`() {
        assertEquals("com.ar.dosarcusina.app", AppIdentity.APPLICATION_ID)
    }
}
