import Foundation
import SwiftData

/// Domain of a quantitative measurement reading.
public enum MeasurementDomain: String, Codable, CaseIterable, Sendable {
    case electricityMeter = "Index Energie Electrică (kWh)"
    case gasMeter         = "Index Gaze Naturale (m³)"
    case coldWaterMeter   = "Index Apă Rece (m³)"
    case hotWaterMeter    = "Index Apă Caldă (m³)"
    case thermalEnergy    = "Energie Termică (Gcal)"
    case healthBiomarker  = "Analiză Medicală / Biomarker"
    case bloodPressure    = "Tensiune Arterială (mmHg)"
    case bodyWeight       = "Greutate Corporală (kg)"
    case diopters         = "Dioptrii Oftalmologice (OD/OS)"
    case odometer         = "Kilometraj (km)"
    case customMetric     = "Parametru Personalizat"
    
    public var defaultUnit: String {
        switch self {
        case .electricityMeter: return "kWh"
        case .gasMeter, .coldWaterMeter, .hotWaterMeter: return "m³"
        case .thermalEnergy: return "Gcal"
        case .healthBiomarker: return "mg/dL"
        case .bloodPressure: return "mmHg"
        case .bodyWeight: return "kg"
        case .diopters: return "dpt"
        case .odometer: return "km"
        case .customMetric: return "unități"
        }
    }
}

/// Persistent SwiftData model representing quantitative time-series telemetry:
/// utility meter readings, health biomarkers, vitals, pet weights, or odometer snapshots.
@Model
public final class MeasurementLog {
    public var id: UUID
    public var domainRawValue: String
    public var metricName: String               // e.g. "Index Contor Zi", "Glicemie", "Colesterol LDL", "Greutate"
    public var value: Double                    // Current index or biomarker reading
    public var secondaryValue: Double?          // e.g. Diastolic BP (80 in 120/80) or OS diopter
    public var unit: String                     // "kWh", "m³", "mg/dL", "kg", "km"
    public var recordedAt: Date
    
    // Utility Meter Specifics
    public var previousValue: Double?           // Auto-populated or reference prior reading
    public var unitPrice: Double?               // Price per kWh / m³ for cost calculation (RON)
    public var isSelfRead: Bool                 // Autocitit vs. Estimat / Regularizare
    
    // Health Biomarker Specifics
    public var referenceMin: Double?            // Lab normal range min (e.g. 70 mg/dL)
    public var referenceMax: Double?            // Lab normal range max (e.g. 99 mg/dL)
    public var labOrProviderName: String?       // e.g. Synevo, Regina Maria, Hidroelectrica
    public var notes: String?

    public var asset: Asset?

    @Relationship(deleteRule: .cascade)
    public var attachments: [DocumentAttachment] = []

    public var domain: MeasurementDomain {
        get { MeasurementDomain(rawValue: domainRawValue) ?? .customMetric }
        set { domainRawValue = newValue.rawValue }
    }
    
    // Computed Differential Properties
    public var deltaFromPrevious: Double? {
        guard let prev = previousValue else { return nil }
        return value - prev
    }
    
    public var estimatedCost: Double? {
        guard let delta = deltaFromPrevious, let price = unitPrice, delta > 0 else { return nil }
        return delta * price
    }
    
    public var isOutOfRange: Bool {
        if let min = referenceMin, value < min { return true }
        if let max = referenceMax, value > max { return true }
        return false
    }
    
    public init(
        id: UUID = UUID(),
        domain: MeasurementDomain = .electricityMeter,
        metricName: String,
        value: Double,
        secondaryValue: Double? = nil,
        unit: String? = nil,
        recordedAt: Date = Date(),
        previousValue: Double? = nil,
        unitPrice: Double? = nil,
        isSelfRead: Bool = true,
        referenceMin: Double? = nil,
        referenceMax: Double? = nil,
        labOrProviderName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.domainRawValue = domain.rawValue
        self.metricName = metricName
        self.value = value
        self.secondaryValue = secondaryValue
        self.unit = unit ?? domain.defaultUnit
        self.recordedAt = recordedAt
        self.previousValue = previousValue
        self.unitPrice = unitPrice
        self.isSelfRead = isSelfRead
        self.referenceMin = referenceMin
        self.referenceMax = referenceMax
        self.labOrProviderName = labOrProviderName
        self.notes = notes
    }
}
