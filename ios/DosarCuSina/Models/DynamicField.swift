import Foundation
import SwiftData

public enum DynamicFieldType: String, Codable, CaseIterable, Sendable {
    case text
    case number
    case currency
    case date
    case boolean
    case singleSelect
    case multiSelect
    case url
    case phone
    case longText
    
    public var displayTitle: String {
        switch self {
        case .text: return "Text"
        case .number: return "Număr"
        case .currency: return "Monetară"
        case .date: return "Dată"
        case .boolean: return "Comutator"
        case .singleSelect: return "Selecție Unică"
        case .multiSelect: return "Selecție Multiplă"
        case .url: return "Link Web / URL"
        case .phone: return "Număr Telefon"
        case .longText: return "Text Extins"
        }
    }
    
    public var iconName: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .currency: return "banknote"
        case .date: return "calendar"
        case .boolean: return "switch.2"
        case .singleSelect: return "checkmark.circle"
        case .multiSelect: return "checklist"
        case .url: return "link"
        case .phone: return "phone"
        case .longText: return "text.alignleft"
        }
    }
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
    public var asset: Asset?
    
    public var fieldType: DynamicFieldType {
        get { DynamicFieldType(rawValue: fieldTypeRaw) ?? .text }
        set { fieldTypeRaw = newValue.rawValue }
    }
    
    public var displayValue: String {
        switch fieldType {
        case .text, .singleSelect, .multiSelect, .url, .phone, .longText:
            return (stringValue?.isEmpty == false) ? stringValue! : "—"
        case .number:
            if let n = numberValue {
                return n.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", n) : String(format: "%.2f", n)
            }
            return "—"
        case .currency:
            if let n = numberValue {
                return "\(String(format: "%.2f", n)) RON"
            }
            return "—"
        case .date:
            if let d = dateValue {
                return d.formatted(.dateTime.day().month().year())
            }
            return "—"
        case .boolean:
            if let b = boolValue {
                return b ? "Da" : "Nu"
            }
            return "—"
        }
    }
    
    public init(
        id: UUID = UUID(),
        key: String,
        label: String,
        fieldType: DynamicFieldType = .text,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        dateValue: Date? = nil,
        boolValue: Bool? = nil,
        asset: Asset? = nil
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.fieldTypeRaw = fieldType.rawValue
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.dateValue = dateValue
        self.boolValue = boolValue
        self.asset = asset
    }
}
