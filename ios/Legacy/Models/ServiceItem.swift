import Foundation
import SwiftData

/// Represents an individual maintenance part, service intervention, medical procedure,
/// veterinary treatment, or warranty RMA claim across any household asset.
@Model
public final class ServiceItem {
    public var id: UUID
    public var name: String
    public var category: String
    public var partBrandOrCode: String?
    public var partSerialNumber: String?
    public var cost: Double?
    public var serviceDate: Date
    public var mileageAtService: Double?
    public var notes: String?
    
    // Universal Household Domain Additions
    public var laborCost: Double?
    public var partsCost: Double?
    public var specialistOrDoctorName: String?  // e.g. "Dr. Popescu", "Mecanic Ion", "Instalator Dan"
    public var serialOrBatchNumber: String?     // Medical implant lot, vaccine batch, RMA ticket
    public var locationOrToothNumber: String?   // e.g. "Dinte #36 FDI", "Punte spate", "Filtru treapta 1"
    public var daysInService: Int?              // RMA warranty extension days per OUG 140/2021
    public var warrantyMonths: Int?
    public var nextDueDate: Date?
    public var nextDueMileageKm: Double?
    public var shopName: String?
    
    public var event: LifecycleEvent?
    public var asset: Asset?
    
    /// Receipts, invoices, or reports linked to this intervention.
    /// Nullify (not cascade): the same document also lives in the asset's vault,
    /// so deleting a service entry must never delete the underlying document.
    @Relationship(deleteRule: .nullify)
    public var attachments: [DocumentAttachment] = []
    
    public var partBrand: String? {
        get { partBrandOrCode }
        set { partBrandOrCode = newValue }
    }
    
    public var totalEffectiveCost: Double {
        if let explicitCost = cost, explicitCost > 0 {
            return explicitCost
        }
        let labor = laborCost ?? 0.0
        let parts = partsCost ?? 0.0
        return labor + parts
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        category: String = "General",
        partBrand: String? = nil,
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
        self.name = name
        self.category = category
        self.partBrandOrCode = partBrand
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
