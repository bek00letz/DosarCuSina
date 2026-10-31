import Foundation
import SwiftData
import SwiftUI

@Model
public final class Asset {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var categoryRaw: String
    public var iconName: String
    public var accentColorHex: String
    
    // Telemetry (for vehicles, bikes, boats, equipment)
    public var currentMetricValue: Double?
    public var metricUnit: String?
    
    // Tailored Domain Fields: Vehicles
    public var vin: String?
    public var licensePlate: String?
    public var manufactureYear: Int?
    public var fuelType: String?
    public var engineSpecs: String?
    public var engineDisplacementCm3: Int?
    public var enginePowerHp: Int?
    public var vinNumber: String? {
        get { vin }
        set { vin = newValue }
    }
    
    // Tailored Domain Fields: Home & Real Estate
    public var fullAddress: String?
    public var surfaceAreaSqMeters: Double?
    public var heatingBoilerSpecs: String?
    public var meterSerials: String?
    public var constructionYear: Int?
    public var heatingBoilerModel: String?
    public var heatingBoilerSerial: String?
    public var gasMeterSerial: String?
    public var electricityMeterSerial: String?
    public var waterMeterSerial: String?
    public var surfaceAreaM2: Double? {
        get { surfaceAreaSqMeters }
        set { surfaceAreaSqMeters = newValue }
    }
    
    // Tailored Domain Fields: Pets
    public var petSpecies: String?
    public var petBreed: String?
    public var microchipNumber: String?
    public var petBirthDate: Date?
    public var vetContactInfo: String?
    public var petMicrochipNumber: String? {
        get { microchipNumber }
        set { microchipNumber = newValue }
    }
    public var veterinarianClinic: String?
    public var veterinarianPhone: String?
    
    // Tailored Domain Fields: Personal Health
    public var personName: String?
    public var bloodType: String?
    public var emergencyContact: String?
    public var familyDoctorName: String?
    public var familyDoctorPhone: String?
    public var emergencyContactName: String?
    public var emergencyContactPhone: String?
    public var allergiesNotes: String?
    
    public var createdAt: Date
    public var updatedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \LifecycleEvent.asset)
    public var events: [LifecycleEvent] = []
    
    @Relationship(deleteRule: .cascade, inverse: \DocumentAttachment.asset)
    public var attachments: [DocumentAttachment] = []
    
    @Relationship(deleteRule: .cascade)
    public var dynamicFields: [DynamicField] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ServiceItem.asset)
    public var serviceItems: [ServiceItem] = []
    
    public var category: AssetCategory {
        get { AssetCategory(rawValue: categoryRaw) ?? .custom }
        set { categoryRaw = newValue.rawValue }
    }
    
    public var accentColor: Color {
        Color(hex: accentColorHex) ?? category.defaultColor
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        category: AssetCategory = .home,
        iconName: String? = nil,
        accentColorHex: String? = nil,
        currentMetricValue: Double? = nil,
        metricUnit: String? = nil,
        vin: String? = nil,
        licensePlate: String? = nil,
        manufactureYear: Int? = nil,
        fuelType: String? = nil,
        engineSpecs: String? = nil,
        fullAddress: String? = nil,
        surfaceAreaSqMeters: Double? = nil,
        heatingBoilerSpecs: String? = nil,
        meterSerials: String? = nil,
        petSpecies: String? = nil,
        petBreed: String? = nil,
        microchipNumber: String? = nil,
        petBirthDate: Date? = nil,
        vetContactInfo: String? = nil,
        personName: String? = nil,
        bloodType: String? = nil,
        emergencyContact: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.categoryRaw = category.rawValue
        self.iconName = iconName ?? category.systemIcon
        self.accentColorHex = accentColorHex ?? "007AFF"
        self.currentMetricValue = currentMetricValue
        self.metricUnit = metricUnit
        self.vin = vin
        self.licensePlate = licensePlate
        self.manufactureYear = manufactureYear
        self.fuelType = fuelType
        self.engineSpecs = engineSpecs
        self.fullAddress = fullAddress
        self.surfaceAreaSqMeters = surfaceAreaSqMeters
        self.heatingBoilerSpecs = heatingBoilerSpecs
        self.meterSerials = meterSerials
        self.petSpecies = petSpecies
        self.petBreed = petBreed
        self.microchipNumber = microchipNumber
        self.petBirthDate = petBirthDate
        self.vetContactInfo = vetContactInfo
        self.personName = personName
        self.bloodType = bloodType
        self.emergencyContact = emergencyContact
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
