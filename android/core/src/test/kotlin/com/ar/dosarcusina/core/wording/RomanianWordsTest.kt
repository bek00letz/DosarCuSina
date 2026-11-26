package com.ar.dosarcusina.core.wording

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** The generated words and how core writes them: Romanian's plural rule, the specifiers, and the checks. */
class RomanianWordsTest {
    @Test
    fun `Romanian's plural rule`() {
        val categories = mapOf(
            0L to PluralCategory.FEW, 1L to PluralCategory.ONE, 2L to PluralCategory.FEW, 19L to PluralCategory.FEW,
            20L to PluralCategory.OTHER, 100L to PluralCategory.OTHER, 101L to PluralCategory.FEW,
            119L to PluralCategory.FEW, 120L to PluralCategory.OTHER, 1001L to PluralCategory.FEW,
            -1L to PluralCategory.ONE, -20L to PluralCategory.OTHER,
        )
        categories.forEach { (count, category) -> assertEquals(category, RomanianPlural.of(count), "$count") }
    }

    @Test
    fun `a word with a count, text and a substitution`() {
        assertEquals("o zi", Word.shared("%lld zile", Word.count(1)).written())
        assertEquals("1.250 de zile", Word.shared("%lld zile", Word.count(1250)).written())
        assertEquals("în 5 zile", Word.shared("în %@", Word.text("5 zile")).written())
        assertEquals("20\u00A0de\u00A0lei", MoneyWording.wholeLei("20", 20))
    }

    @Test
    fun `a word Android says differently`() {
        assertEquals("Protejat cu amprenta", Word.app("Protejat cu Face ID").written())
    }

    @Test
    fun `every word the engines say is generated`() {
        val keys = listOf(
            WordBook.SHARED to "%lld zile", WordBook.SHARED to "%@ și %@", WordBook.SHARED to "în %@",
            WordBook.APP to "acum %@", WordBook.APP to "%@\u00A0%lld lei", WordBook.APP to "%@\u00A0%lld cafele",
        )
        keys.forEach { (book, key) -> assertTrue(RomanianWords.has(book, key), key) }
    }

    @Test
    fun `a key no catalog has, or arguments the key doesn't take, fail`() {
        assertThrows<IllegalArgumentException> { Word.app("Nu e în catalog").written() }
        assertThrows<IllegalArgumentException> { Word.shared("%lld zile", Word.text("5")).written() }
        assertThrows<IllegalArgumentException> { Word.shared("în %@").written() }
    }
}
