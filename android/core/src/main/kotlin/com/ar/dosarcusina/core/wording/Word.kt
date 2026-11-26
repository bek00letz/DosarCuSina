package com.ar.dosarcusina.core.wording

/**
 * The String Catalog a word is in, by the name Android knows it by (scripts/string_catalogs.py,
 * `ANDROID_BOOKS`): the iOS app's catalog, the Shared table its app, widgets and share extension
 * compile, and the widgets' own.
 */
enum class WordBook(val stored: String) {
    /** ios/DosarCuSina/Resources/Localizable.xcstrings: what iOS's `String(localized:)` reads without a table. */
    APP("app"),

    /** ios/Shared/Shared.xcstrings: `String(localized:, table: "Shared")`. */
    SHARED("shared"),

    /** ios/DosarCuSinaWidgets/Localizable.xcstrings. */
    WIDGETS("widgets"),
}

/** One argument of a word, as iOS's `String(localized:)` is given it. */
sealed interface WordArg {
    /** A `%@`: text already written. */
    data class Text(val text: String) : WordArg

    /** A `%lld`: a whole number, written with the app's grouping („1.250”), that also picks a plural form. */
    data class Count(val count: Long) : WordArg
}

/**
 * A word to write: its catalog's key, exactly as the iOS code looks it up, and its arguments.
 * Android writes it from the words generated from that catalog ([RomanianWords]), so both apps
 * say the same; a word Android says differently is in shared/strings/android-differs.json.
 */
data class Word(val book: WordBook, val key: String, val args: List<WordArg> = emptyList()) {
    /** The finished Romanian. */
    fun written(): String = RomanianWords.write(this)

    companion object {
        /** A word of the iOS app's own catalog. */
        fun app(key: String, vararg args: WordArg): Word = Word(WordBook.APP, key, args.toList())

        /** A word of the Shared table. */
        fun shared(key: String, vararg args: WordArg): Word = Word(WordBook.SHARED, key, args.toList())

        fun text(text: String): WordArg = WordArg.Text(text)

        fun count(count: Int): WordArg = WordArg.Count(count.toLong())

        fun count(count: Long): WordArg = WordArg.Count(count)
    }
}
