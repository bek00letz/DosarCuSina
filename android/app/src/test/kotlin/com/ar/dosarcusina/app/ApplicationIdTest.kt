package com.ar.dosarcusina.app

import com.ar.dosarcusina.core.AppIdentity
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class ApplicationIdTest {
    @Test
    fun `the build ships under the app's one id`() {
        assertEquals(AppIdentity.APPLICATION_ID, BuildConfig.APPLICATION_ID)
    }
}
