package com.dosarcusina.ocr

import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Romanian utility bill providers matching iOS RomanianUtilityProvider enum.
 */
enum class RomanianUtilityProvider(val displayName: String) {
    DIGI("DIGI"),
    PPC("PPC / Enel"),
    HIDROELECTRICA("Hidroelectrica"),
    EON("E.ON"),
    ENGIE("ENGIE"),
    ORANGE("Orange"),
    VODAFONE("Vodafone"),
    UNKNOWN("General");

    companion object {
        fun identify(text: String): RomanianUtilityProvider {
            return when {
                Regex("""\b(DIGI|RCS\s*&\s*RDS|RCS\s*RDS)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) -> DIGI
                Regex("""\b(PPC|ENEL|PPC\s+ENERGIE)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) -> PPC
                Regex("""\b(HIDROELECTRICA|SPEEH\s+HIDROELECTRICA)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) -> HIDROELECTRICA
                Regex("""\b(E\.ON|EON)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) -> EON
                Regex("""\b(ENGIE|ENGIE\s+ROMANIA)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) -> ENGIE
                Regex("""\b(ORANGE|ORANGE\s+ROMANIA)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) -> ORANGE
                Regex("""\b(VODAFONE|VODAFONE\s+ROMANIA)\b""", RegexOption.IGNORE_CASE).containsMatchIn(text) -> VODAFONE
                else -> UNKNOWN
            }
        }
    }
}

/**
 * Parsed bill extraction result.
 */
data class ScanResult(
    val provider: RomanianUtilityProvider,
    val clientCode: String? = null,
    val invoiceNumber: String? = null,
    val dueDate: Long? = null,
    val totalAmount: Double? = null,
    val currency: String = "RON",
    val meterIndex: String? = null,
    val paymentCode: String? = null,
    val rawText: String = ""
)

/**
 * Regex-based parser for Romanian utility invoices and receipts.
 */
object RomanianUtilityParser {

    private val DIGI_CLIENT_CODE = Regex("""Cod\s+client[:\s]+([0-9]{7,10})""", RegexOption.IGNORE_CASE)
    private val DIGI_INVOICE_NUM = Regex("""Factura\s+(?:seria\s+([A-Z0-9]+)\s+nr\.?\s*([0-9]+)|nr\.?\s*([0-9]+))""", RegexOption.IGNORE_CASE)
    private val DIGI_DUE_DATE = Regex("""(?:Data\s+scadent[aă]|Scadent[aă])[:\s]+((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))""", RegexOption.IGNORE_CASE)
    private val DIGI_TOTAL = Regex("""Total\s+de\s+plat[aă][:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    private val PPC_CLIENT_CODE = Regex("""Cod\s+client[:\s]+([0-9]{9,10})""", RegexOption.IGNORE_CASE)
    private val PPC_PAYMENT_CODE = Regex("""Cod\s+plat[aă][:\s]+([0-9]{10,12})""", RegexOption.IGNORE_CASE)
    private val PPC_DUE_DATE = Regex("""(?:Data\s+scaden[tț]ei|Scadent[aă])[:\s]+((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))""", RegexOption.IGNORE_CASE)
    private val PPC_TOTAL = Regex("""Total\s+(?:de\s+plat[aă]|factur[aă]\s+curent[aă])[:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    private val HIDRO_CLIENT_CODE = Regex("""Cod\s+client[:\s]+([0-9]{6,10})""", RegexOption.IGNORE_CASE)
    private val HIDRO_CONSUMPTION_LOC = Regex("""Loc\s+de\s+consum[:\s]+([0-9]{8,12})""", RegexOption.IGNORE_CASE)
    private val HIDRO_INVOICE_NUM = Regex("""Factura\s+nr[:\s]+([0-9]+)""", RegexOption.IGNORE_CASE)
    // 1.8.0 active energy index
    private val HIDRO_ACTIVE_ENERGY = Regex("""(?:1\.8\.0|energie\s+activ[aă])[:\s]+(\d+(?:[.,]\d+)?)""", RegexOption.IGNORE_CASE)
    private val HIDRO_DUE_DATE = Regex("""Data\s+scadent[aă][:\s]+((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))""", RegexOption.IGNORE_CASE)
    private val HIDRO_TOTAL = Regex("""Total\s+de\s+achitat[:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    private val EON_COLLECTION_CODE = Regex("""Cod\s+[iî]ncasare[:\s]+([0-9]{10})""", RegexOption.IGNORE_CASE)
    private val EON_CLIENT_CODE = Regex("""Cod\s+client[:\s]+([0-9]{10})""", RegexOption.IGNORE_CASE)
    private val EON_DUE_DATE = Regex("""(?:Scadent[aă]|Data\s+scadent[aă])[:\s]+((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))""", RegexOption.IGNORE_CASE)
    private val EON_TOTAL = Regex("""Total\s+de\s+plat[aă][:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    private val ENGIE_CLIENT_CODE = Regex("""Cod\s+(?:client|partener)[:\s]+([0-9]{9,10})""", RegexOption.IGNORE_CASE)
    private val ENGIE_GAS_INDEX = Regex("""Index\s+nou[:\s]+([0-9]+)\s*mc""", RegexOption.IGNORE_CASE)
    private val ENGIE_DUE_DATE = Regex("""(?:Data\s+scadent[aă]|Scadent[aă])[:\s]+((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))""", RegexOption.IGNORE_CASE)
    private val ENGIE_TOTAL = Regex("""Total\s+de\s+plat[aă][:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    private val ORANGE_SUBSCRIBER_CODE = Regex("""Cod\s+abonat[:\s]+([0-9]{8,10})""", RegexOption.IGNORE_CASE)
    private val ORANGE_INVOICE_NUM = Regex("""Factura\s+nr\.?\s*([A-Z0-9]+)""", RegexOption.IGNORE_CASE)
    private val ORANGE_DUE_DATE = Regex("""Scadent[aă][:\s]+((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))""", RegexOption.IGNORE_CASE)
    private val ORANGE_TOTAL = Regex("""Total\s+(?:factur[aă]\s+curent[aă]|de\s+plat[aă])[:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    private val VODAFONE_CLIENT_CODE = Regex("""Cod\s+client[:\s]+([0-9]{8,10})""", RegexOption.IGNORE_CASE)
    private val VODAFONE_INVOICE_NUM = Regex("""Num[aă]r\s+factur[aă][:\s]+([A-Z0-9]+)""", RegexOption.IGNORE_CASE)
    private val VODAFONE_DUE_DATE = Regex("""Data\s+scadent[aă][:\s]+((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))""", RegexOption.IGNORE_CASE)
    private val VODAFONE_TOTAL = Regex("""Total\s+de\s+plat[aă][:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    private val GENERIC_DATE = Regex("""(?:Data(?:\s+scadent[aă])?|Scaden[tț][aă])?[:\s]*\b((?:0?[1-9]|[12][0-9]|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20[2-9][0-9])|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+(?:20[2-9][0-9]))\b""", RegexOption.IGNORE_CASE)
    private val GENERIC_TOTAL = Regex("""(?:Total|Suma|Achitat|Plat[aă])[:\s]+([0-9.,\s]+?)\s*(?:LEI|RON)""", RegexOption.IGNORE_CASE)

    fun parse(text: String): ScanResult {
        val provider = RomanianUtilityProvider.identify(text)

        var clientCode: String? = null
        var invoiceNumber: String? = null
        var dueDateStr: String? = null
        var totalAmountStr: String? = null
        var meterIndex: String? = null
        var paymentCode: String? = null

        when (provider) {
            RomanianUtilityProvider.DIGI -> {
                clientCode = DIGI_CLIENT_CODE.find(text)?.groupValues?.get(1)
                val digiInvoiceMatch = DIGI_INVOICE_NUM.find(text)
                invoiceNumber = if (digiInvoiceMatch != null) {
                    val num = digiInvoiceMatch.groupValues[2]
                    val fallbackNum = digiInvoiceMatch.groupValues[3]
                    if (num.isNotEmpty()) num else fallbackNum.ifEmpty { null }
                } else null
                dueDateStr = DIGI_DUE_DATE.find(text)?.groupValues?.get(1)
                totalAmountStr = DIGI_TOTAL.find(text)?.groupValues?.get(1)
            }
            RomanianUtilityProvider.PPC -> {
                clientCode = PPC_CLIENT_CODE.find(text)?.groupValues?.get(1)
                paymentCode = PPC_PAYMENT_CODE.find(text)?.groupValues?.get(1)
                dueDateStr = PPC_DUE_DATE.find(text)?.groupValues?.get(1)
                totalAmountStr = PPC_TOTAL.find(text)?.groupValues?.get(1)
            }
            RomanianUtilityProvider.HIDROELECTRICA -> {
                clientCode = HIDRO_CLIENT_CODE.find(text)?.groupValues?.get(1)
                invoiceNumber = HIDRO_INVOICE_NUM.find(text)?.groupValues?.get(1)
                meterIndex = HIDRO_ACTIVE_ENERGY.find(text)?.groupValues?.get(1)
                dueDateStr = HIDRO_DUE_DATE.find(text)?.groupValues?.get(1)
                totalAmountStr = HIDRO_TOTAL.find(text)?.groupValues?.get(1)
            }
            RomanianUtilityProvider.EON -> {
                clientCode = EON_CLIENT_CODE.find(text)?.groupValues?.get(1)
                paymentCode = EON_COLLECTION_CODE.find(text)?.groupValues?.get(1)
                dueDateStr = EON_DUE_DATE.find(text)?.groupValues?.get(1)
                totalAmountStr = EON_TOTAL.find(text)?.groupValues?.get(1)
            }
            RomanianUtilityProvider.ENGIE -> {
                clientCode = ENGIE_CLIENT_CODE.find(text)?.groupValues?.get(1)
                meterIndex = ENGIE_GAS_INDEX.find(text)?.groupValues?.get(1)
                dueDateStr = ENGIE_DUE_DATE.find(text)?.groupValues?.get(1)
                totalAmountStr = ENGIE_TOTAL.find(text)?.groupValues?.get(1)
            }
            RomanianUtilityProvider.ORANGE -> {
                clientCode = ORANGE_SUBSCRIBER_CODE.find(text)?.groupValues?.get(1)
                invoiceNumber = ORANGE_INVOICE_NUM.find(text)?.groupValues?.get(1)
                dueDateStr = ORANGE_DUE_DATE.find(text)?.groupValues?.get(1)
                totalAmountStr = ORANGE_TOTAL.find(text)?.groupValues?.get(1)
            }
            RomanianUtilityProvider.VODAFONE -> {
                clientCode = VODAFONE_CLIENT_CODE.find(text)?.groupValues?.get(1)
                invoiceNumber = VODAFONE_INVOICE_NUM.find(text)?.groupValues?.get(1)
                dueDateStr = VODAFONE_DUE_DATE.find(text)?.groupValues?.get(1)
                totalAmountStr = VODAFONE_TOTAL.find(text)?.groupValues?.get(1)
            }
            RomanianUtilityProvider.UNKNOWN -> {
                // Fallback generic extraction
                totalAmountStr = GENERIC_TOTAL.find(text)?.groupValues?.get(1)
                val dateMatch = GENERIC_DATE.find(text)
                if (dateMatch != null) {
                    dueDateStr = dateMatch.groupValues[1]
                }
            }
        }

        // Fallback for amount if provider-specific regex didn't catch it
        if (totalAmountStr == null) {
            totalAmountStr = GENERIC_TOTAL.find(text)?.groupValues?.get(1)
        }

        // Fallback for due date if provider-specific regex didn't catch it
        if (dueDateStr == null) {
            val dateMatch = GENERIC_DATE.find(text)
            if (dateMatch != null) {
                dueDateStr = dateMatch.groupValues[1]
            }
        }

        val totalAmount = totalAmountStr?.let { parseRomanianAmount(it) }
        val dueDate = dueDateStr?.let { parseRomanianDate(it) }

        return ScanResult(
            provider = provider,
            clientCode = clientCode,
            invoiceNumber = invoiceNumber,
            dueDate = dueDate,
            totalAmount = totalAmount,
            currency = "RON",
            meterIndex = meterIndex,
            paymentCode = paymentCode,
            rawText = text
        )
    }

    /**
     * Normalizes Romanian numeric formats (e.g. "1.234,56 LEI", "14 502,30 LEI" -> 14502.30).
     */
    fun parseRomanianAmount(raw: String): Double? {
        var sanitized = raw.trim()
            .replace("LEI", "", ignoreCase = true)
            .replace("RON", "", ignoreCase = true)
            .replace("EUR", "", ignoreCase = true)
            .replace("\u00A0", "")
            .replace(" ", "")
            .trim()

        if (sanitized.contains(",") && sanitized.contains(".")) {
            if (sanitized.lastIndexOf(',') > sanitized.lastIndexOf('.')) {
                // European/Romanian: thousand . and decimal ,
                sanitized = sanitized.replace(".", "").replace(",", ".")
            } else {
                // US: thousand , and decimal .
                sanitized = sanitized.replace(",", "")
            }
        } else if (sanitized.contains(",")) {
            sanitized = sanitized.replace(",", ".")
        }

        return sanitized.toDoubleOrNull()
    }

    private val MONTH_MAP = mapOf(
        "ianuarie" to "01", "februarie" to "02", "martie" to "03", "aprilie" to "04",
        "mai" to "05", "iunie" to "06", "iulie" to "07", "august" to "08",
        "septembrie" to "09", "octombrie" to "10", "noiembrie" to "11", "decembrie" to "12"
    )

    /**
     * Parses dd.MM.yyyy, dd/MM/yyyy, dd-MM-yyyy, and written Romanian months ("15 noiembrie 2026") to epoch timestamp.
     * Supports both 1-digit and 2-digit days and months.
     */
    fun parseRomanianDate(raw: String): Long? {
        var normalized = raw.trim().lowercase(Locale.ROOT)
        for ((name, num) in MONTH_MAP) {
            if (normalized.contains(name)) {
                normalized = normalized.replace(name, num)
                val parts = normalized.split(Regex("""\s+""")).filter { it.isNotEmpty() }
                if (parts.size == 3) {
                    normalized = "${parts[0]}.${parts[1]}.${parts[2]}"
                }
                break
            }
        }

        val sanitized = normalized.replace('/', '.').replace('-', '.').trim()
        val formats = listOf("dd.MM.yyyy", "d.M.yyyy", "yyyy-MM-dd")
        for (pattern in formats) {
            val format = SimpleDateFormat(pattern, Locale.US).apply {
                isLenient = false
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }
            try {
                val parsed = format.parse(sanitized)
                if (parsed != null) return parsed.time
            } catch (ignored: Exception) {}
        }
        return null
    }
}
