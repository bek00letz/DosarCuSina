import SwiftUI

/// Polished specifications subview for Personal & Family Health assets.
/// Implements the ICE (In Case of Emergency) Medical Card, blood type pill,
/// semantic allergy tags, emergency doctor contacts, and Model B Just-in-Time security.
public struct HealthDomainSectionView: View {
    public let asset: Asset
    
    @State private var vaultManager = BiometricVaultManager.shared
    @State private var isAuthenticating: Bool = false
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    private var isUnlocked: Bool {
        vaultManager.isUnlocked(category: .health)
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. ICE Emergency Medical Card
            iceMedicalCard
            
            // 2. Family Member Profile & Age
            profileCard
            
            // 3. Medical Contacts & Doctors Card
            medicalContactsCard
            
            // 4. Romanian Health Standards Notice
            healthComplianceCard
        }
    }
    
    // MARK: - 1. ICE Emergency Medical Card
    private var iceMedicalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Card Medical de Urgență (ICE)", systemImage: "cross.case.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.red)
                
                Spacer()
                
                if !isUnlocked {
                    Button {
                        authenticateVault()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vaultManager.biometrySystemImage)
                            Text("Deblochează")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Blood Type Pill & Allergies
            HStack(spacing: 12) {
                // Blood Type Pill
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grupă Sanguină")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text(asset.bloodType ?? "Nespecificată")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                
                // Chronic Conditions Indicator
                if let chronic = asset.chronicConditions, !chronic.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Afecțiuni Cronice")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Text(isUnlocked ? chronic : "••••••••")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            
            // Allergies Semantic Banner
            if let allergies = asset.allergies ?? asset.allergiesNotes, !allergies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Alergii Cunoscute")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    
                    Text(isUnlocked ? allergies : "Date protejate prin autentificare biometrică")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 2. Profile Card
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Profil Membru Familie", icon: "person.crop.circle.fill", color: .blue)
            
            VStack(spacing: 8) {
                if let name = asset.personName ?? asset.name as String?, !name.isEmpty {
                    infoRow(label: "Nume & Prenume", value: isUnlocked ? name : vaultManager.displayValue(for: name, in: .health, visiblePrefix: 2, visibleSuffix: 1))
                }
                
                if let bdate = asset.birthDate ?? asset.petBirthDate {
                    infoRow(label: "Data Nașterii", value: formattedDate(bdate))
                    if let age = calculateAge(from: bdate) {
                        infoRow(label: "Vârstă Calculată", value: "\(age) ani")
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 3. Medical Contacts Card
    private var medicalContactsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Medici & Contacte Urgență", icon: "phone.circle.fill", color: .green)
            
            VStack(spacing: 8) {
                if let doc = asset.familyDoctorName ?? asset.primaryContactName, !doc.isEmpty {
                    contactRow(
                        role: "Medic de Familie",
                        name: doc,
                        phone: asset.familyDoctorPhone ?? asset.primaryContactPhone
                    )
                }
                
                if let ice = asset.emergencyContactName ?? asset.emergencyContact, !ice.isEmpty {
                    contactRow(
                        role: "Contact Urgență",
                        name: ice,
                        phone: asset.emergencyContactPhone
                    )
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 4. Compliance Card
    private var healthComplianceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("Prevenție & Standarde CNAS România")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• Pachet Prevenție CNAS: Analize anuale uzuale decontate\n• CEASS (Card European de Sănătate): Valabil 24 de luni\n• Stomatologie: Detartraj & control recomandat la 6 luni\n• Rețete Cronice: Valabilitate 30 sau 90 de zile")
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
    
    private func contactRow(role: String, name: String, phone: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
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
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
    }
    
    private func calculateAge(from birthDate: Date) -> Int? {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
        return ageComponents.year
    }
    
    private func authenticateVault() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            await vaultManager.unlockCategory(.health)
            await MainActor.run {
                self.isAuthenticating = false
            }
        }
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
