package com.dosarcusina.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class RomanianUtilityParserTest {

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    @Test
    fun testDigiInvoiceParsing() {
        val snippet = "RCS & RDS S.A. Cod client: 19482910 Factura seria FCR nr. 29481 Data scadenta: 25.11.2026 Total de plata: 149,50 LEI"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.DIGI, result.provider)
        assertEquals("19482910", result.clientCode)
        assertEquals("29481", result.invoiceNumber)
        assertEquals(149.50, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-11-25", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testPpcEnelInvoiceParsing() {
        val snippet = "PPC Energie Muntenia S.A. Cod client: 104928192 Cod plata: 9482019482 Data scadentei: 18.12.2026 Total de plata: 382,14 lei"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.PPC, result.provider)
        assertEquals("104928192", result.clientCode)
        assertEquals("9482019482", result.paymentCode)
        assertEquals(382.14, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-12-18", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testHidroelectricaInvoiceParsing() {
        val snippet = "SPEEH HIDROELECTRICA S.A. Cod client: 849201 Loc de consum: 10294819 Factura nr 9481 Data scadenta: 30.10.2026 Total de achitat: 215,80 LEI"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.HIDROELECTRICA, result.provider)
        assertEquals("849201", result.clientCode)
        assertEquals("9481", result.invoiceNumber)
        assertEquals(215.80, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-10-30", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testEonInvoiceParsing() {
        val snippet = "E.ON Energie Romania Cod incasare: 1049281948 Cod client: 1049281948 Scadenta: 15.11.2026 Total de plata: 540,00 LEI"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.EON, result.provider)
        assertEquals("1049281948", result.clientCode)
        assertEquals("1049281948", result.paymentCode)
        assertEquals(540.00, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-11-15", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testEngieInvoiceParsing() {
        val snippet = "ENGIE Romania S.A. Cod client: 194820192 Index nou: 1495 mc Total de plata: 412,30 LEI Data scadenta: 12.11.2026"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.ENGIE, result.provider)
        assertEquals("194820192", result.clientCode)
        assertEquals("1495", result.meterIndex)
        assertEquals(412.30, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-11-12", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testOrangeInvoiceParsing() {
        val snippet = "Orange Romania S.A. Cod abonat: 84920194 Factura nr. ORG102948 Scadenta: 20.11.2026 Total factura curenta: 89,99 lei"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.ORANGE, result.provider)
        assertEquals("84920194", result.clientCode)
        assertEquals("ORG102948", result.invoiceNumber)
        assertEquals(89.99, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-11-20", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testVodafoneInvoiceParsing() {
        val snippet = "Vodafone Romania S.A. Cod client: 29481029 Numar factura: VDF94810 Data scadenta: 22.11.2026 Total de plata: 110,25 LEI"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.VODAFONE, result.provider)
        assertEquals("29481029", result.clientCode)
        assertEquals("VDF94810", result.invoiceNumber)
        assertEquals(110.25, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-11-22", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testGenericReceiptFallback() {
        val snippet = "Bon fiscal / Chitanta Nr 491 Data: 14.10.2026 Total: 75,50 RON Multumim!"
        val result = RomanianUtilityParser.parse(snippet)

        assertEquals(RomanianUtilityProvider.UNKNOWN, result.provider)
        assertEquals(75.50, result.totalAmount!!, 0.001)
        assertNotNull(result.dueDate)
        assertEquals("2026-10-14", dateFormat.format(Date(result.dueDate!!)))
    }

    @Test
    fun testRomanianAmountNormalization() {
        assertEquals(1234.56, RomanianUtilityParser.parseRomanianAmount("1.234,56 LEI")!!, 0.001)
        assertEquals(450.50, RomanianUtilityParser.parseRomanianAmount("450,50 RON")!!, 0.001)
        assertEquals(99.00, RomanianUtilityParser.parseRomanianAmount("99,00")!!, 0.001)
        assertEquals(14500.00, RomanianUtilityParser.parseRomanianAmount("14.500,00 LEI")!!, 0.001)
    }

    @Test
    fun testSingleDigitDayAndMonthDateParsing() {
        // Invoice with single-digit day and month: "5.2.2026"
        val snippet = "Factura utilitati Data: 5.2.2026 Total: 100 RON"
        val result = RomanianUtilityParser.parse(snippet)
        assertNotNull(result.dueDate)
        assertEquals("2026-02-05", dateFormat.format(Date(result.dueDate!!)))
    }
}
