import Foundation
import SwiftData
import CryptoKit

// MARK: - Enums & Summaries

public enum ArchiveImportMode: String, CaseIterable, Sendable {
    case merge = "Îmbinare (Merge)"
    case cleanRestore = "Restaurare Curată (Clean Restore)"
}

public struct ArchiveInspectionSummary: Sendable {
    public let manifest: DossierManifestV2
    public let fileURL: URL
    public let totalByteSize: Int64
    public let isValidIntegrity: Bool
    
    public init(
        manifest: DossierManifestV2,
        fileURL: URL,
        totalByteSize: Int64,
        isValidIntegrity: Bool
    ) {
        self.manifest = manifest
        self.fileURL = fileURL
        self.totalByteSize = totalByteSize
        self.isValidIntegrity = isValidIntegrity
    }
}

public struct ArchiveImportResult: Sendable {
    public let assetsImported: Int
    public let assetsUpdated: Int
    public let eventsImported: Int
    public let eventsUpdated: Int
    public let serviceItemsImported: Int
    public let measurementsImported: Int
    public let attachmentsImported: Int
    
    public init(
        assetsImported: Int = 0,
        assetsUpdated: Int = 0,
        eventsImported: Int = 0,
        eventsUpdated: Int = 0,
        serviceItemsImported: Int = 0,
        measurementsImported: Int = 0,
        attachmentsImported: Int = 0
    ) {
        self.assetsImported = assetsImported
        self.assetsUpdated = assetsUpdated
        self.eventsImported = eventsImported
        self.eventsUpdated = eventsUpdated
        self.serviceItemsImported = serviceItemsImported
        self.measurementsImported = measurementsImported
        self.attachmentsImported = attachmentsImported
    }
}

public enum ArchiveError: LocalizedError, Sendable {
    case manifestMissing
    case invalidManifest(String)
    case unsupportedSchemaVersion(Int)
    case checksumMismatch(file: String, expected: String, actual: String)
    case missingDataFile(String)
    case invalidArchiveStructure
    case exportFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "Arhiva nu conține fișierul obligatoriu 'manifest.json'."
        case .invalidManifest(let reason):
            return "Fișierul manifest este invalid: \(reason)"
        case .unsupportedSchemaVersion(let v):
            return "Versiune de schemă arhivă nesuportată: \(v). Aplicația suportă versiunile 1 și 2."
        case .checksumMismatch(let file, let exp, let act):
            return "Eroare de integritate SHA-256 pentru '\(file)': așteptat \(exp), calculat \(act)."
        case .missingDataFile(let f):
            return "Fișierul de date obligatoriu '\(f)' lipsește din arhivă."
        case .invalidArchiveStructure:
            return "Structura arhivei .dosar este coruptă sau invalidă."
        case .exportFailed(let reason):
            return "Exportul arhivei a eșuat: \(reason)"
        }
    }
}

// MARK: - Dossier Archive Service

/// Central coordinator for exporting and importing `.dosar` open package archives.
/// Packages `manifest.json`, `data/*.json`, `vault/*` raw binaries, and `opis.pdf`
/// with full SHA-256 integrity validation and support for Merge and Clean Restore modes.
public final class DossierArchiveService: Sendable {
    public static let shared = DossierArchiveService()
    
    public init() {}
    
    // MARK: - SHA-256 Helper
    
    public static func computeSHA256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Export Engine
    
    /// Exports all household assets, events, service items, measurements, dynamic fields,
    /// attachments, and the auto-generated Opis Documente into a standardized `.dosar` archive.
    @MainActor
    public func exportHouseholdArchive(
        context: ModelContext,
        targetDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        // 1. Fetch all local records
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let events = try context.fetch(FetchDescriptor<LifecycleEvent>())
        let serviceItems = try context.fetch(FetchDescriptor<ServiceItem>())
        let measurements = try context.fetch(FetchDescriptor<MeasurementLog>())
        let attachments = try context.fetch(FetchDescriptor<DocumentAttachment>())
        
        let encoder = JSONEncoder.dosarArchiveEncoder()
        
        // 2. Map to DTOs
        var assetDTOs: [AssetDTO] = []
        var dynamicFieldsCount = 0
        for asset in assets {
            var fieldDTOs: [DynamicFieldDTO] = []
            for field in asset.dynamicFields {
                fieldDTOs.append(DynamicFieldDTO(
                    id: field.id,
                    key: field.key,
                    label: field.label,
                    fieldTypeRaw: field.fieldTypeRaw,
                    stringValue: field.stringValue,
                    numberValue: field.numberValue,
                    dateValue: field.dateValue,
                    boolValue: field.boolValue
                ))
            }
            dynamicFieldsCount += fieldDTOs.count
            
            assetDTOs.append(AssetDTO(
                id: asset.id,
                name: asset.name,
                subtitle: asset.subtitle,
                categoryRaw: asset.categoryRaw,
                customCategoryName: asset.customCategoryName,
                iconName: asset.iconName,
                accentColorHex: asset.accentColorHex,
                notes: asset.notes,
                currentMetricValue: asset.currentMetricValue,
                metricUnit: asset.metricUnit,
                vin: asset.vin,
                licensePlate: asset.licensePlate,
                civSeries: asset.civSeries,
                make: asset.make,
                modelName: asset.modelName,
                manufactureYear: asset.manufactureYear,
                fuelType: asset.fuelType,
                engineSpecs: asset.engineSpecs,
                engineDisplacementCc: asset.engineDisplacementCc,
                enginePowerKw: asset.enginePowerKw,
                address: asset.address,
                cadastralNumber: asset.cadastralNumber,
                surfaceAreaSqm: asset.surfaceAreaSqm,
                constructionYear: asset.constructionYear,
                podCode: asset.podCode,
                clcCode: asset.clcCode,
                waterClientCode: asset.waterClientCode,
                meterReadWindowStartDay: asset.meterReadWindowStartDay,
                meterReadWindowEndDay: asset.meterReadWindowEndDay,
                heatingBoilerModel: asset.heatingBoilerModel,
                heatingBoilerSerial: asset.heatingBoilerSerial,
                gasMeterSerial: asset.gasMeterSerial,
                electricityMeterSerial: asset.electricityMeterSerial,
                waterMeterSerial: asset.waterMeterSerial,
                heatingBoilerSpecs: asset.heatingBoilerSpecs,
                meterSerials: asset.meterSerials,
                personName: asset.personName,
                birthDate: asset.birthDate,
                bloodType: asset.bloodType,
                allergies: asset.allergies,
                chronicConditions: asset.chronicConditions,
                emergencyContact: asset.emergencyContact,
                familyDoctorName: asset.familyDoctorName,
                familyDoctorPhone: asset.familyDoctorPhone,
                emergencyContactName: asset.emergencyContactName,
                emergencyContactPhone: asset.emergencyContactPhone,
                microchipNumber: asset.microchipNumber,
                petPassportNumber: asset.petPassportNumber,
                speciesAndBreed: asset.speciesAndBreed,
                weightKg: asset.weightKg,
                petSpecies: asset.petSpecies,
                petBreed: asset.petBreed,
                vetContactInfo: asset.vetContactInfo,
                veterinarianClinic: asset.veterinarianClinic,
                veterinarianPhone: asset.veterinarianPhone,
                serialOrImei: asset.serialOrImei,
                retailerOrIssuer: asset.retailerOrIssuer,
                purchaseOrIssueDate: asset.purchaseOrIssueDate,
                purchasePrice: asset.purchasePrice,
                warrantyMonths: asset.warrantyMonths,
                extendedWarrantyMonths: asset.extendedWarrantyMonths,
                providerName: asset.providerName,
                billingCycle: asset.billingCycle,
                recurringAmount: asset.recurringAmount,
                currencyCode: asset.currencyCode,
                paymentCardLast4: asset.paymentCardLast4,
                cancellationUrl: asset.cancellationUrl,
                contractEndDate: asset.contractEndDate,
                primaryContactName: asset.primaryContactName,
                primaryContactRole: asset.primaryContactRole,
                primaryContactPhone: asset.primaryContactPhone,
                primaryContactEmail: asset.primaryContactEmail,
                createdAt: asset.createdAt,
                updatedAt: asset.updatedAt,
                dynamicFields: fieldDTOs
            ))
        }
        
        var eventDTOs: [LifecycleEventDTO] = []
        for event in events {
            guard let parentAssetId = event.asset?.id else { continue }
            let attIds = event.attachments.map { $0.id }
            eventDTOs.append(LifecycleEventDTO(
                id: event.id,
                assetId: parentAssetId,
                title: event.title,
                eventDescription: event.eventDescription,
                dueDate: event.dueDate,
                completedDate: event.completedDate,
                isCompleted: event.isCompleted,
                cost: event.cost,
                currency: event.currency,
                provider: event.provider,
                policyOrContractNumber: event.policyOrContractNumber,
                coverageType: event.coverageType,
                bonusMalusClass: event.bonusMalusClass,
                mileageAtEvent: event.mileageAtEvent,
                serviceLocation: event.serviceLocation,
                insuredCoverageAmount: event.insuredCoverageAmount,
                franchiseAmount: event.franchiseAmount,
                startDate: event.startDate,
                isAutoRenew: event.isAutoRenew,
                calendarEventIdentifier: event.calendarEventIdentifier,
                reminderItemIdentifier: event.reminderItemIdentifier,
                cadenceDays: event.cadenceDays,
                cadenceMetricInterval: event.cadenceMetricInterval,
                metricTriggerValue: event.metricTriggerValue,
                reminderOffsetDays: event.reminderOffsetDays,
                createdAt: event.createdAt,
                attachmentIds: attIds
            ))
        }
        
        var serviceDTOs: [ServiceItemDTO] = []
        for s in serviceItems {
            guard let parentAssetId = s.asset?.id else { continue }
            serviceDTOs.append(ServiceItemDTO(
                id: s.id,
                assetId: parentAssetId,
                eventId: s.event?.id,
                name: s.name,
                category: s.category,
                partBrandOrCode: s.partBrandOrCode,
                partSerialNumber: s.partSerialNumber,
                cost: s.cost,
                laborCost: s.laborCost,
                partsCost: s.partsCost,
                serviceDate: s.serviceDate,
                mileageAtService: s.mileageAtService,
                specialistOrDoctorName: s.specialistOrDoctorName,
                serialOrBatchNumber: s.serialOrBatchNumber,
                locationOrToothNumber: s.locationOrToothNumber,
                daysInService: s.daysInService,
                warrantyMonths: s.warrantyMonths,
                nextDueDate: s.nextDueDate,
                nextDueMileageKm: s.nextDueMileageKm,
                shopName: s.shopName,
                notes: s.notes
            ))
        }
        
        var measurementDTOs: [MeasurementLogDTO] = []
        for m in measurements {
            guard let parentAssetId = m.asset?.id else { continue }
            let attIds = m.attachments.map { $0.id }
            measurementDTOs.append(MeasurementLogDTO(
                id: m.id,
                assetId: parentAssetId,
                domainRawValue: m.domainRawValue,
                metricName: m.metricName,
                value: m.value,
                secondaryValue: m.secondaryValue,
                unit: m.unit,
                recordedAt: m.recordedAt,
                previousValue: m.previousValue,
                unitPrice: m.unitPrice,
                isSelfRead: m.isSelfRead,
                referenceMin: m.referenceMin,
                referenceMax: m.referenceMax,
                labOrProviderName: m.labOrProviderName,
                notes: m.notes,
                attachmentIds: attIds
            ))
        }
        
        // 3. Encode Data Payloads & Vault Files
        var zipEntries: [DosarZipEngine.Entry] = []
        var checksumMap: [String: String] = [:]
        
        let assetsData = try encoder.encode(assetDTOs)
        let assetsPath = "data/assets.json"
        checksumMap[assetsPath] = Self.computeSHA256(of: assetsData)
        zipEntries.append(DosarZipEngine.Entry(path: assetsPath, data: assetsData))
        
        let eventsData = try encoder.encode(eventDTOs)
        let eventsPath = "data/events.json"
        checksumMap[eventsPath] = Self.computeSHA256(of: eventsData)
        zipEntries.append(DosarZipEngine.Entry(path: eventsPath, data: eventsData))
        
        let serviceData = try encoder.encode(serviceDTOs)
        let servicePath = "data/service_history.json"
        checksumMap[servicePath] = Self.computeSHA256(of: serviceData)
        zipEntries.append(DosarZipEngine.Entry(path: servicePath, data: serviceData))
        
        let measurementData = try encoder.encode(measurementDTOs)
        let measurementPath = "data/measurements.json"
        checksumMap[measurementPath] = Self.computeSHA256(of: measurementData)
        zipEntries.append(DosarZipEngine.Entry(path: measurementPath, data: measurementData))
        
        // 4. Attachments Vault & Metadata
        var metaDTOs: [AttachmentMetadataDTO] = []
        for att in attachments {
            let ext = att.fileExtension.isEmpty ? "bin" : att.fileExtension.lowercased()
            let vaultPath = "vault/\(att.id.uuidString).\(ext)"
            let payload = att.fileData ?? Data()
            let sha = Self.computeSHA256(of: payload)
            
            checksumMap[vaultPath] = sha
            zipEntries.append(DosarZipEngine.Entry(path: vaultPath, data: payload, modifiedDate: att.createdAt))
            
            metaDTOs.append(AttachmentMetadataDTO(
                id: att.id,
                assetId: att.asset?.id,
                eventId: att.event?.id,
                fileName: att.fileName,
                fileExtension: ext,
                fileSizeBytes: Int64(payload.count),
                extractedText: att.extractedText,
                createdAt: att.createdAt,
                vaultRelativePath: vaultPath,
                sha256: sha
            ))
        }
        
        let metaData = try encoder.encode(metaDTOs)
        let metaPath = "data/attachments_meta.json"
        checksumMap[metaPath] = Self.computeSHA256(of: metaData)
        zipEntries.append(DosarZipEngine.Entry(path: metaPath, data: metaData))
        
        // 5. Generate Opis Documente PDF
        let opisData = PDFDossierGenerator.shared.generateHouseholdDossier(for: assets, title: "Dosar Administrativ al Gospodăriei")
        let opisPath = "opis.pdf"
        checksumMap[opisPath] = Self.computeSHA256(of: opisData)
        zipEntries.append(DosarZipEngine.Entry(path: opisPath, data: opisData))
        
        // 6. Build Manifest v2
        let entityCounts = DossierManifestV2.EntityCounts(
            assets: assetDTOs.count,
            events: eventDTOs.count,
            serviceItems: serviceDTOs.count,
            measurements: measurementDTOs.count,
            dynamicFields: dynamicFieldsCount,
            attachments: attachments.count
        )
        
        let manifest = DossierManifestV2(
            schemaVersion: 2,
            appVersion: "2.0.0",
            appName: "Dosar cu Șină",
            exportDate: Date(),
            platform: "iOS",
            deviceId: UUID().uuidString,
            format: "com.ar.dosarcusina.dossier",
            entityCounts: entityCounts,
            checksums: checksumMap
        )
        
        let manifestData = try encoder.encode(manifest)
        // Add manifest.json as the very first entry
        zipEntries.insert(DosarZipEngine.Entry(path: "manifest.json", data: manifestData), at: 0)
        
        // 7. Compress into PKZip .dosar archive
        let archiveBytes = try DosarZipEngine.createArchive(entries: zipEntries)
        
        let dateStamp = Int(Date().timeIntervalSince1970)
        let fileName = "Dosar_Complet_\(dateStamp).dosar"
        let outputURL = targetDirectory.appendingPathComponent(fileName)
        try archiveBytes.write(to: outputURL, options: .atomic)
        
        return outputURL
    }
    
    // MARK: - Inspection Engine
    
    /// Inspects a `.dosar` archive without modifying local database state.
    /// Validates `manifest.json`, checks schema version, and verifies SHA-256 integrity map.
    public func inspectArchive(at url: URL) throws -> ArchiveInspectionSummary {
        let archiveData = try Data(contentsOf: url)
        let entries = try DosarZipEngine.unpackArchive(archiveData)
        
        guard let manifestEntry = entries.first(where: { $0.path == "manifest.json" }) else {
            throw ArchiveError.manifestMissing
        }
        
        let decoder = JSONDecoder.dosarArchiveDecoder()
        guard let manifest = try? decoder.decode(DossierManifestV2.self, from: manifestEntry.data) else {
            throw ArchiveError.invalidManifest("Nu s-a putut decodifica structura DossierManifestV2.")
        }
        
        guard manifest.schemaVersion >= 1 && manifest.schemaVersion <= 2 else {
            throw ArchiveError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        
        // Verify Checksums
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        var isValid = true
        
        for (relPath, expectedSHA) in manifest.checksums {
            guard let fileData = entryMap[relPath] else {
                isValid = false
                break
            }
            let actualSHA = Self.computeSHA256(of: fileData)
            if actualSHA.lowercased() != expectedSHA.lowercased() {
                isValid = false
                break
            }
        }
        
        return ArchiveInspectionSummary(
            manifest: manifest,
            fileURL: url,
            totalByteSize: Int64(archiveData.count),
            isValidIntegrity: isValid
        )
    }
    
    // MARK: - Import Engine (Merge & Clean Restore)
    
    /// Imports a `.dosar` archive into the local SwiftData storage.
    /// Supports `cleanRestore` (wipes local state first) and `merge` (timestamp-based conflict resolution).
    @MainActor
    public func importArchive(
        at url: URL,
        mode: ArchiveImportMode,
        context: ModelContext
    ) throws -> ArchiveImportResult {
        let archiveData = try Data(contentsOf: url)
        let entries = try DosarZipEngine.unpackArchive(archiveData)
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        
        // 1. Read and validate manifest
        guard let manifestData = entryMap["manifest.json"] else {
            throw ArchiveError.manifestMissing
        }
        let decoder = JSONDecoder.dosarArchiveDecoder()
        let manifest = try decoder.decode(DossierManifestV2.self, from: manifestData)
        
        guard manifest.schemaVersion >= 1 && manifest.schemaVersion <= 2 else {
            throw ArchiveError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        
        // 2. Strict SHA-256 Integrity Verification
        for (relPath, expectedSHA) in manifest.checksums {
            guard let fileData = entryMap[relPath] else {
                throw ArchiveError.missingDataFile(relPath)
            }
            let actualSHA = Self.computeSHA256(of: fileData)
            if actualSHA.lowercased() != expectedSHA.lowercased() {
                throw ArchiveError.checksumMismatch(file: relPath, expected: expectedSHA, actual: actualSHA)
            }
        }
        
        // 3. Decode JSON Entities
        guard let assetsJSON = entryMap["data/assets.json"] else {
            throw ArchiveError.missingDataFile("data/assets.json")
        }
        let incomingAssets = try decoder.decode([AssetDTO].self, from: assetsJSON)
        
        let incomingEvents: [LifecycleEventDTO]
        if let eventsJSON = entryMap["data/events.json"] {
            incomingEvents = try decoder.decode([LifecycleEventDTO].self, from: eventsJSON)
        } else {
            incomingEvents = []
        }
        
        let incomingServiceItems: [ServiceItemDTO]
        if let serviceJSON = entryMap["data/service_history.json"] {
            incomingServiceItems = try decoder.decode([ServiceItemDTO].self, from: serviceJSON)
        } else {
            incomingServiceItems = []
        }
        
        let incomingMeasurements: [MeasurementLogDTO]
        if let measJSON = entryMap["data/measurements.json"] {
            incomingMeasurements = try decoder.decode([MeasurementLogDTO].self, from: measJSON)
        } else {
            incomingMeasurements = []
        }
        
        let incomingAttachmentsMeta: [AttachmentMetadataDTO]
        if let metaJSON = entryMap["data/attachments_meta.json"] {
            incomingAttachmentsMeta = try decoder.decode([AttachmentMetadataDTO].self, from: metaJSON)
        } else {
            incomingAttachmentsMeta = []
        }
        
        // 4. Execute Clean Restore or Merge
        if mode == .cleanRestore {
            // Delete all existing records
            let existingMeasurements = try context.fetch(FetchDescriptor<MeasurementLog>())
            for m in existingMeasurements { context.delete(m) }
            
            let existingService = try context.fetch(FetchDescriptor<ServiceItem>())
            for s in existingService { context.delete(s) }
            
            let existingEvents = try context.fetch(FetchDescriptor<LifecycleEvent>())
            for e in existingEvents { context.delete(e) }
            
            let existingAttachments = try context.fetch(FetchDescriptor<DocumentAttachment>())
            for a in existingAttachments { context.delete(a) }
            
            let existingFields = try context.fetch(FetchDescriptor<DynamicField>())
            for f in existingFields { context.delete(f) }
            
            let existingAssets = try context.fetch(FetchDescriptor<Asset>())
            for a in existingAssets { context.delete(a) }
            
            try context.save()
        }
        
        // Fetch remaining/existing entities into lookup maps
        let currentAssets = try context.fetch(FetchDescriptor<Asset>())
        var assetMap = Dictionary(uniqueKeysWithValues: currentAssets.map { ($0.id, $0) })
        
        let currentEvents = try context.fetch(FetchDescriptor<LifecycleEvent>())
        var eventMap = Dictionary(uniqueKeysWithValues: currentEvents.map { ($0.id, $0) })
        
        let currentService = try context.fetch(FetchDescriptor<ServiceItem>())
        var serviceMap = Dictionary(uniqueKeysWithValues: currentService.map { ($0.id, $0) })
        
        let currentMeas = try context.fetch(FetchDescriptor<MeasurementLog>())
        var measMap = Dictionary(uniqueKeysWithValues: currentMeas.map { ($0.id, $0) })
        
        let currentAtts = try context.fetch(FetchDescriptor<DocumentAttachment>())
        var attMap = Dictionary(uniqueKeysWithValues: currentAtts.map { ($0.id, $0) })
        
        var assetsImportedCount = 0
        var assetsUpdatedCount = 0
        var eventsImportedCount = 0
        var eventsUpdatedCount = 0
        var serviceImportedCount = 0
        var measurementsImportedCount = 0
        var attachmentsImportedCount = 0
        
        // Process Assets
        for dto in incomingAssets {
            if let existing = assetMap[dto.id] {
                // Merge Mode: update only if incoming is newer
                if dto.updatedAt > existing.updatedAt {
                    applyAssetDTO(dto, to: existing)
                    mergeDynamicFields(from: dto.dynamicFields, into: existing, context: context)
                    assetsUpdatedCount += 1
                }
            } else {
                let newAsset = Asset(
                    id: dto.id,
                    name: dto.name,
                    subtitle: dto.subtitle,
                    category: AssetCategory(rawValue: dto.categoryRaw) ?? .custom,
                    iconName: dto.iconName,
                    accentColorHex: dto.accentColorHex,
                    notes: dto.notes,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                applyAssetDTO(dto, to: newAsset)
                context.insert(newAsset)
                mergeDynamicFields(from: dto.dynamicFields, into: newAsset, context: context)
                assetMap[newAsset.id] = newAsset
                assetsImportedCount += 1
            }
        }
        
        // Process Lifecycle Events
        for dto in incomingEvents {
            guard let parentAsset = assetMap[dto.assetId] else { continue }
            if let existing = eventMap[dto.id] {
                if dto.createdAt > existing.createdAt {
                    applyEventDTO(dto, to: existing)
                    existing.asset = parentAsset
                    eventsUpdatedCount += 1
                }
            } else {
                let newEvent = LifecycleEvent(
                    id: dto.id,
                    title: dto.title,
                    eventDescription: dto.eventDescription,
                    dueDate: dto.dueDate,
                    completedDate: dto.completedDate,
                    isCompleted: dto.isCompleted,
                    cost: dto.cost,
                    currency: dto.currency,
                    cadenceDays: dto.cadenceDays,
                    cadenceMetricInterval: dto.cadenceMetricInterval,
                    metricTriggerValue: dto.metricTriggerValue,
                    reminderOffsetDays: dto.reminderOffsetDays,
                    createdAt: dto.createdAt
                )
                newEvent.asset = parentAsset
                applyEventDTO(dto, to: newEvent)
                context.insert(newEvent)
                eventMap[newEvent.id] = newEvent
                eventsImportedCount += 1
            }
        }
        
        // Process Service Items
        for dto in incomingServiceItems {
            guard let parentAsset = assetMap[dto.assetId] else { continue }
            if let existing = serviceMap[dto.id] {
                applyServiceDTO(dto, to: existing)
                existing.asset = parentAsset
                existing.event = dto.eventId.flatMap { eventMap[$0] }
            } else {
                let newService = ServiceItem(
                    id: dto.id,
                    name: dto.name,
                    category: dto.category,
                    partBrand: dto.partBrandOrCode,
                    partSerialNumber: dto.partSerialNumber,
                    cost: dto.cost,
                    laborCost: dto.laborCost,
                    partsCost: dto.partsCost,
                    serviceDate: dto.serviceDate,
                    mileageAtService: dto.mileageAtService,
                    specialistOrDoctorName: dto.specialistOrDoctorName,
                    serialOrBatchNumber: dto.serialOrBatchNumber,
                    locationOrToothNumber: dto.locationOrToothNumber,
                    daysInService: dto.daysInService,
                    warrantyMonths: dto.warrantyMonths,
                    nextDueDate: dto.nextDueDate,
                    nextDueMileageKm: dto.nextDueMileageKm,
                    shopName: dto.shopName,
                    notes: dto.notes
                )
                newService.asset = parentAsset
                newService.event = dto.eventId.flatMap { eventMap[$0] }
                context.insert(newService)
                serviceMap[newService.id] = newService
                serviceImportedCount += 1
            }
        }
        
        // Process Measurements
        for dto in incomingMeasurements {
            guard let parentAsset = assetMap[dto.assetId] else { continue }
            if let existing = measMap[dto.id] {
                applyMeasurementDTO(dto, to: existing)
                existing.asset = parentAsset
            } else {
                let newMeas = MeasurementLog(
                    id: dto.id,
                    domain: MeasurementDomain(rawValue: dto.domainRawValue) ?? .customMetric,
                    metricName: dto.metricName,
                    value: dto.value,
                    secondaryValue: dto.secondaryValue,
                    unit: dto.unit,
                    recordedAt: dto.recordedAt,
                    previousValue: dto.previousValue,
                    unitPrice: dto.unitPrice,
                    isSelfRead: dto.isSelfRead,
                    referenceMin: dto.referenceMin,
                    referenceMax: dto.referenceMax,
                    labOrProviderName: dto.labOrProviderName,
                    notes: dto.notes
                )
                newMeas.asset = parentAsset
                context.insert(newMeas)
                measMap[newMeas.id] = newMeas
                measurementsImportedCount += 1
            }
        }
        
        // Process Attachments & Vault Ingestion
        for meta in incomingAttachmentsMeta {
            let vaultData = entryMap[meta.vaultRelativePath] ?? Data()
            if let existing = attMap[meta.id] {
                existing.fileName = meta.fileName
                existing.fileExtension = meta.fileExtension
                if !vaultData.isEmpty {
                    existing.fileData = vaultData
                }
                existing.extractedText = meta.extractedText
            } else {
                let newAtt = DocumentAttachment(
                    id: meta.id,
                    fileName: meta.fileName,
                    fileExtension: meta.fileExtension,
                    fileData: vaultData.isEmpty ? nil : vaultData,
                    extractedText: meta.extractedText,
                    createdAt: meta.createdAt
                )
                if let assetId = meta.assetId, let asset = assetMap[assetId] {
                    newAtt.asset = asset
                }
                if let eventId = meta.eventId, let event = eventMap[eventId] {
                    newAtt.event = event
                }
                context.insert(newAtt)
                attMap[newAtt.id] = newAtt
                attachmentsImportedCount += 1
            }
        }
        
        try context.save()
        
        return ArchiveImportResult(
            assetsImported: assetsImportedCount,
            assetsUpdated: assetsUpdatedCount,
            eventsImported: eventsImportedCount,
            eventsUpdated: eventsUpdatedCount,
            serviceItemsImported: serviceImportedCount,
            measurementsImported: measurementsImportedCount,
            attachmentsImported: attachmentsImportedCount
        )
    }
    
    // MARK: - Private Entity Mapping Helpers
    
    private func applyAssetDTO(_ dto: AssetDTO, to asset: Asset) {
        asset.name = dto.name
        asset.subtitle = dto.subtitle
        asset.categoryRaw = dto.categoryRaw
        asset.customCategoryName = dto.customCategoryName
        asset.iconName = dto.iconName
        asset.accentColorHex = dto.accentColorHex
        asset.notes = dto.notes
        asset.currentMetricValue = dto.currentMetricValue
        asset.metricUnit = dto.metricUnit
        asset.vin = dto.vin
        asset.licensePlate = dto.licensePlate
        asset.civSeries = dto.civSeries
        asset.make = dto.make
        asset.modelName = dto.modelName
        asset.manufactureYear = dto.manufactureYear
        asset.fuelType = dto.fuelType
        asset.engineSpecs = dto.engineSpecs
        asset.engineDisplacementCc = dto.engineDisplacementCc
        asset.enginePowerKw = dto.enginePowerKw
        asset.address = dto.address
        asset.cadastralNumber = dto.cadastralNumber
        asset.surfaceAreaSqm = dto.surfaceAreaSqm
        asset.constructionYear = dto.constructionYear
        asset.podCode = dto.podCode
        asset.clcCode = dto.clcCode
        asset.waterClientCode = dto.waterClientCode
        asset.meterReadWindowStartDay = dto.meterReadWindowStartDay
        asset.meterReadWindowEndDay = dto.meterReadWindowEndDay
        asset.heatingBoilerModel = dto.heatingBoilerModel
        asset.heatingBoilerSerial = dto.heatingBoilerSerial
        asset.gasMeterSerial = dto.gasMeterSerial
        asset.electricityMeterSerial = dto.electricityMeterSerial
        asset.waterMeterSerial = dto.waterMeterSerial
        asset.heatingBoilerSpecs = dto.heatingBoilerSpecs
        asset.meterSerials = dto.meterSerials
        asset.personName = dto.personName
        asset.birthDate = dto.birthDate
        asset.bloodType = dto.bloodType
        asset.allergies = dto.allergies
        asset.chronicConditions = dto.chronicConditions
        asset.emergencyContact = dto.emergencyContact
        asset.familyDoctorName = dto.familyDoctorName
        asset.familyDoctorPhone = dto.familyDoctorPhone
        asset.emergencyContactName = dto.emergencyContactName
        asset.emergencyContactPhone = dto.emergencyContactPhone
        asset.microchipNumber = dto.microchipNumber
        asset.petPassportNumber = dto.petPassportNumber
        asset.speciesAndBreed = dto.speciesAndBreed
        asset.weightKg = dto.weightKg
        asset.petSpecies = dto.petSpecies
        asset.petBreed = dto.petBreed
        asset.vetContactInfo = dto.vetContactInfo
        asset.veterinarianClinic = dto.veterinarianClinic
        asset.veterinarianPhone = dto.veterinarianPhone
        asset.serialOrImei = dto.serialOrImei
        asset.retailerOrIssuer = dto.retailerOrIssuer
        asset.purchaseOrIssueDate = dto.purchaseOrIssueDate
        asset.purchasePrice = dto.purchasePrice
        asset.warrantyMonths = dto.warrantyMonths
        asset.extendedWarrantyMonths = dto.extendedWarrantyMonths
        asset.providerName = dto.providerName
        asset.billingCycle = dto.billingCycle
        asset.recurringAmount = dto.recurringAmount
        asset.currencyCode = dto.currencyCode
        asset.paymentCardLast4 = dto.paymentCardLast4
        asset.cancellationUrl = dto.cancellationUrl
        asset.contractEndDate = dto.contractEndDate
        asset.primaryContactName = dto.primaryContactName
        asset.primaryContactRole = dto.primaryContactRole
        asset.primaryContactPhone = dto.primaryContactPhone
        asset.primaryContactEmail = dto.primaryContactEmail
        asset.updatedAt = dto.updatedAt
    }
    
    private func mergeDynamicFields(from fieldDTOs: [DynamicFieldDTO], into asset: Asset, context: ModelContext) {
        var existingByKey = Dictionary(uniqueKeysWithValues: asset.dynamicFields.map { ($0.key, $0) })
        for fd in fieldDTOs {
            if let existing = existingByKey[fd.key] {
                existing.label = fd.label
                existing.fieldTypeRaw = fd.fieldTypeRaw
                existing.stringValue = fd.stringValue
                existing.numberValue = fd.numberValue
                existing.dateValue = fd.dateValue
                existing.boolValue = fd.boolValue
            } else {
                let newField = DynamicField(
                    id: fd.id,
                    key: fd.key,
                    label: fd.label,
                    fieldType: DynamicFieldType(rawValue: fd.fieldTypeRaw) ?? .text,
                    stringValue: fd.stringValue,
                    numberValue: fd.numberValue,
                    dateValue: fd.dateValue,
                    boolValue: fd.boolValue,
                    asset: asset
                )
                context.insert(newField)
                existingByKey[newField.key] = newField
            }
        }
    }
    
    private func applyEventDTO(_ dto: LifecycleEventDTO, to event: LifecycleEvent) {
        event.title = dto.title
        event.eventDescription = dto.eventDescription
        event.dueDate = dto.dueDate
        event.completedDate = dto.completedDate
        event.isCompleted = dto.isCompleted
        event.cost = dto.cost
        event.currency = dto.currency
        event.provider = dto.provider
        event.policyOrContractNumber = dto.policyOrContractNumber
        event.coverageType = dto.coverageType
        event.bonusMalusClass = dto.bonusMalusClass
        event.mileageAtEvent = dto.mileageAtEvent
        event.serviceLocation = dto.serviceLocation
        event.insuredCoverageAmount = dto.insuredCoverageAmount
        event.franchiseAmount = dto.franchiseAmount
        event.startDate = dto.startDate
        event.isAutoRenew = dto.isAutoRenew
        event.calendarEventIdentifier = dto.calendarEventIdentifier
        event.reminderItemIdentifier = dto.reminderItemIdentifier
        event.cadenceDays = dto.cadenceDays
        event.cadenceMetricInterval = dto.cadenceMetricInterval
        event.metricTriggerValue = dto.metricTriggerValue
        event.reminderOffsetDays = dto.reminderOffsetDays
    }
    
    private func applyServiceDTO(_ dto: ServiceItemDTO, to s: ServiceItem) {
        s.name = dto.name
        s.category = dto.category
        s.partBrandOrCode = dto.partBrandOrCode
        s.partSerialNumber = dto.partSerialNumber
        s.cost = dto.cost
        s.laborCost = dto.laborCost
        s.partsCost = dto.partsCost
        s.serviceDate = dto.serviceDate
        s.mileageAtService = dto.mileageAtService
        s.specialistOrDoctorName = dto.specialistOrDoctorName
        s.serialOrBatchNumber = dto.serialOrBatchNumber
        s.locationOrToothNumber = dto.locationOrToothNumber
        s.daysInService = dto.daysInService
        s.warrantyMonths = dto.warrantyMonths
        s.nextDueDate = dto.nextDueDate
        s.nextDueMileageKm = dto.nextDueMileageKm
        s.shopName = dto.shopName
        s.notes = dto.notes
    }
    
    private func applyMeasurementDTO(_ dto: MeasurementLogDTO, to m: MeasurementLog) {
        m.domainRawValue = dto.domainRawValue
        m.metricName = dto.metricName
        m.value = dto.value
        m.secondaryValue = dto.secondaryValue
        m.unit = dto.unit
        m.recordedAt = dto.recordedAt
        m.previousValue = dto.previousValue
        m.unitPrice = dto.unitPrice
        m.isSelfRead = dto.isSelfRead
        m.referenceMin = dto.referenceMin
        m.referenceMax = dto.referenceMax
        m.labOrProviderName = dto.labOrProviderName
        m.notes = dto.notes
    }
}
