package com.ar.dosarcusina.app.locale

import com.ar.dosarcusina.app.AppSources
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.w3c.dom.Element
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** The app writes Romanian on every phone: one language declared, the one the app applies. */
class AppLocaleTest {
    @Test
    fun `the app declares one language, Romanian`() {
        val locales = AppSources.xml("res/xml/locales_config.xml").getElementsByTagName("locale")
        assertEquals(1, locales.length)
        assertEquals(AppLocale.TAG, (locales.item(0) as Element).getAttribute("android:name"))
    }

    @Test
    fun `the default resources are Romanian`() {
        for (file in listOf("res/values/app.xml", "res/values/strings.xml")) {
            assertEquals(AppLocale.TAG, AppSources.xml(file).documentElement.getAttribute("tools:locale"), file)
        }
    }

    @Test
    fun `the app's language is kept only when it is Romanian alone`() {
        assertTrue(AppLocale.isApplied("ro"))
        assertFalse(AppLocale.isApplied(""))
        assertFalse(AppLocale.isApplied("en-US"))
        assertFalse(AppLocale.isApplied("ro,en-US"))
    }

    @Test
    fun `the app's language writes dates in Romanian`() {
        val day = LocalDate.of(2027, 3, 3)
        assertEquals("3 martie 2027", DateTimeFormatter.ofPattern("d MMMM yyyy", AppLocale.locale).format(day))
    }
}
