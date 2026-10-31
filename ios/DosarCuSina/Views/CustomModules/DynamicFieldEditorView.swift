import SwiftUI
import SwiftData

/// Dynamic form component for managing custom attributes on an asset.
/// Supports inline, non-modal editing of Text, Number, Date, Boolean, and Currency attributes.
public struct DynamicFieldEditorView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Binding support for standalone/builder mode
    @Binding private var externalFields: [DynamicField]
    private var asset: Asset?
    
    // Inline new field draft state
    @State private var newFieldLabel: String = ""
    @State private var selectedFieldType: DynamicFieldType = .text
    @State private var isAddingField: Bool = false
    
    /// Initializer for editing fields on an existing SwiftData `Asset`.
    public init(asset: Asset) {
        self.asset = asset
        self._externalFields = .constant([])
    }
    
    /// Initializer for editing fields within a builder flow (e.g. `CustomModuleBuilderView`).
    public init(fields: Binding<[DynamicField]>) {
        self.asset = nil
        self._externalFields = fields
    }
    
    private var currentFields: [DynamicField] {
        if let asset = asset {
            return asset.dynamicFields
        } else {
            return externalFields
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with field count & add button
            HStack {
                Label {
                    Text("Atribute Personalizate")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                if !currentFields.isEmpty {
                    Text("\(currentFields.count) \(currentFields.count == 1 ? "atribut" : "atribute")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            
            // List of existing dynamic fields
            if currentFields.isEmpty && !isAddingField {
                emptyStateCard
            } else {
                VStack(spacing: 10) {
                    ForEach(currentFields) { field in
                        DynamicFieldRow(
                            field: field,
                            onDelete: {
                                deleteField(field)
                            }
                        )
                    }
                }
            }
            
            // Inline New Field Creation Card
            if isAddingField {
                addFieldCard
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            } else {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isAddingField = true
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Adaugă Câmp Nou")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.08))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateCard: some View {
        VStack(spacing: 6) {
            Text("Niciun atribut definit încă")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Poți adăuga numere de serie, cote, specificații tehnice sau date de contract.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Add Field Inline Card
    private var addFieldCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Câmp Personalizat Nou")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAddingField = false
                        newFieldLabel = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }
            }
            
            // Field Label Input
            TextField("Etichetă (ex: Serie Șasiu, Nivel Ulei)", text: $newFieldLabel)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // Field Type Picker Chips
            VStack(alignment: .leading, spacing: 6) {
                Text("Tipul valorii:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DynamicFieldType.allCases, id: \.self) { type in
                            FieldTypeChip(
                                type: type,
                                isSelected: selectedFieldType == type,
                                onSelect: {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    selectedFieldType = type
                                }
                            )
                        }
                    }
                }
            }
            
            // Action Buttons
            HStack(spacing: 10) {
                Button("Anulează") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAddingField = false
                        newFieldLabel = ""
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                Button {
                    confirmAddField()
                } label: {
                    Text("Salvează Atribut")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            canSaveField
                                ? Color.blue
                                : Color.blue.opacity(0.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(!canSaveField)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    private var canSaveField: Bool {
        !newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func confirmAddField() {
        let trimmed = newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let sanitizedKey = trimmed
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "ro_RO"))
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        
        let newField = DynamicField(
            key: sanitizedKey.isEmpty ? "field_\(UUID().uuidString.prefix(6))" : sanitizedKey,
            label: trimmed,
            fieldType: selectedFieldType
        )
        
        // Provide default values based on type
        switch selectedFieldType {
        case .boolean:
            newField.boolValue = false
        case .date:
            newField.dateValue = Date()
        default:
            break
        }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let asset = asset {
                asset.dynamicFields.append(newField)
                asset.updatedAt = Date()
            } else {
                externalFields.append(newField)
            }
            newFieldLabel = ""
            isAddingField = false
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func deleteField(_ field: DynamicField) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let asset = asset {
                asset.dynamicFields.removeAll { $0.id == field.id }
                modelContext.delete(field)
                asset.updatedAt = Date()
            } else {
                externalFields.removeAll { $0.id == field.id }
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Dynamic Field Row with Inline Controls
private struct DynamicFieldRow: View {
    @Bindable var field: DynamicField
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Field Header
            HStack {
                Label {
                    Text(field.label)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                } icon: {
                    Image(systemName: field.fieldType.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(field.fieldType.accentColor)
                }
                
                Spacer()
                
                Text(field.fieldType.displayTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(field.fieldType.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(field.fieldType.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            
            // Inline Value Editor based on type
            valueEditor
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
    
    @ViewBuilder
    private var valueEditor: some View {
        switch field.fieldType {
        case .text:
            TextField("Introdu valoare text...", text: Binding(
                get: { field.stringValue ?? "" },
                set: { field.stringValue = $0 }
            ))
            .font(.system(.body, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
        case .number:
            TextField("0", text: Binding(
                get: { field.numberValue != nil ? String(format: "%g", field.numberValue!) : "" },
                set: { field.numberValue = Double($0.replacingOccurrences(of: ",", with: ".")) }
            ))
            .keyboardType(.decimalPad)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
        case .date:
            DatePicker(
                "Dată",
                selection: Binding(
                    get: { field.dateValue ?? Date() },
                    set: { field.dateValue = $0 }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            
        case .boolean:
            Toggle(
                field.boolValue == true ? "Activat / Valabil" : "Inactiv / Neconfigurat",
                isOn: Binding(
                    get: { field.boolValue ?? false },
                    set: { field.boolValue = $0 }
                )
            )
            .font(.system(.subheadline, design: .rounded))
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            
        case .currency:
            HStack(spacing: 8) {
                TextField("0.00", text: Binding(
                    get: { field.numberValue != nil ? String(format: "%.2f", field.numberValue!) : "" },
                    set: { field.numberValue = Double($0.replacingOccurrences(of: ",", with: ".")) }
                ))
                .keyboardType(.decimalPad)
                .font(.system(.body, design: .monospaced))
                
                Text("RON")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - Field Type Chip
private struct FieldTypeChip: View {
    let type: DynamicFieldType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: type.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(type.displayTitle)
                    .font(.system(.caption, design: .rounded, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? type.accentColor.opacity(0.18)
                    : Color(uiColor: .tertiarySystemGroupedBackground)
            )
            .foregroundStyle(
                isSelected
                    ? type.accentColor
                    : Color.secondary
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? type.accentColor : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DynamicFieldType UI Extensions
extension DynamicFieldType {
    public var displayTitle: String {
        switch self {
        case .text: return "Text"
        case .number: return "Număr"
        case .date: return "Dată"
        case .boolean: return "Comutator"
        case .currency: return "Monetară"
        }
    }
    
    public var iconName: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .date: return "calendar"
        case .boolean: return "switch.2"
        case .currency: return "banknote"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .text: return .blue
        case .number: return .orange
        case .date: return .green
        case .boolean: return .purple
        case .currency: return .teal
        }
    }
}
