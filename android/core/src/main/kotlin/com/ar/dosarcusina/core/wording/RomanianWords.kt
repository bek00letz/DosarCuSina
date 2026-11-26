package com.ar.dosarcusina.core.wording

import com.ar.dosarcusina.core.values.RomanianNumber
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigDecimal

/**
 * The app's words, generated from the iOS String Catalogs into this module's resources
 * (`words.json`, beside this file's package, written by scripts/android-words.py with the
 * app's strings.xml, never by hand), and the one way core writes them: a [Word]'s template, its
 * plural form picked by Romanian's rule ([RomanianPlural]), its numbers in the app's locale
 * ([RomanianNumber.format], „1.250”), never `String.format` with the machine's locale.
 */
object RomanianWords {
    private const val RESOURCE = "words.json"

    /** `%1$s`, `%2$,d`: the only specifiers the generated words carry. */
    private val SPECIFIER = Regex("%(\\d+)\\$(,?)([sd])")

    private val books: Map<WordBook, Map<String, Entry>> by lazy { read() }

    /** [word] in finished Romanian. Fails for a key its catalog doesn't have, or arguments that aren't the key's. */
    fun write(word: Word): String {
        val entry = requireNotNull(books[word.book]?.get(word.key)) {
            "„${word.key}” isn't in the ${word.book.stored} catalog: run scripts/android-words.py"
        }
        val fits = entry.args.size == word.args.size &&
            entry.args.zip(word.args).all { (kind, arg) -> kind.accepts(arg) }
        require(fits) { "„${word.key}” takes ${entry.args}, not ${word.args}" }
        val template = entry.text ?: entry.forms.getValue(RomanianPlural.of(countAt(word, entry.pluralArg)))
        return SPECIFIER.replace(template) { match ->
            when (val arg = word.args[match.groupValues[1].toInt() - 1]) {
                is WordArg.Text -> arg.text
                is WordArg.Count -> number(arg.count, groups = match.groupValues[2] == ",")
            }
        }
    }

    /** Whether [book] has [key]: for a test that every key an engine says is generated. */
    fun has(book: WordBook, key: String): Boolean = books[book]?.containsKey(key) == true

    private fun countAt(word: Word, position: Int): Long =
        (word.args[position - 1] as WordArg.Count).count

    private fun number(count: Long, groups: Boolean): String =
        RomanianNumber.format(BigDecimal.valueOf(count), 0, 0, groupsDigits = groups)

    private enum class ArgKind(val stored: String) {
        TEXT("text"),
        COUNT("count"),
        ;

        fun accepts(arg: WordArg): Boolean = when (this) {
            TEXT -> arg is WordArg.Text
            COUNT -> arg is WordArg.Count
        }
    }

    private class Entry(
        val args: List<ArgKind>,
        val text: String?,
        val pluralArg: Int,
        val forms: Map<PluralCategory, String>,
    )

    private fun read(): Map<WordBook, Map<String, Entry>> {
        val stream = RomanianWords::class.java.getResourceAsStream(RESOURCE)
            ?: error("$RESOURCE is missing from core's resources: run scripts/android-words.py")
        val document = stream.use { Json.parseToJsonElement(it.readBytes().decodeToString()) }.jsonObject
        val books = document.getValue("books").jsonObject
        return WordBook.entries.associateWith { book ->
            books[book.stored]?.jsonObject?.mapValues { (_, value) -> entry(value.jsonObject) }.orEmpty()
        }
    }

    private fun entry(json: JsonObject): Entry {
        val args = json.getValue("args").jsonArray.map { kind ->
            ArgKind.entries.first { it.stored == kind.jsonPrimitive.content }
        }
        val plural = json["plural"]?.jsonObject
            ?: return Entry(args, json.getValue("text").jsonPrimitive.content, 0, emptyMap())
        val forms = PluralCategory.entries.associateWith { plural.getValue(it.stored).jsonPrimitive.content }
        return Entry(args, null, plural.getValue("arg").jsonPrimitive.int, forms)
    }
}
