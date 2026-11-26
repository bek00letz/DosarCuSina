package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.TextRules

/**
 * Reads an address's parts, as the iOS app's `PostalAddress.parse`: folded text in segments (split at commas,
 * semicolons, new lines and bars), each read token by token, a printed marker ("Str.", "nr.", "bl.", "jud.")
 * saying what the tokens after it are.
 */
internal class PostalAddressParser {
    val street = mutableListOf<String>()
    var streetType: String? = null
    var number: String? = null
    var block: String? = null
    var staircase: String? = null
    var apartment: String? = null
    var sector: String? = null
    var locality = mutableListOf<String>()
    val county = mutableListOf<String>()

    /** Whether any address marker was printed ("nr.", "bl.", "ap.", "sector", a town). */
    var hasMarkers = false
        private set

    /** A number read without "nr." ("Str. Exemplului 1"); a printed "nr." replaces it. */
    private var numberIsInferred = false
    private var seenStreet = false

    /** What a printed marker introduces. */
    enum class Marker { STREET_TYPE, NUMBER, BLOCK, STAIRCASE, FLOOR, APARTMENT, SECTOR, COUNTY, POSTAL_CODE, LOCALITY }

    fun address(): PostalAddress = PostalAddress(
        street = street.toList(), streetType = streetType, number = number, block = block, staircase = staircase,
        apartment = apartment, sector = sector, locality = locality.toList(), county = county.toList(),
    )

    fun parse(text: String) {
        val folded = RomanianText.fold(text).replace("b-dul", "bd ")
        for (segment in segments(folded)) read(tokens(segment))
    }

    /** One segment's tokens. */
    private fun read(tokens: List<String>) {
        val segment = Segment(tokens)
        while (segment.index < tokens.size) {
            val token = tokens[segment.index]
            when {
                // "cod poștal 012345" is not the street's number.
                token == "cod" && tokens.getOrNull(segment.index + 1) == "postal" -> segment.index += POSTAL_CODE_TOKENS
                token == CAPITAL -> {
                    hasMarkers = true
                    if (token !in locality) locality.add(token)
                    segment.filling = null
                    segment.index += 1
                }
                token in IGNORED -> segment.index += 1
                MARKERS[token] != null -> marked(segment, token, MARKERS.getValue(token))
                else -> {
                    unmarked(segment, token)
                    segment.index += 1
                }
            }
        }
        if (street.isNotEmpty()) seenStreet = true
        if (segment.loose.isNotEmpty()) looseWords(segment.loose)
    }

    /** Where a segment's reading stands: the token it is at, what the tokens fill, the ones nothing claimed. */
    private class Segment(val tokens: List<String>) {
        var index = 0
        var filling: Marker? = null
        val loose = mutableListOf<String>()
    }

    private fun marked(segment: Segment, token: String, marker: Marker) {
        hasMarkers = true
        when (marker) {
            Marker.STREET_TYPE -> {
                if (segment.filling == Marker.STREET_TYPE) {
                    // Part of the name: "Str. Al. I. Cuza".
                    street.add(token)
                } else if (streetType == null && street.isEmpty()) {
                    streetType = STREET_TYPES.getValue(token)
                    segment.filling = marker
                } else {
                    segment.filling = null
                }
                segment.index += 1
            }
            Marker.LOCALITY, Marker.COUNTY -> {
                segment.filling = marker
                segment.index += 1
            }
            else -> {
                val (value, used) = value(segment.tokens, segment.index + 1)
                if (value != null) {
                    if (marker == Marker.NUMBER && numberIsInferred) {
                        number = null
                        numberIsInferred = false
                    }
                    assign(value, marker)
                }
                segment.index += 1 + used
                segment.filling = null
            }
        }
    }

    private fun unmarked(segment: Segment, token: String) {
        when (segment.filling) {
            Marker.STREET_TYPE -> {
                val nameHasLetters = street.any(::startsWithALetter)
                if (PostalStreets.allNumbers(token) && number == null && nameHasLetters) {
                    // "Str. Exemplului 1": the number after the name.
                    number = token
                    numberIsInferred = true
                    segment.filling = null
                } else {
                    street.add(token)
                }
            }
            Marker.LOCALITY -> locality.add(token)
            Marker.COUNTY -> county.add(token)
            else -> segment.loose.add(token)
        }
    }

    /** The words of a segment no marker claimed. */
    private fun looseWords(loose: List<String>) {
        if (!seenStreet && streetType == null && startsWithALetter(loose.first())) {
            // A street written without its type: "Exemplului 1".
            val name = loose.takeWhile { !hasNumber(it) }
            street.clear()
            street.addAll(name)
            val next = loose.drop(name.size).firstOrNull()
            if (number == null && next != null && PostalStreets.allNumbers(next)) {
                number = next
                numberIsInferred = true
            }
            seenStreet = true
        } else if (locality.isEmpty() && seenStreet && loose.none(::hasNumber)) {
            // A town after the street, without a marker: "…, Brașov".
            locality = loose.toMutableList()
        }
    }

    private fun assign(value: String, marker: Marker) {
        // "nr. 01" is number 1; "0" (a ground floor) stays.
        val trimmed = value.trimStart('0')
        val kept = trimmed.ifEmpty { value }
        when (marker) {
            Marker.NUMBER -> if (number == null) number = kept
            Marker.BLOCK -> if (block == null) block = kept
            Marker.STAIRCASE -> if (staircase == null) staircase = kept
            Marker.APARTMENT -> if (apartment == null) apartment = kept
            Marker.SECTOR -> if (sector == null && PostalStreets.allNumbers(kept)) sector = kept
            Marker.FLOOR, Marker.POSTAL_CODE, Marker.COUNTY, Marker.LOCALITY, Marker.STREET_TYPE -> Unit
        }
    }

    companion object {
        /** "cod", "postal" and the code itself. */
        private const val POSTAL_CODE_TOKENS = 3

        /** The capital, named without a marker. */
        private const val CAPITAL = "bucuresti"

        /** Words that say nothing about the place: the country. */
        private val IGNORED = setOf("romania")

        /** Each street type's printed forms, folded, by the one form it is kept as. */
        private val STREET_TYPES: Map<String, String> = mapOf(
            "strada" to listOf("str", "strada", "stra"),
            "bulevardul" to listOf("bd", "bdul", "blvd", "bulevardul", "bulevard"),
            "calea" to listOf("calea", "cal"),
            "soseaua" to listOf("sos", "soseaua", "sosea"),
            "aleea" to listOf("al", "aleea", "alee"),
            "piata" to listOf("piata", "pta"),
            "intrarea" to listOf("intrarea", "intr"),
            "splaiul" to listOf("splaiul", "spl"),
            "drumul" to listOf("drumul"),
            "prelungirea" to listOf("prelungirea", "prel"),
            "fundatura" to listOf("fundatura", "fdt"),
        ).flatMap { (type, words) -> words.map { it to type } }.toMap()

        /** Markers as they are printed, folded: "Str.", "Strada", "B-dul", "nr.", "bl.", "sc.", "ap.". */
        private val MARKERS: Map<String, Marker> = buildMap {
            STREET_TYPES.keys.forEach { put(it, Marker.STREET_TYPE) }
            listOf("nr", "numar", "numarul").forEach { put(it, Marker.NUMBER) }
            listOf("bl", "bloc", "blocul").forEach { put(it, Marker.BLOCK) }
            listOf("sc", "scara").forEach { put(it, Marker.STAIRCASE) }
            listOf("et", "etaj", "etajul").forEach { put(it, Marker.FLOOR) }
            listOf("ap", "apt", "apart", "apartament", "apartamentul").forEach { put(it, Marker.APARTMENT) }
            listOf("sector", "sectorul", "sect").forEach { put(it, Marker.SECTOR) }
            listOf("jud", "judet", "judetul").forEach { put(it, Marker.COUNTY) }
            put("cp", Marker.POSTAL_CODE)
            // "UAT" (unitatea administrativ-teritorială) names the town or commune too, as a policy prints it.
            listOf("loc", "localitatea", "mun", "municipiul", "oras", "orasul", "com", "comuna", "sat", "satul", "uat")
                .forEach { put(it, Marker.LOCALITY) }
        }

        private val SEPARATORS = setOf(",", ";", "\n", "|")

        fun marker(folded: String): Marker? = MARKERS[folded]

        /** Folded text split at the separators, without empty segments. */
        private fun segments(folded: String): List<String> {
            val result = mutableListOf<String>()
            val current = StringBuilder()
            for (character in TextRules.characters(folded)) {
                if (character in SEPARATORS) {
                    if (current.isNotEmpty()) result.add(current.toString())
                    current.clear()
                } else {
                    current.append(character)
                }
            }
            if (current.isNotEmpty()) result.add(current.toString())
            return result
        }

        /** A segment's runs of letters and digits. */
        private fun tokens(segment: String): List<String> {
            val result = mutableListOf<String>()
            val current = StringBuilder()
            for (character in TextRules.characters(segment)) {
                if (TextRules.isLetter(character) || TextRules.isNumber(character)) {
                    current.append(character)
                } else if (current.isNotEmpty()) {
                    result.add(current.toString())
                    current.clear()
                }
            }
            if (current.isNotEmpty()) result.add(current.toString())
            return result
        }

        private fun hasNumber(token: String): Boolean = TextRules.characters(token).any(TextRules::isNumber)

        private fun startsWithALetter(token: String): Boolean =
            TextRules.characters(token).firstOrNull()?.let(TextRules::isLetter) == true

        private fun isOneLetter(token: String): Boolean {
            val characters = TextRules.characters(token)
            return characters.size == 1 && TextRules.isLetter(characters[0])
        }

        /**
         * The value after a marker: one token, or a letter and a number written apart ("A 1" for block A1, "12 A"
         * for number 12A). Returns how many tokens it used.
         */
        private fun value(tokens: List<String>, index: Int): Pair<String?, Int> {
            val first = tokens.getOrNull(index)?.takeIf { MARKERS[it] == null } ?: return null to 0
            val joined = tokens.getOrNull(index + 1)?.takeIf { next ->
                val letterThenNumber = isOneLetter(first) && PostalStreets.allNumbers(next)
                val numberThenLetter = PostalStreets.allNumbers(first) && isOneLetter(next)
                MARKERS[next] == null && (letterThenNumber || numberThenLetter)
            }
            return if (joined != null) first + joined to 2 else first to 1
        }
    }
}
