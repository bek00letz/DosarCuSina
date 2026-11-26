package com.ar.dosarcusina.app

import org.w3c.dom.Document
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/** The app's own sources (src/main), as the tests read them: its manifest and resources. */
object AppSources {
    private val main = File(requireNotNull(System.getProperty("dosar.appMain")) { "The test task sets dosar.appMain" })

    /** The XML file at [path] under src/main, its attributes named as written („android:name”). */
    fun xml(path: String): Document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(main, path))
}
