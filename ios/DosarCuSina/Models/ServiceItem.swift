import Foundation
import SwiftData

/// Represents an individual maintenance part or service item replaced/performed during an event.
/// Enables granular cross-referencing (e.g., brake pads, engine oil, filters) across history.
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
    
    public var event: LifecycleEvent?
    public var asset: Asset?
    
    public var partBrand: String? {
        get { partBrandOrCode }
        set { partBrandOrCode = newValue }
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        category: String = "General",
        partBrand: String? = nil,
        partSerialNumber: String? = nil,
        cost: Double? = nil,
        serviceDate: Date = Date(),
        mileageAtService: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.partBrandOrCode = partBrand
        self.partSerialNumber = partSerialNumber
        self.cost = cost
        self.serviceDate = serviceDate
        self.mileageAtService = mileageAtService
        self.notes = notes
    }
}
