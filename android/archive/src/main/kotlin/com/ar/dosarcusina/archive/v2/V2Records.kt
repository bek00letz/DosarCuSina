package com.ar.dosarcusina.archive.v2

import com.ar.dosarcusina.archive.v3.Ids
import com.ar.dosarcusina.archive.v3.JsonRecord
import com.ar.dosarcusina.archive.v3.UnreadableRecord
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.RomanianText
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

// The records of a version 2 archive, as the first iOS builds wrote them (the iOS app's
// DossierArchiveV2Models.swift). Each is read as Swift's Codable reads it: a required key that is
// missing, or any key of the wrong shape, refuses its file.

private fun JsonRecord.id(key: String): UUID = Ids.parse(string(key)) ?: throw UnreadableRecord()

private fun JsonRecord.idOrNull(key: String): UUID? =
    stringOrNull(key)?.let { Ids.parse(it) ?: throw UnreadableRecord() }

private fun JsonRecord.ids(key: String): List<UUID> = strings(key).map { Ids.parse(it) ?: throw UnreadableRecord() }

/** A v2 asset: its kind's fixed columns, read by name, and its dynamic fields. */
internal class V2Asset private constructor(private val record: JsonRecord) {
    val id: UUID = record.id("id")
    val name: String = record.string("name")
    val category: String = record.string("categoryRaw")
    val currencyCode: String = record.string("currencyCode")
    val createdAt: Instant = record.instant("createdAt")
    val updatedAt: Instant = record.instant("updatedAt")
    val dynamicFields: List<V2DynamicField> =
        record.list("dynamicFields").map { V2DynamicField.read(JsonRecord.of(it)) }

    init {
        record.string("iconName")
        record.string("accentColorHex")
        for (key in TEXTS) record.stringOrNull(key)
        for (key in NUMBERS) record.doubleOrNull(key)
        for (key in COUNTS) record.intOrNull(key)
        for (key in MOMENTS) record.instantOrNull(key)
    }

    fun text(key: String): String? = record.stringOrNull(key)

    fun number(key: String): Double? = record.doubleOrNull(key)

    fun int(key: String): Int? = record.intOrNull(key)

    fun moment(key: String): Instant? = record.instantOrNull(key)

    companion object {
        fun read(record: JsonRecord) = V2Asset(record)

        private val TEXTS = listOf(
            "subtitle", "customCategoryName", "notes", "metricUnit", "vin", "licensePlate", "civSeries", "make",
            "modelName",
            "fuelType", "engineSpecs", "address", "cadastralNumber", "podCode", "clcCode", "waterClientCode",
            "heatingBoilerModel", "heatingBoilerSerial", "gasMeterSerial", "electricityMeterSerial", "waterMeterSerial",
            "heatingBoilerSpecs", "meterSerials", "personName", "bloodType", "allergies", "chronicConditions",
            "emergencyContact", "familyDoctorName", "familyDoctorPhone", "emergencyContactName",
            "emergencyContactPhone",
            "microchipNumber", "petPassportNumber", "speciesAndBreed", "petSpecies", "petBreed", "vetContactInfo",
            "veterinarianClinic", "veterinarianPhone", "serialOrImei", "retailerOrIssuer", "providerName",
            "billingCycle",
            "paymentCardLast4", "cancellationUrl", "primaryContactName", "primaryContactRole", "primaryContactPhone",
            "primaryContactEmail",
        )
        private val NUMBERS =
            listOf("currentMetricValue", "surfaceAreaSqm", "weightKg", "purchasePrice", "recurringAmount")
        private val COUNTS = listOf(
            "manufactureYear", "engineDisplacementCc", "enginePowerKw", "constructionYear", "meterReadWindowStartDay",
            "meterReadWindowEndDay", "warrantyMonths", "extendedWarrantyMonths",
        )
        private val MOMENTS = listOf("birthDate", "purchaseOrIssueDate", "contractEndDate")
    }
}

/** A v2 dynamic field: a label and one value, kept in the section's notes. */
internal data class V2DynamicField(
    val label: String,
    val stringValue: String?,
    val numberValue: Double?,
    val dateValue: Instant?,
    val boolValue: Boolean?,
) {
    /** Its value as the notes write it: text, a number as Swift writes one, a day, "Da" or "Nu". */
    fun text(zone: ZoneId): String? = stringValue
        ?: numberValue?.let(::swiftDescription)
        ?: dateValue?.let { CalendarDay.of(it, zone).isoString }
        ?: boolValue?.let { if (it) "Da" else "Nu" }

    companion object {
        fun read(record: JsonRecord): V2DynamicField {
            record.id("id")
            record.string("key")
            record.string("fieldTypeRaw")
            return V2DynamicField(
                record.string("label"), record.stringOrNull("stringValue"), record.doubleOrNull("numberValue"),
                record.instantOrNull("dateValue"), record.boolOrNull("boolValue"),
            )
        }

        /** Swift's `String(Double)`: the shortest digits, with `.0` after a whole number. */
        fun swiftDescription(value: Double): String {
            val text = MachineText.number(value).content
            return if (text.any { it == '.' || it == 'e' }) text else "$text.0"
        }
    }
}

/** A v2 event: a deadline, completed or not. */
internal data class V2Event(
    val id: UUID,
    val assetId: UUID,
    val title: String,
    val eventDescription: String?,
    val dueDate: Instant,
    val completedDate: Instant?,
    val isCompleted: Boolean,
    val cost: Double?,
    val currency: String,
    val provider: String?,
    val policyOrContractNumber: String?,
    val mileageAtEvent: Double?,
    val cadenceDays: Int?,
    val metricTriggerValue: Double?,
    val reminderOffsetDays: List<Int>,
    val createdAt: Instant,
) {
    companion object {
        fun read(record: JsonRecord): V2Event {
            for (key in listOf(
                "coverageType",
                "bonusMalusClass",
                "serviceLocation",
                "calendarEventIdentifier",
                "reminderItemIdentifier",
            )) {
                record.stringOrNull(key)
            }
            for (key in listOf(
                "insuredCoverageAmount",
                "franchiseAmount",
                "cadenceMetricInterval",
            )) record.doubleOrNull(key)
            record.instantOrNull("startDate")
            record.bool("isAutoRenew")
            record.ids("attachmentIds")
            return V2Event(
                id = record.id("id"), assetId = record.id("assetId"), title = record.string("title"),
                eventDescription = record.stringOrNull("eventDescription"), dueDate = record.instant("dueDate"),
                completedDate = record.instantOrNull("completedDate"), isCompleted = record.bool("isCompleted"),
                cost = record.doubleOrNull("cost"), currency = record.string("currency"),
                provider = record.stringOrNull("provider"),
                policyOrContractNumber = record.stringOrNull("policyOrContractNumber"),
                mileageAtEvent = record.doubleOrNull("mileageAtEvent"), cadenceDays = record.intOrNull("cadenceDays"),
                metricTriggerValue = record.doubleOrNull("metricTriggerValue"),
                reminderOffsetDays = record.list("reminderOffsetDays").map(JsonRecord::int),
                createdAt = record.instant("createdAt"),
            )
        }
    }
}

/** A v2 service record: a line item, with the visit it was part of. */
internal data class V2ServiceItem(
    val id: UUID,
    val assetId: UUID,
    val eventId: UUID?,
    val name: String,
    val category: String,
    val partBrandOrCode: String?,
    val partSerialNumber: String?,
    val cost: Double?,
    val laborCost: Double?,
    val partsCost: Double?,
    val serviceDate: Instant,
    val mileageAtService: Double?,
    val specialistOrDoctorName: String?,
    val serialOrBatchNumber: String?,
    val locationOrToothNumber: String?,
    val daysInService: Int?,
    val warrantyMonths: Int?,
    val shopName: String?,
    val notes: String?,
) {
    companion object {
        fun read(record: JsonRecord): V2ServiceItem {
            record.instantOrNull("nextDueDate")
            record.doubleOrNull("nextDueMileageKm")
            return V2ServiceItem(
                id = record.id("id"), assetId = record.id("assetId"), eventId = record.idOrNull("eventId"),
                name = record.string("name"),
                category = record.string("category"), partBrandOrCode = record.stringOrNull("partBrandOrCode"),
                partSerialNumber = record.stringOrNull("partSerialNumber"), cost = record.doubleOrNull("cost"),
                laborCost = record.doubleOrNull("laborCost"), partsCost = record.doubleOrNull("partsCost"),
                serviceDate = record.instant("serviceDate"), mileageAtService = record.doubleOrNull("mileageAtService"),
                specialistOrDoctorName = record.stringOrNull("specialistOrDoctorName"),
                serialOrBatchNumber = record.stringOrNull("serialOrBatchNumber"),
                locationOrToothNumber = record.stringOrNull("locationOrToothNumber"),
                daysInService = record.intOrNull("daysInService"), warrantyMonths = record.intOrNull("warrantyMonths"),
                shopName = record.stringOrNull("shopName"), notes = record.stringOrNull("notes"),
            )
        }
    }
}

/** A v2 reading. */
internal data class V2Measurement(
    val id: UUID,
    val assetId: UUID,
    val domain: String,
    val metricName: String,
    val value: Double,
    val secondaryValue: Double?,
    val unit: String,
    val recordedAt: Instant,
    val unitPrice: Double?,
    val isSelfRead: Boolean,
    val referenceMin: Double?,
    val referenceMax: Double?,
    val labOrProviderName: String?,
    val notes: String?,
    val attachmentIds: List<UUID>,
) {
    companion object {
        fun read(record: JsonRecord): V2Measurement {
            record.doubleOrNull("previousValue")
            return V2Measurement(
                id = record.id("id"), assetId = record.id("assetId"), domain = record.string("domainRawValue"),
                metricName = record.string("metricName"), value = record.double("value"),
                secondaryValue = record.doubleOrNull("secondaryValue"), unit = record.string("unit"),
                recordedAt = record.instant("recordedAt"), unitPrice = record.doubleOrNull("unitPrice"),
                isSelfRead = record.bool("isSelfRead"), referenceMin = record.doubleOrNull("referenceMin"),
                referenceMax = record.doubleOrNull("referenceMax"),
                labOrProviderName = record.stringOrNull("labOrProviderName"),
                notes = record.stringOrNull("notes"), attachmentIds = record.ids("attachmentIds"),
            )
        }
    }
}

/** A v2 document's metadata; its file is in the vault. */
internal data class V2Attachment(
    val id: UUID,
    val assetId: UUID?,
    val eventId: UUID?,
    val fileName: String,
    val fileExtension: String,
    val fileSizeBytes: Long,
    val extractedText: String?,
    val createdAt: Instant,
    val vaultRelativePath: String,
    val sha256: String,
) {
    companion object {
        fun read(record: JsonRecord) = V2Attachment(
            id = record.id("id"), assetId = record.idOrNull("assetId"), eventId = record.idOrNull("eventId"),
            fileName = record.string("fileName"), fileExtension = record.string("fileExtension"),
            fileSizeBytes = record.long("fileSizeBytes"), extractedText = record.stringOrNull("extractedText"),
            createdAt = record.instant("createdAt"), vaultRelativePath = record.string("vaultRelativePath"),
            sha256 = record.string("sha256"),
        )
    }
}

/** The text rules the v2 conversion needs (search's words, a phone and a plate as stored), as the iOS app has them. */
internal object V2Text {
    /** The folded words, joined by single spaces (`SearchText.normalize`). */
    fun normalize(text: String): String = com.ar.dosarcusina.archive.Words.of(text).joinToString(" ")

    /**
     * Whether [phrase]'s words appear in order in [text], each as the start of a word (`SearchText.containsPhrase`).
     */
    fun containsPhrase(text: String, phrase: String): Boolean {
        val words = text.split(" ").filter { it.isNotEmpty() }
        val needle = phrase.split(" ").filter { it.isNotEmpty() }
        if (needle.isEmpty() || needle.size > words.size) return false
        return (0..words.size - needle.size).any { start ->
            needle.indices.all { words[start + it].startsWith(needle[it]) }
        }
    }

    /** A phone number as stored: digits, `+` kept, `00` read as `+` (`FieldFormatter.normalizePhone`). */
    fun phone(raw: String): String = com.ar.dosarcusina.archive.FieldFormatter.normalizePhone(raw)

    private val COUNTY_CODES = setOf(
        "AB", "AR", "AG", "BC", "BH", "BN", "BT", "BV", "BR", "BZ", "CS", "CL", "CJ", "CT", "CV", "DB", "DJ", "GL",
        "GR", "GJ",
        "HR", "HD", "IL", "IS", "IF", "MM", "MH", "MS", "NT", "OT", "PH", "SM", "SJ", "SB", "SV", "TR", "TM", "TL",
        "VS", "VL",
        "VN", "B",
    )
    private const val SUFFIX_LETTERS = 3

    /**
     * A Romanian plate as `B-123-ABC` / `CJ-12-XYZ`, else the text in capitals (`FieldFormatter.normalize(as:
     * .plate)`).
     */
    fun plate(raw: String): String {
        val trimmed = raw.trim()
        val compact = RomanianText.fold(trimmed).uppercase().filter(Char::isLetterOrDigit)
        val letters = compact.takeWhile(Char::isLetter)
        val digits = compact.drop(letters.length).takeWhile(Char::isDigit)
        val suffix = compact.drop(letters.length + digits.length)
        val digitCount = if (letters == "B") 2..3 else 2..2
        val isPlate = compact.all { it.code < 128 } && letters in COUNTY_CODES && suffix.length == SUFFIX_LETTERS &&
            suffix.all(Char::isLetter) && digits.length in digitCount
        return if (isPlate) "$letters-$digits-$suffix" else trimmed.uppercase()
    }
}
