package com.ar.dosarcusina.core.capture

import com.ar.dosarcusina.core.search.SearchText
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** The capture lexicon the build carries can't be read: a broken build, never something to guess around. */
class CaptureLexiconError(message: String) : IllegalStateException(message)

/**
 * The words the shared readers look for that are no one kind's, as the iOS app declares them once
 * (`CaptureLexicon` in ios/DosarCuSina/Services/Capture/CaptureLexicon.swift): exported by its tests to
 * `shared/catalog/capture/lexicon.json` (`CaptureLexiconExportTests`), copied into this module's resources
 * as it is built, and read here. Android never keeps a list of its own. Today it holds what a line of work
 * is that is never a part ([labourWords]); capture's other words come with capture (Phase 5).
 */
class CaptureLexicon private constructor(
    /**
     * Words of a line that is the work itself, never a part or a job done to one: the labour ("Manoperă
     * 1,5 ore", „mână de lucru”, hours worked), folded. Each matches only where a word starts, so it reaches
     * its endings („manoperei”) and nothing longer: never "labor", which a laboratory's „laborator” starts with.
     */
    val labourWords: List<String>,
) {
    companion object {
        private const val RESOURCE = "/com/ar/dosarcusina/core/capture/lexicon.json"

        /** The lexicon this build carries, read once. */
        val builtIn: CaptureLexicon by lazy {
            val stream = CaptureLexicon::class.java.getResourceAsStream(RESOURCE)
                ?: throw CaptureLexiconError("lexicon.json isn't in the build: core copies shared/catalog/capture/")
            read(stream.use { it.readBytes().decodeToString() })
        }

        /** The lexicon in [text], as `lexicon.json` writes it. */
        fun read(text: String): CaptureLexicon {
            val words = ((MachineText.parseOrNull(text) as? JsonObject)?.get("labourWords") as? JsonArray)
                ?.map { word -> (word as? JsonPrimitive)?.takeIf { it.isString }?.content }
            val text = words?.filterNotNull()?.takeIf { it.size == words.size }
                ?: throw CaptureLexiconError("lexicon.json's labourWords aren't text")
            return CaptureLexicon(text)
        }
    }
}

/**
 * Labour lines aren't parts, so they never get a part's key, as the iOS app's `LabourLine`
 * (ios/DosarCuSina/Services/Capture/CaptureComponentResolver.swift): wherever a line item is written (a
 * captured invoice's line, a row the person typed, an import), one this rule calls labour is kept as the
 * visit's labour cost, and nothing that lists parts (Istoric's pocket, search's „Piese și lucrări”, when a
 * part was last done) counts it. Its words are capture's ([CaptureLexicon.labourWords]).
 */
object LabourLine {
    /** Whether [description] is labour: one of the lexicon's words starts a word of it, in order. */
    fun matches(description: String, lexicon: CaptureLexicon = CaptureLexicon.builtIn): Boolean {
        val text = SearchText.normalize(description)
        return lexicon.labourWords.any { SearchText.containsPhrase(text, it) }
    }

    /**
     * The names of what was done, without the labour: what a visit's title counts and names. A visit that
     * lists only labour keeps it, so its title still says what it was.
     */
    fun work(names: List<String>, lexicon: CaptureLexicon = CaptureLexicon.builtIn): List<String> {
        val work = names.filterNot { matches(it, lexicon) }
        return work.ifEmpty { names }
    }
}
