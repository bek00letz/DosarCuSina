package com.ar.dosarcusina.app

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.w3c.dom.Element

/** What the manifest promises: the app that opens the binder, its name from the strings, and no internet. */
class ManifestTest {
    private val application =
        AppSources.xml("AndroidManifest.xml").getElementsByTagName("application").item(0) as Element

    @Test
    fun `the application opens the binder, in the app's one language, under its name`() {
        assertEquals(".DosarApplication", application.getAttribute("android:name"))
        assertEquals("@xml/locales_config", application.getAttribute("android:localeConfig"))
        assertEquals("@string/app_name", application.getAttribute("android:label"))
    }

    @Test
    fun `backups go only to a new phone`() {
        assertEquals("@xml/data_extraction_rules", application.getAttribute("android:dataExtractionRules"))
        assertEquals("@xml/backup_rules", application.getAttribute("android:fullBackupContent"))
    }

    @Test
    fun `the internet stays out`() {
        val permissions = AppSources.xml("AndroidManifest.xml").getElementsByTagName("uses-permission")
        val asked = (0 until permissions.length).map { permissions.item(it) as Element }
        assertEquals(listOf("android.permission.INTERNET"), asked.map { it.getAttribute("android:name") })
        assertEquals("remove", asked.single().getAttribute("tools:node"))
    }
}
