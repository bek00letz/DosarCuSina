package com.ar.dosarcusina.ui

import com.ar.dosarcusina.core.wording.RomanianWords
import com.ar.dosarcusina.core.wording.WordBook
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Every word the screens say by its iOS key (`Word.app("…")`, `Word.shared("…")`) is in the words
 * generated from the String Catalogs, so a key that isn't fails here, not on a screen.
 */
class UiWordsTest {
    @Test
    fun `every key the screens name is in its catalog`() {
        val sources = File("src/main/kotlin/com/ar/dosarcusina/ui").walkTopDown()
            .filter { it.extension == "kt" }
            .toList()
        assertTrue(sources.isNotEmpty(), "the ui sources are found from the module's folder")
        val keys = sources.flatMap { file ->
            KEY.findAll(file.readText()).map { match -> Triple(file.name, match.groupValues[1], match.groupValues[2]) }
        }
        assertTrue(keys.isNotEmpty())
        val missing = keys.filterNot { (_, book, key) -> RomanianWords.has(bookOf(book), unescaped(key)) }
        assertEquals(emptyList<Triple<String, String, String>>(), missing)
    }

    private fun bookOf(name: String): WordBook = if (name == "shared") WordBook.SHARED else WordBook.APP

    private fun unescaped(key: String): String = key.replace("\\\"", "\"").replace("\\$", "$")

    private companion object {
        /** `Word.app("key"` and `Word.shared("key"`, the key as written in the source. */
        val KEY = Regex("""Word\.(app|shared)\(\s*"((?:[^"\\]|\\.)*)"""")
    }
}
