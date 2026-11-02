import SwiftUI

/// The design-system control for one template field, bound into a set of values.
/// Every field type maps to exactly one control, so every screen edits the same way.
struct FieldEditor: View {
    let field: FieldDefinition
    @Binding var values: FieldValues
    var isRequired = false

    @Environment(\.calendar) private var calendar
    @State private var currency: String

    init(field: FieldDefinition, values: Binding<FieldValues>, isRequired: Bool = false) {
        self.field = field
        self._values = values
        self.isRequired = isRequired
        _currency = State(initialValue: values.wrappedValue[field.key]?.moneyValue?.currency ?? Money.defaultCurrency)
    }

    private var title: LocalizedStringKey { LocalizedStringKey(field.label) }
    private var prompt: LocalizedStringKey? { field.placeholder.map { LocalizedStringKey($0) } }

    var body: some View {
        switch field.type {
        case .text, .longText, .url, .phone, .email, .address, .plate, .vin, .microchip, .iban:
            DSTextField(
                title,
                text: textBinding,
                kind: FieldEditor.textKind(for: field.type),
                prompt: prompt,
                isRequired: isRequired,
                validator: { FieldEditor.validation(FieldFormatter.validate($0, as: field.type)) },
                formatter: { FieldFormatter.normalize($0, as: field.type) }
            )
        case .number, .metric:
            DSMetricField(title, value: numberBinding, unit: field.unit ?? "", isRequired: isRequired)
        case .money:
            DSMoneyField(title, amount: moneyBinding, currencyCode: currencyBinding, isRequired: isRequired)
        case .date:
            DSDateField(title, date: dateBinding, isRequired: isRequired)
        case .expiryDate:
            DSExpiryDateField(title, date: dateBinding, isRequired: isRequired)
        case .toggle:
            DSToggleField(title, isOn: boolBinding)
        case .choice:
            DSChoiceField(title, selection: choiceBinding, options: (field.options ?? []).map(\.key), isRequired: isRequired) {
                field.label(forChoice: $0)
            }
        case .multiChoice:
            DSMultiChoiceField(title, selection: choicesBinding, options: (field.options ?? []).map(\.key)) {
                field.label(forChoice: $0)
            }
        }
    }

    // MARK: Bindings

    private var textBinding: Binding<String> {
        Binding {
            values[field.key]?.textValue ?? ""
        } set: { newValue in
            values[field.key] = newValue.isEmpty ? nil : .text(newValue)
        }
    }

    private var numberBinding: Binding<Double?> {
        Binding { values[field.key]?.numberValue } set: { values[field.key] = $0.map(FieldValue.number) }
    }

    private var moneyBinding: Binding<Decimal?> {
        Binding {
            values[field.key]?.moneyValue?.amount
        } set: { amount in
            values[field.key] = amount.map { .money(Money($0, currency: currency)) }
        }
    }

    private var currencyBinding: Binding<String> {
        Binding {
            currency
        } set: { code in
            currency = code
            if let amount = values[field.key]?.moneyValue?.amount {
                values[field.key] = .money(Money(amount, currency: code))
            }
        }
    }

    private var dateBinding: Binding<Date?> {
        Binding {
            values[field.key]?.dateValue?.noonDate(in: calendar)
        } set: { date in
            values[field.key] = date.map { .date(CalendarDay($0, calendar: calendar)) }
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding { values[field.key]?.boolValue ?? false } set: { values[field.key] = .bool($0) }
    }

    private var choiceBinding: Binding<String?> {
        Binding {
            values[field.key]?.textValue.map(field.choiceKey(for:))
        } set: { key in
            values[field.key] = key.map(FieldValue.text)
        }
    }

    private var choicesBinding: Binding<Set<String>> {
        Binding {
            Set(values[field.key]?.choicesValue ?? [])
        } set: { keys in
            let ordered = (field.options ?? []).map(\.key).filter(keys.contains)
            values[field.key] = ordered.isEmpty ? nil : .choices(ordered)
        }
    }

    // MARK: Mapping

    static func textKind(for type: FieldType) -> DSTextKind {
        switch type {
        case .longText: .longText
        case .url: .url
        case .phone: .phone
        case .email: .email
        case .address: .address
        case .plate: .plate
        case .vin: .vin
        case .microchip: .microchip
        case .iban: .iban
        default: .text
        }
    }

    static func validation(_ result: FieldValidation) -> DSValidation {
        switch result {
        case .empty, .valid: .valid
        case .warning(let text): .warning(LocalizedStringResource(stringLiteral: text))
        case .invalid(let text): .invalid(LocalizedStringResource(stringLiteral: text))
        }
    }
}

/// Whether the values are good enough to save: no field holds text its type rejects.
enum FieldValuesCheck {
    static func canSave(_ values: FieldValues, fields: [FieldDefinition]) -> Bool {
        fields.allSatisfy { field in
            guard let text = values[field.key]?.textValue, field.type.valueKind == .text,
                  field.type != .choice else { return true }
            return FieldFormatter.validate(text, as: field.type).allowsSaving
        }
    }
}
