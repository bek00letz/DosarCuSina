package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.core.values.NamedChoice

/**
 * How a personal document is named: "<document> – <Surname Given names>", the way the household says
 * it ("Carte de identitate – Manole Corina"), as the iOS app's `DocumentNaming`
 * (ios/DosarCuSina/Services/Documents/DocumentNaming.swift). Capture, "Scriu eu" and moving a
 * document to another person all name it here.
 */
object DocumentNaming {
    /** The en dash with a space on each side, between the document and its holder. */
    const val SEPARATOR = " – "

    /** "Carte de identitate – Manole Corina", or just the document when there is no holder. */
    fun name(document: String, holder: String?): String {
        val trimmed = document.trim()
        val who = holder?.trim()
        return if (who.isNullOrEmpty()) trimmed else trimmed + SEPARATOR + who
    }

    /**
     * The name with the holder swapped, when it ends with the old holder's name (ignoring case and
     * diacritics). None when the name isn't the holder's, so a name the person chose ("Buletinul
     * vechi") is never rewritten.
     */
    fun renamed(name: String, from: String?, to: String): String? {
        val newHolder = to.trim()
        val oldHolder = from?.trim()
        val at = name.lastIndexOf(SEPARATOR)
        if (oldHolder.isNullOrEmpty() || newHolder.isEmpty() || at < 0) return null
        val document = name.substring(0, at)
        val holder = name.substring(at + SEPARATOR.length)
        val same = NamedChoice.fold(holder) == NamedChoice.fold(oldHolder)
        val changes = NamedChoice.fold(holder) != NamedChoice.fold(newHolder)
        return if (document.isNotBlank() && same && changes) name(document, newHolder) else null
    }

    /**
     * The name with the document swapped, when the person corrects its type ("Alt document – Manole
     * Corina" becomes "Pașaport – Manole Corina"): only when the name starts with the old type's own
     * name (ignoring case and diacritics), alone or before the holder, whose name stays as it is.
     * None otherwise, so a name the person chose is never rewritten.
     */
    fun retyped(name: String, from: String?, to: String): String? {
        val newDocument = to.trim()
        val trimmed = name.trim()
        val oldDocument = from?.trim()
        if (oldDocument.isNullOrEmpty() || newDocument.isEmpty()) return null
        if (NamedChoice.fold(oldDocument) == NamedChoice.fold(newDocument)) return null
        if (NamedChoice.fold(trimmed) == NamedChoice.fold(oldDocument)) return newDocument
        val at = trimmed.indexOf(SEPARATOR)
        if (at < 0 || NamedChoice.fold(trimmed.substring(0, at)) != NamedChoice.fold(oldDocument)) return null
        return name(newDocument, trimmed.substring(at + SEPARATOR.length))
    }
}
