import SwiftUI

/// Polished specifications subview for Custom modules and Landlord / Rental Hub.
/// Renders structured landlord contract fields (tenant, deposit, lease dates),
/// dynamic custom attribute groups, and Romanian tax compliance reminders (Declarația Unică ANAF 25 mai).
public struct CustomDomainSectionView: View {
    public let asset: Asset
    
    @State private var copiedField: String? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. Landlord Hub & Rental Information Card (if applicable or has tenant)
            if hasLandlordDetails {
                landlordCard
            }
            
            // 2. Custom Attributes & Dynamic Specifications Card
            if !asset.dynamicFields.isEmpty {
                dynamicAttributesCard
            }
            
            // 3. Notes & Context Card
            if let notes = asset.notes, !notes.isEmpty {
                notesCard(notes)
            }
            
            // 4. Romanian Rental & Custom Compliance Card
            if hasLandlordDetails {
                landlordComplianceCard
            }
        }
    }
    
    // MARK: - 1. Landlord Card
    private var landlordCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Hub Închiriere & Contract", icon: "key.fill", color: .purple)
            
            VStack(spacing: 8) {
                if let tenant = asset.primaryContactName, !tenant.isEmpty {
                    infoRow(label: "Nume Chiriaș", value: tenant)
                }
                
                if let phone = asset.primaryContactPhone, !phone.isEmpty {
                    infoRow(label: "Telefon Chiriaș", value: phone)
                }
                
                if let rent = asset.recurringAmount, rent > 0 {
                    let curr = asset.currencyCode.isEmpty ? "RON" : asset.currencyCode
                    infoRow(label: "Chirie Lunară", value: "\(String(format: "%.2f", rent)) \(curr)")
                }
                
                if let start = asset.purchaseOrIssueDate {
                    infoRow(label: "Început Contract", value: formattedDate(start))
                }
                
                if let end = asset.contractEndDate {
                    infoRow(label: "Expirare Contract", value: formattedDate(end))
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 2. Dynamic Attributes Card
    private var dynamicAttributesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Specificații Tehnice & Atribute", icon: "slider.horizontal.3", color: .blue)
            
            VStack(spacing: 8) {
                ForEach(asset.dynamicFields) { field in
                    copyableDynamicRow(field: field)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 3. Notes Card
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            domainHeader(title: "Observații & Detalii", icon: "note.text", color: .gray)
            Text(notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 4. Landlord Compliance Card
    private var landlordComplianceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Obligații Fiscale Proprietar (ANAF)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• Declarația Unică (Formularul 212): Scadență la 25 mai în fiecare an\n• Înregistrare Contract: Obligatorie la ANAF în termen de 30 de zile de la semnare\n• Certificat Energetic: Obligatoriu copie anexată la contractul de locațiune\n• Plafon CASS: Se aplică la depășirea a 6, 12 sau 24 de salarii minime brute pe an")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
    
    // MARK: - Computed Properties
    private var hasLandlordDetails: Bool {
        asset.name.localizedCaseInsensitiveContains("chirie") ||
        asset.name.localizedCaseInsensitiveContains("inchiriat") ||
        asset.name.localizedCaseInsensitiveContains("închiriat") ||
        (asset.subtitle?.localizedCaseInsensitiveContains("chirias") ?? false) ||
        (asset.subtitle?.localizedCaseInsensitiveContains("chiriaș") ?? false) ||
        asset.primaryContactRole?.localizedCaseInsensitiveContains("chirias") == true ||
        asset.primaryContactRole?.localizedCaseInsensitiveContains("chiriaș") == true ||
        asset.dynamicFields.contains { $0.key.contains("chirias") || $0.key.contains("contract") || $0.key.contains("garantie") }
    }
    
    // MARK: - Helpers
    private func domainHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func copyableDynamicRow(field: DynamicField) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(field.displayValue)
                    .font(.system(.caption, design: field.fieldType == .number ? .monospaced : .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            if field.displayValue != "—" && !field.displayValue.isEmpty {
                Button {
                    UIPasteboard.general.string = field.displayValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        copiedField = field.id.uuidString
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedField == field.id.uuidString {
                            withAnimation { copiedField = nil }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if copiedField == field.id.uuidString {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                            Text("Copiat")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                            Text("Copiază")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(copiedField == field.id.uuidString ? Color.green.opacity(0.12) : Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.02), radius: 6, x: 0, y: 2)
    }
}
