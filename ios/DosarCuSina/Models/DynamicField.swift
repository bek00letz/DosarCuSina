import Foundation
import SwiftData

public enum DynamicFieldType: String, Codable, CaseIterable, Sendable {
    case text
    case number
    case date
    case boolean
    case currency
}

@Model
public final class DynamicField {
    public var id: UUID
    public var key: String
    public var label: String
    public var fieldTypeRaw: String
    
    public var stringValue: String?
    public var numberValue: Double?
    public var dateValue: Date?
    public var boolValue: Bool?
    
    public var fieldType: DynamicFieldType {
        get { DynamicFieldType(rawValue: fieldTypeRaw) ?? .text }
        set { fieldTypeRaw = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        key: String,
        label: String,
        fieldType: DynamicFieldType = .text,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        dateValue: Date? = nil,
        boolValue: Bool? = nil
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.fieldTypeRaw = fieldType.rawValue
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.dateValue = dateValue
        self.boolValue = boolValue
    }
}
