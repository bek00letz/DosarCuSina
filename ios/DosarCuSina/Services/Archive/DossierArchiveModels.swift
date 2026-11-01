import Foundation

// MARK: - Manifest Schema Version 2

/// Authoritative manifest specification for `.dosar` archives (Schema Version 2).
/// Includes full SHA-256 integrity map, entity counts, device metadata, and export timestamp.
public struct DossierManifestV2: Codable, Sendable {
    public let schemaVersion: Int              // 2
    public let appVersion: String             // "2.0.0"
    public let appName: String                // "Dosar cu Șină"
    public let exportDate: Date               // ISO 8601 UTC
    public let platform: String               // "iOS" or "Android"
    public let deviceId: String
    public let format: String                 // "com.ar.dosarcusina.dossier"
    public let entityCounts: EntityCounts
    public let checksums: [String: String]     // "data/assets.json": "sha256..."
    
    public struct EntityCounts: Codable, Sendable {
        public let assets: Int
        public let events: Int
        public let serviceItems: Int
        public let measurements: Int
        public let dynamicFields: Int
        public let attachments: Int
        
        public init(
            assets: Int,
            events: Int,
            serviceItems: Int,
            measurements: Int,
            dynamicFields: Int,
            attachments: Int
        ) {
            self.assets = assets
            self.events = events
            self.serviceItems = serviceItems
            self.measurements = measurements
            self.dynamicFields = dynamicFields
            self.attachments = attachments
        }
    }
    
    public init(
        schemaVersion: Int = 2,
        appVersion: String = "2.0.0",
        appName: String = "Dosar cu Șină",
        exportDate: Date = Date(),
        platform: String = "iOS",
        deviceId: String = UUID().uuidString,
        format: String = "com.ar.dosarcusina.dossier",
        entityCounts: EntityCounts,
        checksums: [String: String]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.appName = appName
        self.exportDate = exportDate
        self.platform = platform
        self.deviceId = deviceId
        self.format = format
        self.entityCounts = entityCounts
        self.checksums = checksums
    }
}

// MARK: - Data Transfer Objects (DTOs)

public struct DynamicFieldDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let key: String
    public let label: String
    public let fieldTypeRaw: String
    public let stringValue: String?
    public let numberValue: Double?
    public let dateValue: Date?
    public let boolValue: Bool?
    
    public init(
        id: UUID = UUID(),
        key: String,
        label: String,
        fieldTypeRaw: String,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        dateValue: Date? = nil,
        boolValue: Bool? = nil
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.fieldTypeRaw = fieldTypeRaw
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.dateValue = dateValue
        self.boolValue = boolValue
    }
}

public struct AssetDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let subtitle: String?
    public let categoryRaw: String
    public let customCategoryName: String?
    public let iconName: String
    public let accentColorHex: String
    public let notes: String?
    public let currentMetricValue: Double?
    public let metricUnit: String?
    
    // Vehicles
    public let vin: String?
    public let licensePlate: String?
    public let civSeries: String?
    public let make: String?
    public let modelName: String?
    public let manufactureYear: Int?
    public let fuelType: String?
    public let engineSpecs: String?
    public let engineDisplacementCc: Int?
    public let enginePowerKw: Int?
    
    // Home & Utilities
    public let address: String?
    public let cadastralNumber: String?
    public let surfaceAreaSqm: Double?
    public let constructionYear: Int?
    public let podCode: String?
    public let clcCode: String?
    public let waterClientCode: String?
    public let meterReadWindowStartDay: Int?
    public let meterReadWindowEndDay: Int?
    public let heatingBoilerModel: String?
    public let heatingBoilerSerial: String?
    public let gasMeterSerial: String?
    public let electricityMeterSerial: String?
    public let waterMeterSerial: String?
    public let heatingBoilerSpecs: String?
    public let meterSerials: String?
    
    // Health & Family
    public let personName: String?
    public let birthDate: Date?
    public let bloodType: String?
    public let allergies: String?
    public let chronicConditions: String?
    public let emergencyContact: String?
    public let familyDoctorName: String?
    public let familyDoctorPhone: String?
    public let emergencyContactName: String?
    public let emergencyContactPhone: String?
    
    // Pets & Vet
    public let microchipNumber: String?
    public let petPassportNumber: String?
    public let speciesAndBreed: String?
    public let weightKg: Double?
    public let petSpecies: String?
    public let petBreed: String?
    public let vetContactInfo: String?
    public let veterinarianClinic: String?
    public let veterinarianPhone: String?
    
    // Warranties & Goods
    public let serialOrImei: String?
    public let retailerOrIssuer: String?
    public let purchaseOrIssueDate: Date?
    public let purchasePrice: Double?
    public let warrantyMonths: Int?
    public let extendedWarrantyMonths: Int?
    
    // Subscriptions & Contracts
    public let providerName: String?
    public let billingCycle: String?
    public let recurringAmount: Double?
    public let currencyCode: String
    public let paymentCardLast4: String?
    public let cancellationUrl: String?
    public let contractEndDate: Date?
    
    // Contacts
    public let primaryContactName: String?
    public let primaryContactRole: String?
    public let primaryContactPhone: String?
    public let primaryContactEmail: String?
    
    // Timestamps & Relational Dynamic Fields
    public let createdAt: Date
    public let updatedAt: Date
    public let dynamicFields: [DynamicFieldDTO]
    
    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        categoryRaw: String,
        customCategoryName: String? = nil,
        iconName: String,
        accentColorHex: String,
        notes: String? = nil,
        currentMetricValue: Double? = nil,
        metricUnit: String? = nil,
        vin: String? = nil,
        licensePlate: String? = nil,
        civSeries: String? = nil,
        make: String? = nil,
        modelName: String? = nil,
        manufactureYear: Int? = nil,
        fuelType: String? = nil,
        engineSpecs: String? = nil,
        engineDisplacementCc: Int? = nil,
        enginePowerKw: Int? = nil,
        address: String? = nil,
        cadastralNumber: String? = nil,
        surfaceAreaSqm: Double? = nil,
        constructionYear: Int? = nil,
        podCode: String? = nil,
        clcCode: String? = nil,
        waterClientCode: String? = nil,
        meterReadWindowStartDay: Int? = nil,
        meterReadWindowEndDay: Int? = nil,
        heatingBoilerModel: String? = nil,
        heatingBoilerSerial: String? = nil,
        gasMeterSerial: String? = nil,
        electricityMeterSerial: String? = nil,
        waterMeterSerial: String? = nil,
        heatingBoilerSpecs: String? = nil,
        meterSerials: String? = nil,
        personName: String? = nil,
        birthDate: Date? = nil,
        bloodType: String? = nil,
        allergies: String? = nil,
        chronicConditions: String? = nil,
        emergencyContact: String? = nil,
        familyDoctorName: String? = nil,
        familyDoctorPhone: String? = nil,
        emergencyContactName: String? = nil,
        emergencyContactPhone: String? = nil,
        microchipNumber: String? = nil,
        petPassportNumber: String? = nil,
        speciesAndBreed: String? = nil,
        weightKg: Double? = nil,
        petSpecies: String? = nil,
        petBreed: String? = nil,
        vetContactInfo: String? = nil,
        veterinarianClinic: String? = nil,
        veterinarianPhone: String? = nil,
        serialOrImei: String? = nil,
        retailerOrIssuer: String? = nil,
        purchaseOrIssueDate: Date? = nil,
        purchasePrice: Double? = nil,
        warrantyMonths: Int? = nil,
        extendedWarrantyMonths: Int? = nil,
        providerName: String? = nil,
        billingCycle: String? = nil,
        recurringAmount: Double? = nil,
        currencyCode: String = "RON",
        paymentCardLast4: String? = nil,
        cancellationUrl: String? = nil,
        contractEndDate: Date? = nil,
        primaryContactName: String? = nil,
        primaryContactRole: String? = nil,
        primaryContactPhone: String? = nil,
        primaryContactEmail: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dynamicFields: [DynamicFieldDTO] = []
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.categoryRaw = categoryRaw
        self.customCategoryName = customCategoryName
        self.iconName = iconName
        self.accentColorHex = accentColorHex
        self.notes = notes
        self.currentMetricValue = currentMetricValue
        self.metricUnit = metricUnit
        self.vin = vin
        self.licensePlate = licensePlate
        self.civSeries = civSeries
        self.make = make
        self.modelName = modelName
        self.manufactureYear = manufactureYear
        self.fuelType = fuelType
        self.engineSpecs = engineSpecs
        self.engineDisplacementCc = engineDisplacementCc
        self.enginePowerKw = enginePowerKw
        self.address = address
        self.cadastralNumber = cadastralNumber
        self.surfaceAreaSqm = surfaceAreaSqm
        self.constructionYear = constructionYear
        self.podCode = podCode
        self.clcCode = clcCode
        self.waterClientCode = waterClientCode
        self.meterReadWindowStartDay = meterReadWindowStartDay
        self.meterReadWindowEndDay = meterReadWindowEndDay
        self.heatingBoilerModel = heatingBoilerModel
        self.heatingBoilerSerial = heatingBoilerSerial
        self.gasMeterSerial = gasMeterSerial
        self.electricityMeterSerial = electricityMeterSerial
        self.waterMeterSerial = waterMeterSerial
        self.heatingBoilerSpecs = heatingBoilerSpecs
        self.meterSerials = meterSerials
        self.personName = personName
        self.birthDate = birthDate
        self.bloodType = bloodType
        self.allergies = allergies
        self.chronicConditions = chronicConditions
        self.emergencyContact = emergencyContact
        self.familyDoctorName = familyDoctorName
        self.familyDoctorPhone = familyDoctorPhone
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.microchipNumber = microchipNumber
        self.petPassportNumber = petPassportNumber
        self.speciesAndBreed = speciesAndBreed
        self.weightKg = weightKg
        self.petSpecies = petSpecies
        self.petBreed = petBreed
        self.vetContactInfo = vetContactInfo
        self.veterinarianClinic = veterinarianClinic
        self.veterinarianPhone = veterinarianPhone
        self.serialOrImei = serialOrImei
        self.retailerOrIssuer = retailerOrIssuer
        self.purchaseOrIssueDate = purchaseOrIssueDate
        self.purchasePrice = purchasePrice
        self.warrantyMonths = warrantyMonths
        self.extendedWarrantyMonths = extendedWarrantyMonths
        self.providerName = providerName
        self.billingCycle = billingCycle
        self.recurringAmount = recurringAmount
        self.currencyCode = currencyCode
        self.paymentCardLast4 = paymentCardLast4
        self.cancellationUrl = cancellationUrl
        self.contractEndDate = contractEndDate
        self.primaryContactName = primaryContactName
        self.primaryContactRole = primaryContactRole
        self.primaryContactPhone = primaryContactPhone
        self.primaryContactEmail = primaryContactEmail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dynamicFields = dynamicFields
    }
}

public struct LifecycleEventDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let assetId: UUID
    public let title: String
    public let eventDescription: String?
    public let dueDate: Date
    public let completedDate: Date?
    public let isCompleted: Bool
    public let cost: Double?
    public let currency: String
    public let provider: String?
    public let policyOrContractNumber: String?
    public let coverageType: String?
    public let bonusMalusClass: String?
    public let mileageAtEvent: Double?
    public let serviceLocation: String?
    public let insuredCoverageAmount: Double?
    public let franchiseAmount: Double?
    public let startDate: Date?
    public let isAutoRenew: Bool
    public let calendarEventIdentifier: String?
    public let reminderItemIdentifier: String?
    public let cadenceDays: Int?
    public let cadenceMetricInterval: Double?
    public let metricTriggerValue: Double?
    public let reminderOffsetDays: [Int]
    public let createdAt: Date
    public let attachmentIds: [UUID]
    
    public init(
        id: UUID = UUID(),
        assetId: UUID,
        title: String,
        eventDescription: String? = nil,
        dueDate: Date,
        completedDate: Date? = nil,
        isCompleted: Bool = false,
        cost: Double? = nil,
        currency: String = "RON",
        provider: String? = nil,
        policyOrContractNumber: String? = nil,
        coverageType: String? = nil,
        bonusMalusClass: String? = nil,
        mileageAtEvent: Double? = nil,
        serviceLocation: String? = nil,
        insuredCoverageAmount: Double? = nil,
        franchiseAmount: Double? = nil,
        startDate: Date? = nil,
        isAutoRenew: Bool = false,
        calendarEventIdentifier: String? = nil,
        reminderItemIdentifier: String? = nil,
        cadenceDays: Int? = nil,
        cadenceMetricInterval: Double? = nil,
        metricTriggerValue: Double? = nil,
        reminderOffsetDays: [Int] = [7, 1],
        createdAt: Date = Date(),
        attachmentIds: [UUID] = []
    ) {
        self.id = id
        self.assetId = assetId
        self.title = title
        self.eventDescription = eventDescription
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.isCompleted = isCompleted
        self.cost = cost
        self.currency = currency
        self.provider = provider
        self.policyOrContractNumber = policyOrContractNumber
        self.coverageType = coverageType
        self.bonusMalusClass = bonusMalusClass
        self.mileageAtEvent = mileageAtEvent
        self.serviceLocation = serviceLocation
        self.insuredCoverageAmount = insuredCoverageAmount
        self.franchiseAmount = franchiseAmount
        self.startDate = startDate
        self.isAutoRenew = isAutoRenew
        self.calendarEventIdentifier = calendarEventIdentifier
        self.reminderItemIdentifier = reminderItemIdentifier
        self.cadenceDays = cadenceDays
        self.cadenceMetricInterval = cadenceMetricInterval
        self.metricTriggerValue = metricTriggerValue
        self.reminderOffsetDays = reminderOffsetDays
        self.createdAt = createdAt
        self.attachmentIds = attachmentIds
    }
}

public struct ServiceItemDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let assetId: UUID
    public let eventId: UUID?
    public let name: String
    public let category: String
    public let partBrandOrCode: String?
    public let partSerialNumber: String?
    public let cost: Double?
    public let laborCost: Double?
    public let partsCost: Double?
    public let serviceDate: Date
    public let mileageAtService: Double?
    public let specialistOrDoctorName: String?
    public let serialOrBatchNumber: String?
    public let locationOrToothNumber: String?
    public let daysInService: Int?
    public let warrantyMonths: Int?
    public let nextDueDate: Date?
    public let nextDueMileageKm: Double?
    public let shopName: String?
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        assetId: UUID,
        eventId: UUID? = nil,
        name: String,
        category: String = "General",
        partBrandOrCode: String? = nil,
        partSerialNumber: String? = nil,
        cost: Double? = nil,
        laborCost: Double? = nil,
        partsCost: Double? = nil,
        serviceDate: Date = Date(),
        mileageAtService: Double? = nil,
        specialistOrDoctorName: String? = nil,
        serialOrBatchNumber: String? = nil,
        locationOrToothNumber: String? = nil,
        daysInService: Int? = nil,
        warrantyMonths: Int? = nil,
        nextDueDate: Date? = nil,
        nextDueMileageKm: Double? = nil,
        shopName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.assetId = assetId
        self.eventId = eventId
        self.name = name
        self.category = category
        self.partBrandOrCode = partBrandOrCode
        self.partSerialNumber = partSerialNumber
        self.cost = cost
        self.laborCost = laborCost
        self.partsCost = partsCost
        self.serviceDate = serviceDate
        self.mileageAtService = mileageAtService
        self.specialistOrDoctorName = specialistOrDoctorName
        self.serialOrBatchNumber = serialOrBatchNumber
        self.locationOrToothNumber = locationOrToothNumber
        self.daysInService = daysInService
        self.warrantyMonths = warrantyMonths
        self.nextDueDate = nextDueDate
        self.nextDueMileageKm = nextDueMileageKm
        self.shopName = shopName
        self.notes = notes
    }
}

public struct MeasurementLogDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let assetId: UUID
    public let domainRawValue: String
    public let metricName: String
    public let value: Double
    public let secondaryValue: Double?
    public let unit: String
    public let recordedAt: Date
    public let previousValue: Double?
    public let unitPrice: Double?
    public let isSelfRead: Bool
    public let referenceMin: Double?
    public let referenceMax: Double?
    public let labOrProviderName: String?
    public let notes: String?
    public let attachmentIds: [UUID]
    
    public init(
        id: UUID = UUID(),
        assetId: UUID,
        domainRawValue: String,
        metricName: String,
        value: Double,
        secondaryValue: Double? = nil,
        unit: String,
        recordedAt: Date = Date(),
        previousValue: Double? = nil,
        unitPrice: Double? = nil,
        isSelfRead: Bool = true,
        referenceMin: Double? = nil,
        referenceMax: Double? = nil,
        labOrProviderName: String? = nil,
        notes: String? = nil,
        attachmentIds: [UUID] = []
    ) {
        self.id = id
        self.assetId = assetId
        self.domainRawValue = domainRawValue
        self.metricName = metricName
        self.value = value
        self.secondaryValue = secondaryValue
        self.unit = unit
        self.recordedAt = recordedAt
        self.previousValue = previousValue
        self.unitPrice = unitPrice
        self.isSelfRead = isSelfRead
        self.referenceMin = referenceMin
        self.referenceMax = referenceMax
        self.labOrProviderName = labOrProviderName
        self.notes = notes
        self.attachmentIds = attachmentIds
    }
}

public struct AttachmentMetadataDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let assetId: UUID?
    public let eventId: UUID?
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let extractedText: String?
    public let createdAt: Date
    public let vaultRelativePath: String // "vault/<uuid>.<ext>"
    public let sha256: String
    
    public init(
        id: UUID = UUID(),
        assetId: UUID? = nil,
        eventId: UUID? = nil,
        fileName: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        extractedText: String? = nil,
        createdAt: Date = Date(),
        vaultRelativePath: String,
        sha256: String
    ) {
        self.id = id
        self.assetId = assetId
        self.eventId = eventId
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSizeBytes = fileSizeBytes
        self.extractedText = extractedText
        self.createdAt = createdAt
        self.vaultRelativePath = vaultRelativePath
        self.sha256 = sha256
    }
}

// MARK: - JSON Coder Factory

public extension JSONEncoder {
    static func dosarArchiveEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static func dosarArchiveDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
