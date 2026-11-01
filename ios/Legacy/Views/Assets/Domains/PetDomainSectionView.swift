import SwiftUI

/// Polished specifications subview for Pets & Veterinary Care assets.
/// Displays 15-digit ISO microchip with 1-tap copy, EU pet passport series,
/// breed/species taxonomy, current weight, and veterinary antiparasitic cadences.
public struct PetDomainSectionView: View {
    public let asset: Asset
    
    @State private var copiedField: String? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. Pet Identity Card
            petIdentityCard
            
            // 2. Official Registers & Microchip Card
            identificationCard
            
            // 3. Veterinary Clinic & Doctor Card
            veterinarianCard
            
            // 4. Veterinary & Antiparasitic Cadence Notice
            vetComplianceCard
        }
    }
    
    // MARK: - 1. Pet Identity Card
    private var petIdentityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Profil Animal de Companie", icon: "pawprint.fill", color: .teal)
            
            VStack(spacing: 8) {
                if let specBreed = asset.speciesAndBreed ?? (asset.petSpecies != nil ? "\(asset.petSpecies ?? "") \(asset.petBreed != nil ? "— " + (asset.petBreed ?? "") : "")" : nil), !specBreed.isEmpty {
                    infoRow(label: "Specie & Rasă", value: specBreed)
                }
                
                HStack {
                    if let bdate = asset.birthDate ?? asset.petBirthDate {
                        infoBadge(label: "Data Nașterii", value: formattedDate(bdate), icon: "birthday.cake.fill")
                        if let ageStr = formattedPetAge(from: bdate) {
                            infoBadge(label: "Vârstă", value: ageStr, icon: "hourglass")
                        }
                    }
                    if let weight = asset.weightKg, weight > 0 {
                        infoBadge(label: "Greutate", value: String(format: "%.1f kg", weight), icon: "scalemass.fill")
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 2. Official Registers Card
    private var identificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Identificare Oficială & RECS", icon: "barcode.viewfinder", color: .blue)
            
            VStack(spacing: 8) {
                if let chip = asset.microchipNumber ?? asset.petMicrochipNumber, !chip.isEmpty {
                    copyableRow(label: "Microchip ISO (15 cifre)", value: chip, fieldKey: "microchip", note: "Înregistrat în baza națională RECS")
                }
                
                if let passport = asset.petPassportNumber, !passport.isEmpty {
                    copyableRow(label: "Pașaport European (UE)", value: passport, fieldKey: "passport", note: "Serie carnet de sănătate internațional")
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 3. Vet Clinic Card
    private var veterinarianCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Cabinet & Medic Veterinar", icon: "cross.case.fill", color: .green)
            
            VStack(spacing: 8) {
                let clinic = asset.veterinarianClinic ?? asset.primaryContactRole ?? ""
                let doc = asset.primaryContactName ?? "Cabinet Veterinar"
                let phone = asset.veterinarianPhone ?? asset.primaryContactPhone
                
                if !clinic.isEmpty || !doc.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clinic.isEmpty ? "Cabinet Veterinar" : clinic)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(doc)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let p = phone, !p.isEmpty {
                                Text(p)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if let p = phone, !p.isEmpty, let url = URL(string: "tel://\(p.replacingOccurrences(of: " ", with: ""))") {
                            Link(destination: url) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.green)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } else {
                    Text("Niciun cabinet veterinar asociat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 4. Compliance Notice
    private var vetComplianceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.teal)
                Text("Cadențe Sanitar-Veterinare & Călătorii")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• Deparazitare Internă: Recomandat la fiecare 3 luni (90 zile)\n• Deparazitare Externă: Lunar (pipetă/zgarda) sau 3 luni (comprimate)\n• Vaccin Antirabic: Anual. Călătoria în UE permisă la 21 zile post-vaccinare\n• RECS: Notificarea schimbării proprietarului obligatorie în 7 zile")
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
    
    private func copyableRow(label: String, value: String, fieldKey: String, note: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
                if let n = note {
                    Text(n)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Button {
                UIPasteboard.general.string = value
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    copiedField = fieldKey
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedField == fieldKey {
                        withAnimation { copiedField = nil }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if copiedField == fieldKey {
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
                        .fill(copiedField == fieldKey ? Color.green.opacity(0.12) : Color.blue.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
    
    private func infoBadge(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(label): \(value)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
    }
    
    private func formattedPetAge(from birthDate: Date) -> String? {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: birthDate, to: Date())
        if let y = comps.year, let m = comps.month {
            if y > 0 {
                return m > 0 ? "\(y) ani, \(m) luni" : "\(y) ani"
            } else {
                return "\(m) luni"
            }
        }
        return nil
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
