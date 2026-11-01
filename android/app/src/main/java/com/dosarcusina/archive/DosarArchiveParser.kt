package com.dosarcusina.archive

import com.dosarcusina.data.DosarDatabase
import com.dosarcusina.data.AssetEntity
import com.dosarcusina.data.LifecycleEventEntity
import com.dosarcusina.data.ServiceItemEntity
import com.dosarcusina.data.MeasurementLogEntity
import com.dosarcusina.data.DynamicFieldEntity
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

public enum class ArchiveImportMode {
    MERGE, CLEAN_RESTORE
}

public data class ArchiveInspectionSummary(
    val schemaVersion: Int,
    val appVersion: String,
    val exportDate: String,
    val platform: String,
    val assetCount: Int,
    val eventCount: Int,
    val isValidIntegrity: Boolean
)

public data class ArchiveImportResult(
    val assetsImported: Int,
    val eventsImported: Int,
    val serviceItemsImported: Int,
    val measurementsImported: Int,
    val attachmentsImported: Int
)

/**
 * Cross-platform parser for .dosar open package archives.
 * Validates manifest schema v2, verifies SHA-256 integrity map, and imports records
 * into Room SQLite with MERGE or CLEAN_RESTORE semantics.
 */
public class DosarArchiveParser {

    companion object {
        fun computeSHA256(bytes: ByteArray): String {
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(bytes)
            return hash.joinToString("") { "%02x".format(it) }
        }

        private val isoFormats = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd"
        )

        fun parseIsoDate(dateStr: String?): Long {
            if (dateStr.isNullOrBlank()) return System.currentTimeMillis()
            for (pattern in isoFormats) {
                try {
                    val sdf = SimpleDateFormat(pattern, Locale.US).apply {
                        timeZone = TimeZone.getTimeZone("UTC")
                    }
                    val parsed = sdf.parse(dateStr)
                    if (parsed != null) return parsed.time
                } catch (_: Exception) {
                    // Try next pattern
                }
            }
            return System.currentTimeMillis()
        }
    }

    /**
     * Inspects a .dosar ZIP package and validates manifest and SHA-256 checksums.
     */
    fun inspectArchive(archiveFile: File): ArchiveInspectionSummary {
        val entryMap = mutableMapOf<String, ByteArray>()
        ZipInputStream(FileInputStream(archiveFile)).use { zis ->
            var entry: ZipEntry? = zis.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    entryMap[entry.name] = zis.readBytes()
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }

        val manifestBytes = entryMap["manifest.json"]
            ?: throw IllegalStateException("manifest.json missing from .dosar archive")

        val manifestObj = JSONObject(String(manifestBytes, Charsets.UTF_8))
        val schemaVer = manifestObj.getInt("schemaVersion")
        val appVer = manifestObj.optString("appVersion", "2.0.0")
        val exportDate = manifestObj.optString("exportDate", "")
        val platform = manifestObj.optString("platform", "Unknown")
        val counts = manifestObj.optJSONObject("entityCounts") ?: JSONObject()
        val checksums = manifestObj.optJSONObject("checksums") ?: JSONObject()

        var isValid = true
        val keys = checksums.keys()
        while (keys.hasNext()) {
            val path = keys.next()
            val expectedSha = checksums.getString(path)
            val fileBytes = entryMap[path]
            if (fileBytes == null || computeSHA256(fileBytes) != expectedSha) {
                isValid = false
                break
            }
        }

        return ArchiveInspectionSummary(
            schemaVersion = schemaVer,
            appVersion = appVer,
            exportDate = exportDate,
            platform = platform,
            assetCount = counts.optInt("assets", 0),
            eventCount = counts.optInt("events", 0),
            isValidIntegrity = isValid
        )
    }

    /**
     * Imports archive into Room SQLite database with support for MERGE or CLEAN_RESTORE.
     */
    suspend fun importArchive(
        archiveFile: File,
        mode: ArchiveImportMode,
        database: DosarDatabase,
        vaultStorageDir: File
    ): ArchiveImportResult {
        val entryMap = mutableMapOf<String, ByteArray>()
        ZipInputStream(FileInputStream(archiveFile)).use { zis ->
            var entry: ZipEntry? = zis.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    entryMap[entry.name] = zis.readBytes()
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }

        val manifestBytes = entryMap["manifest.json"]
            ?: throw IllegalStateException("manifest.json missing from .dosar archive")
        val manifestObj = JSONObject(String(manifestBytes, Charsets.UTF_8))
        val schemaVer = manifestObj.getInt("schemaVersion")
        if (schemaVer != 2) {
            throw IllegalStateException("Unsupported schemaVersion $schemaVer in .dosar archive (expected 2)")
        }

        val checksums = manifestObj.getJSONObject("checksums")

        // Verify SHA-256 for all data files
        val keys = checksums.keys()
        while (keys.hasNext()) {
            val path = keys.next()
            val expectedSha = checksums.getString(path)
            val fileBytes = entryMap[path]
                ?: throw IllegalStateException("Missing file referenced in checksums: $path")
            val actualSha = computeSHA256(fileBytes)
            if (actualSha != expectedSha) {
                throw IllegalStateException("Checksum mismatch for $path: expected $expectedSha, got $actualSha")
            }
        }

        // If Clean Restore, wipe existing data
        if (mode == ArchiveImportMode.CLEAN_RESTORE) {
            database.clearAllTables()
        }

        var assetsCount = 0
        var eventsCount = 0
        var serviceCount = 0
        var measurementsCount = 0
        var attachmentsCount = 0

        // Parse assets.json
        entryMap["data/assets.json"]?.let { bytes ->
            val arr = JSONArray(String(bytes, Charsets.UTF_8))
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val assetId = obj.getString("id")
                val entity = AssetEntity(
                    id = assetId,
                    name = obj.getString("name"),
                    subtitle = obj.optString("subtitle", null),
                    categoryRaw = obj.optString("categoryRaw", "home"),
                    iconName = obj.optString("iconName", "house.fill"),
                    accentColorHex = obj.optString("accentColorHex", "007AFF"),
                    currentMetricValue = obj.optDouble("currentMetricValue", Double.NaN).takeIf { !it.isNaN() },
                    metricUnit = obj.optString("metricUnit", null),
                    licensePlate = obj.optString("licensePlate", null),
                    vinNumber = obj.optString("vin", null),
                    manufactureYear = obj.optInt("manufactureYear", 0).takeIf { it > 0 },
                    fuelType = obj.optString("fuelType", null),
                    fullAddress = obj.optString("address", null),
                    surfaceAreaM2 = obj.optDouble("surfaceAreaSqm", Double.NaN).takeIf { !it.isNaN() },
                    constructionYear = obj.optInt("constructionYear", 0).takeIf { it > 0 },
                    heatingBoilerModel = obj.optString("heatingBoilerModel", null),
                    heatingBoilerSerial = obj.optString("heatingBoilerSerial", null),
                    gasMeterSerial = obj.optString("gasMeterSerial", null),
                    electricityMeterSerial = obj.optString("electricityMeterSerial", null),
                    waterMeterSerial = obj.optString("waterMeterSerial", null),
                    bloodType = obj.optString("bloodType", null),
                    familyDoctorName = obj.optString("familyDoctorName", null),
                    familyDoctorPhone = obj.optString("familyDoctorPhone", null),
                    emergencyContactName = obj.optString("emergencyContactName", null),
                    emergencyContactPhone = obj.optString("emergencyContactPhone", null),
                    allergiesNotes = obj.optString("allergies", null)
                )
                database.assetDao().insertAsset(entity)
                assetsCount++

                // Parse nested dynamic fields if any
                val fieldsArr = obj.optJSONArray("dynamicFields")
                if (fieldsArr != null) {
                    for (f in 0 until fieldsArr.length()) {
                        val fObj = fieldsArr.getJSONObject(f)
                        val field = DynamicFieldEntity(
                            id = fObj.optString("id", UUID.randomUUID().toString()),
                            assetId = assetId,
                            key = fObj.getString("key"),
                            label = fObj.getString("label"),
                            fieldTypeRaw = fObj.getString("fieldTypeRaw"),
                            stringValue = fObj.optString("stringValue", null),
                            numberValue = fObj.optDouble("numberValue", Double.NaN).takeIf { !it.isNaN() }
                        )
                        database.dynamicFieldDao().insertField(field)
                    }
                }
            }
        }

        // Parse events.json
        entryMap["data/events.json"]?.let { bytes ->
            val arr = JSONArray(String(bytes, Charsets.UTF_8))
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val dueDateStr = obj.optString("dueDate", null)
                val dueDateMs = parseIsoDate(dueDateStr)
                val ev = LifecycleEventEntity(
                    id = obj.getString("id"),
                    assetId = obj.getString("assetId"),
                    title = obj.getString("title"),
                    eventDescription = obj.optString("eventDescription", null),
                    dueDate = dueDateMs,
                    cost = obj.optDouble("cost", Double.NaN).takeIf { !it.isNaN() },
                    currency = obj.optString("currency", "RON"),
                    provider = obj.optString("provider", null),
                    policyOrContractNumber = obj.optString("policyOrContractNumber", null),
                    isCompleted = obj.optBoolean("isCompleted", false)
                )
                database.eventDao().insertEvent(ev)
                eventsCount++
            }
        }

        // Parse service_history.json
        entryMap["data/service_history.json"]?.let { bytes ->
            val arr = JSONArray(String(bytes, Charsets.UTF_8))
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val sDateStr = obj.optString("serviceDate", null)
                val sDateMs = parseIsoDate(sDateStr)
                val s = ServiceItemEntity(
                    id = obj.getString("id"),
                    assetId = obj.getString("assetId"),
                    eventId = obj.optString("eventId", null),
                    componentName = obj.getString("name"),
                    componentCategory = obj.optString("category", "General"),
                    partBrand = obj.optString("partBrandOrCode", null),
                    cost = obj.optDouble("cost", Double.NaN).takeIf { !it.isNaN() },
                    serviceDate = sDateMs,
                    mileageAtService = obj.optDouble("mileageAtService", Double.NaN).takeIf { !it.isNaN() },
                    notes = obj.optString("notes", null)
                )
                database.serviceItemDao().insert(s)
                serviceCount++
            }
        }

        // Parse measurements.json
        entryMap["data/measurements.json"]?.let { bytes ->
            val arr = JSONArray(String(bytes, Charsets.UTF_8))
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val recDateStr = obj.optString("recordedAt", null)
                val recDateMs = parseIsoDate(recDateStr)
                val m = MeasurementLogEntity(
                    id = obj.getString("id"),
                    assetId = obj.getString("assetId"),
                    domainRawValue = obj.getString("domainRawValue"),
                    metricName = obj.getString("metricName"),
                    value = obj.getDouble("value"),
                    secondaryValue = obj.optDouble("secondaryValue", Double.NaN).takeIf { !it.isNaN() },
                    unit = obj.getString("unit"),
                    recordedAt = recDateMs,
                    previousValue = obj.optDouble("previousValue", Double.NaN).takeIf { !it.isNaN() },
                    unitPrice = obj.optDouble("unitPrice", Double.NaN).takeIf { !it.isNaN() },
                    isSelfRead = obj.optBoolean("isSelfRead", true),
                    referenceMin = obj.optDouble("referenceMin", Double.NaN).takeIf { !it.isNaN() },
                    referenceMax = obj.optDouble("referenceMax", Double.NaN).takeIf { !it.isNaN() },
                    labOrProviderName = obj.optString("labOrProviderName", null),
                    notes = obj.optString("notes", null)
                )
                database.measurementLogDao().insert(m)
                measurementsCount++
            }
        }

        // Extract vault files
        if (!vaultStorageDir.exists()) vaultStorageDir.mkdirs()
        for ((name, data) in entryMap) {
            if (name.startsWith("vault/")) {
                val relativePath = name.removePrefix("vault/")
                if (relativePath.isNotEmpty()) {
                    val destFile = File(vaultStorageDir, relativePath)
                    destFile.parentFile?.mkdirs()
                    destFile.writeBytes(data)
                    attachmentsCount++
                }
            }
        }

        return ArchiveImportResult(
            assetsImported = assetsCount,
            eventsImported = eventsCount,
            serviceItemsImported = serviceCount,
            measurementsImported = measurementsCount,
            attachmentsImported = attachmentsCount
        )
    }
}
