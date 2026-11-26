package com.ar.dosarcusina.archive.v2

import com.ar.dosarcusina.archive.ArchiveError
import com.ar.dosarcusina.archive.DossierArchiveReader
import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.v3.ArchiveFiles
import com.ar.dosarcusina.archive.v3.AssetRecord
import com.ar.dosarcusina.archive.v3.AttachmentRecord
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.DossierPackage
import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.HistoryEntryRecord
import com.ar.dosarcusina.archive.v3.Ids
import com.ar.dosarcusina.archive.v3.JsonRecord
import com.ar.dosarcusina.archive.v3.Manifest
import com.ar.dosarcusina.archive.v3.MeasurementRecord
import com.ar.dosarcusina.archive.v3.ObligationRecord
import com.ar.dosarcusina.archive.v3.ProviderRecord
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.archive.v3.ServiceItemRecord
import com.ar.dosarcusina.archive.v3.UnreadableRecord
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.Money
import java.math.BigDecimal
import java.time.ZoneId
import java.util.UUID

/**
 * Reads schema-version 2 archives (exported by the first iOS builds) and turns them into a v3
 * package, as the iOS app's `DossierV2Converter` (ios/DosarCuSina/Services/Archive/DossierV2Converter.swift),
 * so older backups keep working. Nothing is dropped: values without a v3 field go into the
 * section's notes, contacts become firms, and completed events and service records become
 * history.
 *
 * A line item is matched to its category's parts by the app's own catalog ([BuiltIns]); one that
 * matches none gets its own `custom.` key.
 */
// Each mapping of the iOS converter, side by side.
@Suppress("TooManyFunctions")
object DossierV2Converter {
    const val SCHEMA_VERSION: Int = 2

    /** The files a version 2 archive describes itself with, read whole; every other file is a document's. */
    val DATA_FILES: Set<String> = setOf(
        "data/assets.json", "data/events.json", "data/service_history.json", "data/measurements.json",
        "data/attachments_meta.json",
    )

    /** The version 2 manifest's checksums, which the reader checks every file against. */
    fun checksums(manifest: ByteArray): Map<String, String> = manifest(manifest).checksums

    private class ManifestV2(
        val appVersion: String,
        val platform: String,
        val exportDate: java.time.Instant,
        val checksums: Map<String, String>,
    )

    private fun manifest(bytes: ByteArray): ManifestV2 = try {
        val record = JsonRecord.of(MachineText.parseOrNull(bytes.decodeToString()) ?: throw UnreadableRecord())
        record.int("schemaVersion")
        record.string("appName")
        record.string("deviceId")
        record.string("format")
        val counts = JsonRecord(record.obj("entityCounts"))
        for (key in listOf(
            "assets",
            "events",
            "serviceItems",
            "measurements",
            "dynamicFields",
            "attachments",
        )) counts.int(key)
        ManifestV2(
            record.string("appVersion"),
            record.string("platform"),
            record.instant("exportDate"),
            record.obj("checksums").mapValues { JsonRecord.text(it.value) },
        )
    } catch (_: UnreadableRecord) {
        throw ArchiveError.UnreadableFile(DossierV3.Path.MANIFEST)
    }

    /**
     * The v3 package an archive's version 2 files make. [data] are its data files, [vault] its
     * documents' files, both already checked against their checksums by [DossierArchiveReader].
     */
    fun pack(
        manifestBytes: ByteArray,
        data: Map<String, ByteArray>,
        vault: ArchiveFiles,
        builtIns: BuiltIns,
        zone: ZoneId = DosarCalendar.zone(),
    ): DossierPackage {
        val manifest = manifest(manifestBytes)
        fun <T> decode(path: String, read: (JsonRecord) -> T): List<T> {
            val bytes = data[path] ?: return emptyList()
            return try {
                JsonRecord.list(MachineText.parseOrNull(bytes.decodeToString()) ?: throw UnreadableRecord()).map {
                    read(JsonRecord.of(it))
                }
            } catch (_: UnreadableRecord) {
                throw ArchiveError.UnreadableFile(path)
            }
        }
        val converter = Converter(zone, builtIns)
        val converted = decode("data/assets.json", V2Asset::read).map(converter::convert)
        val assets = converted + converter.members.values.sortedBy { it.name }
        decode("data/events.json", V2Event::read).forEach(converter::convert)
        decode("data/service_history.json", V2ServiceItem::read).forEach(converter::convert)
        val measurements = decode("data/measurements.json", V2Measurement::read)
        val attachments = decode("data/attachments_meta.json", V2Attachment::read)

        val measurementForAttachment = HashMap<UUID, UUID>()
        for (log in measurements) for (attachment in log.attachmentIds) measurementForAttachment.putIfAbsent(
            attachment,
            log.id,
        )
        val v3Attachments = attachments.map { meta ->
            AttachmentRecord(
                id = Ids.text(meta.id), title = null, fileName = meta.fileName, kind = "other",
                contentType = contentType(meta.fileExtension), byteCount = meta.fileSizeBytes,
                sha256 = meta.sha256.lowercase(),
                path = meta.vaultRelativePath, pagePaths = emptyList(), thumbnailPath = null,
                extractedText = meta.extractedText,
                documentDate = null, isArchived = false, supersededById = null, createdAt = meta.createdAt,
                isExample = false,
                assetId = meta.assetId?.let(Ids::text), obligationId = meta.eventId?.let(Ids::text),
                historyEntryId = meta.eventId?.let { converter.entryForEvent[it] }, serviceItemId = null,
                measurementId = measurementForAttachment[meta.id]?.let(Ids::text), providerId = null, validUntil = null,
            )
        }
        val providers = converter.providers.values.sortedBy { it.name }
        val pack = DossierPackage(
            manifest = Manifest(
                format = DossierV3.FORMAT, schemaVersion = SCHEMA_VERSION, appVersion = manifest.appVersion,
                platform = manifest.platform, exportedAt = manifest.exportDate,
                counts = Manifest.Counts(
                    templates = 0, assets = assets.size, obligations = converter.obligations.size,
                    historyEntries = converter.entries.size, serviceItems = converter.items.size,
                    providers = providers.size,
                    measurements = measurements.size, attachments = v3Attachments.size,
                ),
                checksums = manifest.checksums,
            ),
            templates = emptyList(),
            assets = assets,
            obligations = converter.obligations,
            historyEntries = converter.entries,
            serviceItems = converter.items,
            providers = providers,
            measurements = measurements.map(::convert),
            attachments = v3Attachments,
            files = vault,
        )
        DossierArchiveReader.validateReferences(pack)
        return pack
    }

    fun templateKey(category: String): String = when (category) {
        "vehicle", "home", "pet", "health", "documents" -> category
        "warranties" -> "purchase"
        "subscriptions" -> "subscription"
        else -> "other"
    }

    /** The trade of the main contact of a section in a v2 category. */
    fun trade(category: String): String = when (category) {
        "vehicle" -> "mechanic"
        "home" -> "handyman"
        "pet" -> "vet"
        "health" -> "doctor"
        else -> "other"
    }

    /** How often an event repeated, in days, as a rule. */
    fun recurrence(cadenceDays: Int?): RecurrenceRule {
        val days = cadenceDays?.takeIf { it > 0 } ?: return RecurrenceRule.None
        return when {
            days == DAYS_IN_YEAR || days == DAYS_IN_LEAP_YEAR -> RecurrenceRule.Interval(1, "year", "dueDate")
            days == 2 * DAYS_IN_YEAR || days == 2 * DAYS_IN_YEAR + 1 -> RecurrenceRule.Interval(2, "year", "dueDate")
            days % DAYS_IN_YEAR == 0 -> RecurrenceRule.Interval(days / DAYS_IN_YEAR, "year", "dueDate")
            days % DAYS_IN_MONTH == 0 -> RecurrenceRule.Interval(days / DAYS_IN_MONTH, "month", "dueDate")
            days % DAYS_IN_WEEK == 0 -> RecurrenceRule.Interval(days / DAYS_IN_WEEK, "week", "dueDate")
            else -> RecurrenceRule.Interval(days, "day", "dueDate")
        }
    }

    /** An event's kind, from the words of its title, else its category. */
    fun kind(title: String, category: String): String {
        val text = V2Text.normalize(title)
        for ((kind, words) in KIND_WORDS) if (words.any { V2Text.containsPhrase(text, it) }) return kind
        return when (category) {
            "subscriptions" -> "payment"
            "documents" -> "renewal"
            "health", "pet" -> "health"
            else -> "maintenance"
        }
    }

    private val KIND_WORDS: List<Pair<String, List<String>>> = listOf(
        "legal" to listOf(
            "itp",
            "rovinieta",
            "vtp",
            "iscir",
            "verificare instalatie",
            "revizie instalatie",
            "antirabic",
        ),
        "insurance" to listOf("rca", "casco", "pad", "asigurare", "polita"),
        "tax" to listOf("impozit", "taxa", "declaratia", "anaf"),
        "health" to listOf("vaccin", "analize", "control", "deparazitare", "stomatolog", "screening"),
        "renewal" to listOf(
            "pasaport",
            "buletin",
            "carte de identitate",
            "permis",
            "reinnoire",
            "expirare",
            "garantie",
        ),
        "payment" to listOf("plata", "factura", "abonament", "chirie"),
    )

    /** The reminders a deadline of a kind starts from (`ObligationKind.defaultProfile`). */
    @Suppress("MagicNumber") // The profiles themselves.
    fun defaultProfile(kind: String): ReminderProfile = when (kind) {
        "legal", "insurance" -> ReminderProfile(listOf(30, 7, 0), "legal")
        "tax" -> ReminderProfile(listOf(14, 1), "financial")
        "health" -> ReminderProfile(listOf(7, 1), "health", graceDays = 7)
        "renewal" -> ReminderProfile(listOf(60, 30), "legal")
        "payment" -> ReminderProfile(listOf(2, 0), "financial")
        "maintenance" -> ReminderProfile(listOf(14, 1), "comfort", graceDays = 14)
        else -> ReminderProfile(listOf(0), "comfort", graceDays = 3)
    }

    /**
     * The history kind a completed event of one's own of [kind] is kept as (`HistoryKind.forCompleting(.own(kind),
     * …)`).
     */
    fun historyKind(kind: String): String = when (kind) {
        "legal" -> "inspection"
        "payment", "tax", "insurance" -> "payment"
        "health" -> "treatment"
        "renewal" -> "note"
        else -> "maintenance"
    }

    internal fun convert(dto: V2Measurement) = MeasurementRecord(
        id = Ids.text(dto.id), assetId = Ids.text(dto.assetId), kind = measurementKind(dto.domain, dto.unit),
        name = dto.metricName,
        value = dto.value, secondaryValue = dto.secondaryValue, unit = MeasurementUnit.storedKey(dto.unit),
        recordedAt = dto.recordedAt,
        unitPrice = dto.unitPrice?.let { Money(BigDecimal.valueOf(it)) }, isSelfRead = dto.isSelfRead,
        referenceMin = dto.referenceMin, referenceMax = dto.referenceMax, source = dto.labOrProviderName,
        notes = dto.notes,
        isExample = false,
    )

    /** v2 stored the Romanian display name of the domain; matched on its wording and unit. */
    fun measurementKind(domain: String, unit: String): String {
        val text = V2Text.normalize(domain)
        return when {
            "electric" in text -> "electricity"
            "gaze" in text -> "gas"
            "apa rece" in text -> "coldWater"
            "apa calda" in text -> "hotWater"
            "termic" in text -> "thermalEnergy"
            "tensiune" in text -> "bloodPressure"
            "greutate" in text -> "bodyWeight"
            "dioptri" in text -> "diopters"
            "kilometraj" in text || MeasurementUnit.of(unit) == MeasurementUnit.KILOMETRES -> "odometer"
            "analiz" in text || "biomarker" in text -> "biomarker"
            else -> "custom"
        }
    }

    fun contentType(extension: String): String = when (extension.lowercase()) {
        "pdf" -> "com.adobe.pdf"
        "jpg", "jpeg" -> "public.jpeg"
        "png" -> "public.png"
        "heic" -> "public.heic"
        "txt" -> "public.plain-text"
        else -> "public.data"
    }

    private const val DAYS_IN_YEAR = 365
    private const val DAYS_IN_LEAP_YEAR = 366
    private const val DAYS_IN_MONTH = 30
    private const val DAYS_IN_WEEK = 7

    /** Mutable state for one conversion: deadlines, history and firms built along the way. */
    internal class Converter(private val zone: ZoneId, private val builtIns: BuiltIns) {
        private val categoryOf = HashMap<UUID, String>()
        val obligations = ArrayList<ObligationRecord>()
        val entries = ArrayList<HistoryEntryRecord>()
        val items = ArrayList<ServiceItemRecord>()

        /** Firms by their normalized name, so the same mechanic on two cars is one record. */
        val providers = LinkedHashMap<String, ProviderRecord>()

        /** v2 event id → v3 history entry id, for completed events. */
        val entryForEvent = HashMap<UUID, String>()
        private val entryForVisit = HashMap<String, String>()

        /** Household members made for document holders, by normalized name. */
        val members = LinkedHashMap<String, AssetRecord>()

        private fun day(moment: java.time.Instant): CalendarDay = CalendarDay.of(moment, zone)

        /** The member for a holder's name, made once per name. */
        private fun member(name: String?, at: java.time.Instant): String? {
            val clean = name.orEmpty().trim()
            if (clean.isEmpty()) return null
            val key = V2Text.normalize(clean)
            members[key]?.let { return it.id }
            val member = AssetRecord(
                id = Ids.text(UUID.randomUUID()), templateKey = "member", name = clean, parentId = null,
                symbolOverride = null,
                tintOverride = null, notes = null, values = KeptObject.made(FieldValues(), FieldValues.codec),
                customFacts = null,
                photoPath = null, isExample = false, createdAt = at, updatedAt = at,
            )
            members[key] = member
            return member.id
        }

        private fun provider(
            name: String?,
            phone: String?,
            trade: String,
            assetId: UUID?,
            at: java.time.Instant,
        ): String? {
            val cleanName = name.orEmpty().trim()
            val cleanPhone = phone?.let(V2Text::phone)?.takeIf { it.isNotEmpty() }
            if (cleanName.isEmpty() && cleanPhone == null) return null
            val shown = cleanName.ifEmpty { cleanPhone.orEmpty() }
            val key = V2Text.normalize(shown)
            var record = providers[key] ?: ProviderRecord(
                id = Ids.text(UUID.randomUUID()), name = shown, trades = emptyList(), phone = cleanPhone, email = null,
                address = null, notes = null, manualRating = null, wouldCallAgain = null, assetIds = emptyList(),
                isExample = false, createdAt = at, updatedAt = at,
            )
            if (trade !in record.trades) record = record.copy(trades = record.trades + trade)
            if (assetId != null && Ids.text(assetId) !in record.assetIds) record =
                record.copy(assetIds = record.assetIds + Ids.text(assetId))
            record = record.copy(phone = record.phone ?: cleanPhone)
            providers[key] = record
            return record.id
        }

        fun convert(dto: V2Asset): AssetRecord {
            categoryOf[dto.id] = dto.category
            val key = templateKey(dto.category)
            val fill = V2AssetFields(zone)
            val parentId = when (key) {
                "documents" -> {
                    fill.document(dto)
                    // The holder becomes a household member the document is filed under.
                    member(dto.text("personName"), dto.createdAt)
                }
                else -> {
                    fill.fill(key, dto) { name, phone, trade -> provider(name, phone, trade, dto.id, dto.createdAt) }
                    null
                }
            }
            // The section's main contact becomes a firm that looks after it.
            val contact = provider(
                dto.text("primaryContactName"),
                dto.text("primaryContactPhone"),
                trade(dto.category),
                dto.id,
                dto.createdAt,
            )
            val email = dto.text("primaryContactEmail")
            if (contact != null && !email.isNullOrEmpty()) {
                providers.entries.firstOrNull {
                    it.value.id == contact
                }?.let { providers[it.key] = it.value.copy(email = email) }
            }
            if (key != "other") fill.note("Subtitlu", dto.text("subtitle"))
            for (field in dto.dynamicFields) fill.note(field.label, field.text(zone))
            val notes =
                (listOfNotNull(dto.text("notes")) + fill.leftovers).filter { it.isNotEmpty() }.joinToString("\n")
            return AssetRecord(
                id = Ids.text(dto.id), templateKey = key, name = dto.name, parentId = parentId, symbolOverride = null,
                tintOverride = null, notes = notes.ifEmpty { null },
                values = KeptObject.made(fill.values, FieldValues.codec),
                customFacts = null, photoPath = null, isExample = false, createdAt = dto.createdAt,
                updatedAt = dto.updatedAt,
            )
        }

        fun convert(dto: V2Event) {
            val category = categoryOf[dto.assetId] ?: "custom"
            val due = day(dto.dueDate)
            val cost = dto.cost?.let { Money(BigDecimal.valueOf(it), dto.currency) }
            val kind = kind(dto.title, category)
            var reminders = defaultProfile(kind)
            if (dto.reminderOffsetDays.isNotEmpty()) {
                reminders = ReminderProfile(
                    dto.reminderOffsetDays,
                    reminders.consequence,
                    reminders.graceDays,
                    reminders.followUpAfterLapse,
                )
            }
            val obligation = ObligationRecord(
                id = Ids.text(dto.id), assetId = Ids.text(dto.assetId), title = dto.title, notes = dto.eventDescription,
                blueprintKey = null, kind = kind, dueDate = due, dueMetric = dto.metricTriggerValue,
                reminders = KeptObject.made(reminders, ReminderProfile.codec), reminderMinuteOfDay = null,
                recurrence = KeptObject.made(recurrence(dto.cadenceDays), RecurrenceRule.codec),
                estimatedCost = if (dto.isCompleted) null else cost, provider = dto.provider,
                reference = dto.policyOrContractNumber,
                status = if (dto.isCompleted) "done" else "active", snoozedUntil = null, isExample = false,
                createdAt = dto.createdAt, updatedAt = dto.completedDate ?: dto.createdAt, remindersCustomized = null,
            )
            obligations += obligation
            if (!dto.isCompleted) return
            val entryId = Ids.text(UUID.randomUUID())
            entryForEvent[dto.id] = entryId
            entries += HistoryEntryRecord(
                id = entryId, assetId = Ids.text(dto.assetId), obligationId = obligation.id, kind = historyKind(kind),
                title = dto.title,
                occurredAt = dto.completedDate ?: dto.dueDate, metricReading = dto.mileageAtEvent, totalCost = cost,
                note = null,
                rating = null, cycleDueDate = due, nextDueDate = null, previousStatus = "active",
                previousDueMetric = null,
                providerIds = emptyList(), isExample = false,
            )
        }

        fun convert(dto: V2ServiceItem) {
            val category = categoryOf[dto.assetId] ?: "custom"
            val visitDay = day(dto.serviceDate)
            val providerId = provider(
                dto.shopName ?: dto.specialistOrDoctorName,
                null,
                trade(category),
                dto.assetId,
                dto.serviceDate,
            )
            val visit = "${Ids.text(dto.assetId)}|${visitDay.isoString}"
            val entryId = dto.eventId?.let { entryForEvent[it] } ?: entryForVisit[visit]
                ?: Ids.text(UUID.randomUUID()).also { made ->
                entryForVisit[visit] = made
                entries += HistoryEntryRecord(
                    id = made, assetId = Ids.text(dto.assetId), obligationId = null, kind = "maintenance",
                    title = dto.name,
                    occurredAt = dto.serviceDate, metricReading = dto.mileageAtService, totalCost = null, note = null,
                    rating = null,
                    cycleDueDate = null, nextDueDate = null, previousStatus = null, previousDueMetric = null,
                    providerIds = emptyList(), isExample = false,
                )
            }
            val index = entries.indexOfFirst { it.id == entryId }
            if (providerId != null && index >= 0 && providerId !in entries[index].providerIds) {
                entries[index] = entries[index].copy(providerIds = entries[index].providerIds + providerId)
            }
            val components = builtIns.definition(templateKey(category))?.components.orEmpty()
            items += ServiceItemRecord(
                id = Ids.text(dto.id), entryId = entryId, componentKey = componentKey(dto.name, components),
                name = dto.name,
                group = dto.category, partBrandOrCode = dto.partBrandOrCode, partSerialNumber = dto.partSerialNumber,
                cost = dto.cost?.let { Money(BigDecimal.valueOf(it)) },
                laborCost = dto.laborCost?.let { Money(BigDecimal.valueOf(it)) },
                partsCost = dto.partsCost?.let { Money(BigDecimal.valueOf(it)) }, supplierId = null,
                batchOrTicket = dto.serialOrBatchNumber, locationDetail = dto.locationOrToothNumber,
                daysInService = dto.daysInService, warrantyMonths = dto.warrantyMonths, notes = dto.notes,
                isExample = false,
            )
        }
    }

    /**
     * The catalog key for a line item's name, or a stable `custom.<slug>` for anything the
     * catalog doesn't know (`ComponentCatalog.key`): the longest name or synonym found in it wins.
     */
    fun componentKey(text: String, components: List<ComponentDefinition>): String {
        val haystack = V2Text.normalize(text)
        var best: Pair<ComponentDefinition, Int>? = null
        if (haystack.isNotEmpty()) {
            for (component in components) {
                for (phrase in listOf(component.name) + component.synonyms) {
                    val needle = V2Text.normalize(phrase)
                    if (needle.isEmpty() || !V2Text.containsPhrase(haystack, needle)) continue
                    if (needle.length > (best?.second ?: 0)) best = component to needle.length
                }
            }
        }
        best?.let { return it.first.key }
        val slug = haystack.split(" ").filter { it.isNotEmpty() }.joinToString("-")
        return "custom." + slug.ifEmpty { "item" }
    }
}

/** A v2 asset's fields, put into v3 values, with what has no v3 field kept for the notes. */
internal class V2AssetFields(private val zone: ZoneId) {
    var values = FieldValues()
        private set
    val leftovers = ArrayList<String>()

    private fun text(field: String, value: String?) {
        if (!value.isNullOrEmpty()) values = values.with(field, FieldValue.Text(value))
    }

    private fun number(field: String, value: Double?) {
        if (value != null) values = values.with(field, FieldValue.Number(value))
    }

    private fun day(field: String, value: java.time.Instant?) {
        if (value != null) values = values.with(field, FieldValue.Day(CalendarDay.of(value, zone)))
    }

    fun note(label: String, value: String?) {
        if (!value.isNullOrEmpty()) leftovers += "$label: $value"
    }

    fun document(dto: V2Asset) {
        text("document.number", dto.text("serialOrImei"))
        text("document.issuer", dto.text("retailerOrIssuer"))
        day("document.issueDate", dto.moment("purchaseOrIssueDate"))
        day("document.expiry", dto.moment("contractEndDate"))
    }

    /** Fills [key]'s fields from [dto]; [provider] makes the firms its contacts become. */
    fun fill(key: String, dto: V2Asset, provider: (String?, String?, String) -> String?) {
        when (key) {
            "vehicle" -> vehicle(dto)
            "home" -> home(dto)
            "pet" -> {
                text("pet.species", dto.text("petSpecies") ?: dto.text("speciesAndBreed"))
                text("pet.breed", dto.text("petBreed"))
                day("pet.birthDate", dto.moment("birthDate"))
                text("pet.microchip", dto.text("microchipNumber"))
                text("pet.passport", dto.text("petPassportNumber"))
                number("pet.weight", dto.number("weightKg"))
                provider(
                    dto.text("veterinarianClinic") ?: dto.text("vetContactInfo"),
                    dto.text("veterinarianPhone"),
                    "vet",
                )
            }
            "health" -> {
                day("health.birthDate", dto.moment("birthDate"))
                text("health.bloodType", dto.text("bloodType"))
                text("health.allergies", dto.text("allergies"))
                text("health.conditions", dto.text("chronicConditions"))
                provider(dto.text("familyDoctorName"), dto.text("familyDoctorPhone"), "doctor")
                provider(
                    dto.text("emergencyContactName") ?: dto.text("emergencyContact"),
                    dto.text("emergencyContactPhone"),
                    "emergencyContact",
                )
                note("Persoană", dto.text("personName"))
            }
            "purchase" -> purchase(dto)
            "subscription" -> {
                text("subscription.provider", dto.text("providerName"))
                dto.number("recurringAmount")?.let { values = values.with(
                    "subscription.price",
                    FieldValue.Amount(Money(BigDecimal.valueOf(it), dto.currencyCode)),
                ) }
                text("subscription.cycle", dto.text("billingCycle"))
                day("subscription.contractEnd", dto.moment("contractEndDate"))
                text("subscription.cancelUrl", dto.text("cancellationUrl"))
                text("subscription.card", dto.text("paymentCardLast4"))
            }
            else -> text("other.description", dto.text("subtitle"))
        }
    }

    private fun vehicle(dto: V2Asset) {
        text("vehicle.plate", dto.text("licensePlate")?.let(V2Text::plate))
        text("vehicle.make", dto.text("make"))
        text("vehicle.model", dto.text("modelName"))
        number("vehicle.year", dto.number("manufactureYear"))
        text("vehicle.vin", dto.text("vin"))
        text("vehicle.civ", dto.text("civSeries"))
        number("vehicle.odometer", dto.number("currentMetricValue"))
        text("vehicle.fuel", dto.text("fuelType"))
        number("vehicle.engineCc", dto.number("engineDisplacementCc"))
        // v2 stored horsepower in a field named for kilowatts; it was always entered as CP.
        number("vehicle.powerHp", dto.number("enginePowerKw"))
        note("Motor", dto.text("engineSpecs"))
    }

    private fun home(dto: V2Asset) {
        text("home.address", dto.text("address"))
        number("home.area", dto.number("surfaceAreaSqm"))
        number("home.year", dto.number("constructionYear"))
        text("home.cadastral", dto.text("cadastralNumber"))
        text("home.pod", dto.text("podCode"))
        text("home.clc", dto.text("clcCode"))
        text("home.waterCode", dto.text("waterClientCode"))
        number("home.meterReadFrom", dto.number("meterReadWindowStartDay"))
        number("home.meterReadTo", dto.number("meterReadWindowEndDay"))
        text("home.boilerModel", dto.text("heatingBoilerModel"))
        text("home.boilerSerial", dto.text("heatingBoilerSerial"))
        note("Contor gaze", dto.text("gasMeterSerial"))
        note("Contor energie", dto.text("electricityMeterSerial"))
        note("Contor apă", dto.text("waterMeterSerial"))
        note("Centrală", dto.text("heatingBoilerSpecs"))
        note("Contoare", dto.text("meterSerials"))
    }

    private fun purchase(dto: V2Asset) {
        text("purchase.brand", dto.text("make"))
        text("purchase.model", dto.text("modelName"))
        text("purchase.serial", dto.text("serialOrImei"))
        text("purchase.retailer", dto.text("retailerOrIssuer"))
        day("purchase.date", dto.moment("purchaseOrIssueDate"))
        dto.number("purchasePrice")?.let {
            values = values.with("purchase.price", FieldValue.Amount(Money(BigDecimal.valueOf(it), dto.currencyCode)))
        }
        val months = (dto.int("warrantyMonths") ?: DEFAULT_WARRANTY_MONTHS) + (dto.int("extendedWarrantyMonths") ?: 0)
        number("purchase.warrantyMonths", months.toDouble())
        dto.moment("purchaseOrIssueDate")?.let { bought ->
            values =
                values.with("purchase.warrantyUntil", FieldValue.Day(CalendarDay.of(bought, zone).addingMonths(months)))
        }
    }

    private companion object {
        /** Two years: the legal guarantee a v2 purchase had when it said nothing. */
        const val DEFAULT_WARRANTY_MONTHS = 24
    }
}
