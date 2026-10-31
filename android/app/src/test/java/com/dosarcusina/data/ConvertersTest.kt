package com.dosarcusina.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ConvertersTest {

    private val converters = Converters()

    @Test
    fun testFromIntList() {
        val list = listOf(30, 7, 1)
        val serialized = converters.fromIntList(list)
        assertEquals("30,7,1", serialized)
    }

    @Test
    fun testFromIntListNull() {
        val serialized = converters.fromIntList(null)
        assertEquals(null, serialized)
    }

    @Test
    fun testToIntListStandard() {
        val raw = "30,7,1"
        val list = converters.toIntList(raw)
        assertEquals(listOf(30, 7, 1), list)
    }

    @Test
    fun testToIntListWithSpaces() {
        val raw = "30, 7, 1, 0"
        val list = converters.toIntList(raw)
        assertEquals(listOf(30, 7, 1, 0), list)
    }

    @Test
    fun testToIntListEmptyAndNull() {
        assertTrue(converters.toIntList("").isEmpty())
        assertTrue(converters.toIntList(null).isEmpty())
    }
}
