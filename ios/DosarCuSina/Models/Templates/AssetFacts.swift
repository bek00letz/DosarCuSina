import Foundation

/// When and where something was bought, read from field roles so it works for
/// any category: "cât am plătit pe aragaz", "când am luat hota".
public struct PurchaseInfo: Hashable, Sendable {
    public var date: CalendarDay?
    public var price: Money?
    public var retailer: String?
    public var warrantyUntil: CalendarDay?

    public var isEmpty: Bool { date == nil && price == nil && retailer == nil && warrantyUntil == nil }

    /// Whether the warranty still covers `day`.
    public func isUnderWarranty(on day: CalendarDay) -> Bool? {
        warrantyUntil.map { day <= $0 }
    }
}

/// A fact for the asset's top card, ready to show, copy or call.
public struct KeyFact: Hashable, Sendable, Identifiable {
    public var field: FieldDefinition
    public var value: FieldValue
    /// Formatted for display.
    public var text: String

    public var id: String { field.key }
    /// The fact is a phone number someone may want to call.
    public var isCallable: Bool { field.type == .phone }
}

/// One row under Date importante: a key fact from the template or a free row.
public struct FactRow: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var text: String
    public var isCallable: Bool
    public var isSensitive: Bool
    /// A free row the person added, editable in place.
    public var isCustom: Bool
    /// A secret row: `text` is only the mask, and `sealed` the code, opened after Face ID.
    public var isSecret = false
    public var sealed: String?
}

/// Role-based reading of an asset's values, so screens and engines never hard-code field keys.
public enum AssetFacts {
    public static func purchase(_ values: FieldValues, template: TemplateDefinition) -> PurchaseInfo {
        func value(_ role: FieldRole) -> FieldValue? {
            template.fields(withRole: role).lazy.compactMap { values[$0.key] }.first
        }
        return PurchaseInfo(
            date: value(.purchaseDate)?.dateValue,
            price: value(.purchasePrice)?.moneyValue,
            retailer: value(.retailer)?.textValue,
            warrantyUntil: value(.warrantyUntil)?.dateValue
        )
    }

    /// Identifiers, document numbers and key facts that have a value, in the template's order.
    public static func keyFacts(_ values: FieldValues, template: TemplateDefinition, locale: Locale = .dosarDefault) -> [KeyFact] {
        template.keyFactFields.compactMap { field in
            guard let value = values[field.key] else { return nil }
            return KeyFact(field: field, value: value, text: FieldFormatter.display(value, field: field, locale: locale))
        }
    }

    /// Everything Date importante shows: the template's key facts, then the person's own rows.
    public static func factRows(_ values: FieldValues, customFacts: [CustomFact], template: TemplateDefinition?, locale: Locale = .dosarDefault) -> [FactRow] {
        let fromTemplate = template.map { keyFacts(values, template: $0, locale: locale) } ?? []
        return fromTemplate.map {
            FactRow(id: $0.field.key, label: $0.field.label, text: $0.text, isCallable: $0.isCallable, isSensitive: $0.field.isSensitive, isCustom: false)
        } + customFacts.map {
            $0.isSecret
                ? FactRow(id: $0.id.uuidString, label: $0.label, text: SecretFields.mask, isCallable: false, isSensitive: true, isCustom: true,
                          isSecret: true, sealed: $0.value.isEmpty ? nil : $0.value)
                : FactRow(id: $0.id.uuidString, label: $0.label, text: $0.value, isCallable: false, isSensitive: $0.isSensitive, isCustom: true)
        }
    }

    /// The date the asset itself stops being valid (a document, a contract), if the template has one.
    public static func expiry(_ values: FieldValues, template: TemplateDefinition) -> CalendarDay? {
        template.fields(withRole: .expiryDate).lazy.compactMap { values[$0.key]?.dateValue }.first
    }

    public static func text(_ role: FieldRole, in values: FieldValues, template: TemplateDefinition) -> String? {
        template.fields(withRole: role).lazy.compactMap { values[$0.key]?.textValue }.first
    }
}
