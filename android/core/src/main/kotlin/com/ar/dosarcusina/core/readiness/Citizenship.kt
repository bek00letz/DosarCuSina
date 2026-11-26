package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.values.NamedChoice
import kotlinx.serialization.json.JsonObject

/** What the travel rules know of a person's citizenship, as the iOS app's `Citizenship.Group`, by its raw value. */
enum class CitizenshipGroup(val raw: String) {
    /** A citizen of an EU or EEA state, or of Switzerland. */
    FREE_MOVEMENT("freeMovement"),

    /** Any other citizenship, or none (stateless). */
    THIRD_COUNTRY("thirdCountry"),

    /** Not known yet: the trip check asks. */
    UNKNOWN("unknown"),
    ;

    companion object {
        fun of(raw: String): CitizenshipGroup? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * The countries a person can be a citizen of, as the iOS app's `Citizenship`
 * (ios/DosarCuSina/Models/Fields/Citizenship.swift), read from shared/travel/countries.json: each
 * by its key (`country.` and its ISO 3166-1 code), its Romanian name, what documents print for it
 * and whether its citizens move freely in the EU. A person can have several, kept on them as a
 * list (`MemberFields.citizenship`); the trip check goes by the most favourable. Never a country
 * named in code.
 */
class Citizenship(
    /** The choice a person's citizenship field offers, by name, „Fără cetățenie” last. */
    val options: List<Option>,
    private val keyPrefix: String,
    /** The key of having no citizenship (apatrid): the rules of a citizen of a country outside the EU. */
    val stateless: String,
    private val keys: ReadinessKeys,
) {
    /** One choice: a country (with its [code] and whether its citizens [movesFreely]), or none. */
    data class Option(
        override val key: String,
        override val label: String,
        override val aliases: List<String>,
        val code: String?,
        val movesFreely: Boolean,
    ) : NamedChoice

    private val countries: Map<String, Option> = options.filter { it.code != null }.associateBy { it.key }

    /** The stored key of a country, by its two-letter code. */
    fun key(code: String): String = keyPrefix + code

    /** The option for a stored key, or for text a document or an earlier version wrote. */
    fun option(text: String): Option? =
        options.firstOrNull { it.key == text } ?: options.firstOrNull { it.matches(text) }

    /** The country of a stored key; none for no citizenship or a key this build doesn't know. */
    fun country(key: String?): Option? = key?.let { countries[it] }

    /**
     * The stored key of the citizenship a document's nationality names: its code as the
     * machine-readable zone prints it ("ROU", "D"), "Română / ROU" as an identity card prints it,
     * a country's name, or a key already. Null for anything else.
     */
    fun keyForNationality(text: String?): String? {
        val trimmed = text?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        option(trimmed)?.let { return it.key }
        // "Română / ROU": the parts, each on its own.
        return lettersAndSpaces(trimmed).firstNotNullOfOrNull { option(it)?.key }
    }

    /** The group a stored citizenship falls in, for the travel rules. */
    fun group(of: String?): CitizenshipGroup {
        val key = of ?: return CitizenshipGroup.UNKNOWN
        if (key == stateless) return CitizenshipGroup.THIRD_COUNTRY
        val country = country(key) ?: return CitizenshipGroup.UNKNOWN
        return if (country.movesFreely) CitizenshipGroup.FREE_MOVEMENT else CitizenshipGroup.THIRD_COUNTRY
    }

    /**
     * The citizenships kept on a person, as keys in the options' order: the list this version
     * keeps, or the one key an earlier version kept as text. Text no option recognizes is left out.
     */
    fun kept(person: ReadinessValues?): List<String> {
        val stored = when (val value = person?.get(keys.citizenship)) {
            is ReadinessValue.Choices -> value.keys
            is ReadinessValue.Text -> listOf(value.text)
            else -> emptyList()
        }
        return ordered(stored.mapNotNull { option(it)?.key })
    }

    /** A person's citizenships: every one kept on them, else every one their documents print; none if neither says. */
    fun of(person: ReadinessValues?, documents: List<ReadinessValues>): List<String> =
        kept(person).ifEmpty { read(documents) }

    /** Every citizenship the documents print, each once, in the options' order. */
    fun read(documents: List<ReadinessValues>): List<String> = ordered(documents.mapNotNull { printed(it) })

    /** The citizenship one document prints, when it prints one. */
    fun printed(document: ReadinessValues): String? = keyForNationality(document.text(keys.nationality))

    /** The person's values with [citizenships] kept as their list, or null when that is what they keep already. */
    fun keeping(citizenships: List<String>, person: ReadinessValues): ReadinessValues? {
        val list = ordered(citizenships)
        if (list.isEmpty() || person[keys.citizenship] == ReadinessValue.Choices(list)) return null
        return person.with(keys.citizenship, ReadinessValue.Choices(list))
    }

    /** Keys once each, in the options' order: how the list is kept, so the same citizenships are the same value. */
    fun ordered(keys: List<String>): List<String> {
        val wanted = keys.toSet()
        return options.map { it.key }.filter { it in wanted }
    }

    companion object {
        fun read(json: JsonObject, keys: ReadinessKeys): Citizenship {
            val free = json.strings("freeMovement").toSet()
            val options = json.list("options").map { it.obj("options") }.map { option ->
                val code = option.stringOrNull("code")
                val movesFreely = if ("movesFreely" in option) option.bool("movesFreely") else false
                if (code != null && movesFreely != (code in free)) {
                    throw TravelError("countries.json: $code and freeMovement disagree")
                }
                Option(option.string("key"), option.string("label"), option.strings("aliases"), code, movesFreely)
            }
            return Citizenship(options, json.string("keyPrefix"), json.string("stateless"), keys)
        }
    }
}

/** The runs of letters and spaces in [text], each trimmed: "Română / ROU" is "Română" and "ROU". */
private fun lettersAndSpaces(text: String): List<String> {
    val parts = mutableListOf<String>()
    val current = StringBuilder()
    for (character in text) {
        if (character.isLetter() || character == ' ') {
            current.append(character)
        } else {
            parts += current.toString()
            current.clear()
        }
    }
    parts += current.toString()
    return parts.map { it.trim() }.filter { it.isNotEmpty() }
}
