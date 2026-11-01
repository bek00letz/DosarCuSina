import Foundation
import SwiftData
import SwiftUI

@Model
public final class Asset {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var categoryRaw: String
    public var customCategoryName: String?
    public var iconName: String
    public var accentColorHex: String
    public var notes: String?
    
    // Telemetry (for vehicles, bikes, boats, equipment)
    public var currentMetricValue: Double?
    public var metricUnit: String?
    
    // Tailored Domain Fields: Vehicles & Mobility
    public var vin: String?
    public var licensePlate: String?
    public var civSeries: String?
    public var make: String?
    public var modelName: String?
    public var manufactureYear: Int?
    public var fuelType: String?
    public var engineSpecs: String?
    public var engineDisplacementCc: Int?
    public var enginePowerKw: Int?
    
    public var vinNumber: String? {
        get { vin }
        set { vin = newValue }
    }
    public var engineDisplacementCm3: Int? {
        get { engineDisplacementCc }
        set { engineDisplacementCc = newValue }
    }
    public var enginePowerHp: Int? {
        get { enginePowerKw }
        set { enginePowerKw = newValue }
    }
    public var currentMileageKm: Int? {
        get { currentMetricValue.map { Int($0) } }
        set { currentMetricValue = newValue.map { Double($0) } }
    }
    
    // Tailored Domain Fields: Home, Property & Utilities
    public var address: String?
    public var cadastralNumber: String?
    public var surfaceAreaSqm: Double?
    public var constructionYear: Int?
    public var podCode: String?
    public var clcCode: String?
    public var waterClientCode: String?
    public var meterReadWindowStartDay: Int?
    public var meterReadWindowEndDay: Int?
    public var heatingBoilerModel: String?
    public var heatingBoilerSerial: String?
    public var gasMeterSerial: String?
    public var electricityMeterSerial: String?
    public var waterMeterSerial: String?
    public var heatingBoilerSpecs: String?
    public var meterSerials: String?
    
    public var fullAddress: String? {
        get { address }
        set { address = newValue }
    }
    public var surfaceAreaSqMeters: Double? {
        get { surfaceAreaSqm }
        set { surfaceAreaSqm = newValue }
    }
    public var surfaceAreaM2: Double? {
        get { surfaceAreaSqm }
        set { surfaceAreaSqm = newValue }
    }
    
    // Tailored Domain Fields: Personal Health & Family
    public var personName: String?
    public var birthDate: Date?
    public var bloodType: String?
    public var allergies: String?
    public var chronicConditions: String?
    public var emergencyContact: String?
    public var familyDoctorName: String?
    public var familyDoctorPhone: String?
    public var emergencyContactName: String?
    public var emergencyContactPhone: String?
    
    public var allergiesNotes: String? {
        get { allergies }
        set { allergies = newValue }
    }
    
    // Tailored Domain Fields: Pets & Veterinary
    public var microchipNumber: String?
    public var petPassportNumber: String?
    public var speciesAndBreed: String?
    public var weightKg: Double?
    public var petSpecies: String?
    public var petBreed: String?
    public var vetContactInfo: String?
    public var veterinarianClinic: String?
    public var veterinarianPhone: String?
    
    public var petBirthDate: Date? {
        get { birthDate }
        set { birthDate = newValue }
    }
    public var petMicrochipNumber: String? {
        get { microchipNumber }
        set { microchipNumber = newValue }
    }
    
    // Tailored Domain Fields: Warranties, Appliances & Identity Documents
    public var serialOrImei: String?
    public var retailerOrIssuer: String?
    public var purchaseOrIssueDate: Date?
    public var purchasePrice: Double?
    public var warrantyMonths: Int?
    public var extendedWarrantyMonths: Int?
    
    // Tailored Domain Fields: Subscriptions & Contracts
    public var providerName: String?
    public var billingCycle: String?
    public var recurringAmount: Double?
    public var currencyCode: String = "RON"
    public var paymentCardLast4: String?
    public var cancellationUrl: String?
    public var contractEndDate: Date?
    
    // Associated Contact
    public var primaryContactName: String?
    public var primaryContactRole: String?
    public var primaryContactPhone: String?
    public var primaryContactEmail: String?
    
    public var createdAt: Date
    public var updatedAt: Date
    
    // Universal Relationships
    @Relationship(deleteRule: .cascade, inverse: \LifecycleEvent.asset)
    public var events: [LifecycleEvent] = []
    
    @Relationship(deleteRule: .cascade, inverse: \DynamicField.asset)
    public var dynamicFields: [DynamicField] = []
    
    @Relationship(deleteRule: .cascade, inverse: \DocumentAttachment.asset)
    public var attachments: [DocumentAttachment] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ServiceItem.asset)
    public var serviceItems: [ServiceItem] = []
    
    @Relationship(deleteRule: .cascade, inverse: \MeasurementLog.asset)
    public var measurements: [MeasurementLog] = []
    
    public var category: AssetCategory {
        get { AssetCategory(rawValue: categoryRaw) ?? .custom }
        set { categoryRaw = newValue.rawValue }
    }
    
    public var categoryRawValue: String {
        get { categoryRaw }
        set { categoryRaw = newValue }
    }
    
    public var accentColor: Color {
        Color(hex: accentColorHex) ?? category.defaultColor
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        category: AssetCategory = .home,
        customCategoryName: String? = nil,
        iconName: String? = nil,
        accentColorHex: String? = nil,
        currentMetricValue: Double? = nil,
        metricUnit: String? = nil,
        notes: String? = nil,
        // Vehicle
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
        // Home
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
        // Health
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
        // Pets
        microchipNumber: String? = nil,
        petPassportNumber: String? = nil,
        speciesAndBreed: String? = nil,
        weightKg: Double? = nil,
        petSpecies: String? = nil,
        petBreed: String? = nil,
        vetContactInfo: String? = nil,
        veterinarianClinic: String? = nil,
        veterinarianPhone: String? = nil,
        // Warranties / Goods / Docs
        serialOrImei: String? = nil,
        retailerOrIssuer: String? = nil,
        purchaseOrIssueDate: Date? = nil,
        purchasePrice: Double? = nil,
        warrantyMonths: Int? = nil,
        extendedWarrantyMonths: Int? = nil,
        // Subscriptions
        providerName: String? = nil,
        billingCycle: String? = nil,
        recurringAmount: Double? = nil,
        currencyCode: String = "RON",
        paymentCardLast4: String? = nil,
        cancellationUrl: String? = nil,
        contractEndDate: Date? = nil,
        // Contacts
        primaryContactName: String? = nil,
        primaryContactRole: String? = nil,
        primaryContactPhone: String? = nil,
        primaryContactEmail: String? = nil,
        // Legacy parameter compatibility
        fullAddress: String? = nil,
        surfaceAreaSqMeters: Double? = nil,
        petBirthDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.categoryRaw = category.rawValue
        self.customCategoryName = customCategoryName
        self.iconName = iconName ?? category.systemIcon
        self.accentColorHex = accentColorHex ?? "007AFF"
        self.currentMetricValue = currentMetricValue
        self.metricUnit = metricUnit
        self.notes = notes
        
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
        
        self.address = address ?? fullAddress
        self.cadastralNumber = cadastralNumber
        self.surfaceAreaSqm = surfaceAreaSqm ?? surfaceAreaSqMeters
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
        self.birthDate = birthDate ?? petBirthDate
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
        self.speciesAndBreed = speciesAndBreed ?? (petSpecies != nil ? (petBreed != nil ? "\(petSpecies!) — \(petBreed!)" : petSpecies) : nil)
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
    }
    
    // MARK: - Helper Metrics
    
    public var pendingEventsCount: Int {
        events.filter { !$0.isCompleted }.count
    }
    
    public var urgentEventsCount: Int {
        events.filter { $0.isUrgent || $0.isOverdue }.count
    }
    
    public var nextUpcomingEvent: LifecycleEvent? {
        events
            .filter { !$0.isCompleted }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }
    
    public var totalCostThisYear: Double {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        return events
            .filter {
                guard let cost = $0.cost, cost > 0 else { return false }
                let eventYear = calendar.component(.year, from: $0.dueDate)
                return eventYear == currentYear
            }
            .compactMap { $0.cost }
            .reduce(0, +)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}
