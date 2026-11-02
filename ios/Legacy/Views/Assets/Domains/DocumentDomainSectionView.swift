import SwiftUI

/// Polished specifications subview for Identity & Legal Documents.
/// Features Model B Just-in-Time biometric masking for sensitive series & CNP,
/// 1-tap copy, and the international 6-Month Non-EU Travel Rule warning banner for passports.
public struct DocumentDomainSectionView: View {
    public let asset: Asset
    
    @State private var vaultManager = BiometricVaultManager.shared
    @State private var copiedField: String? = nil
    @State private var isAuthenticating: Bool = false
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    private var isUnlocked: Bool {
        vaultManager.isUnlocked(category: .documents)
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. Passport Travel Warning Banner (if within 6 months of expiry)
            if shouldShowPassportNonEUWarning {
                passportTravelWarningCard
            }
            
            // 2. Identity Document Serial & Issuing Authority Card
            documentCard
            
            // 3. Validity & Renewal Schedule Card
            validityCard
            
            // 4. Romanian Bureaucratic Standards Card
            legalStandardsCard
        }
    }
    
    // MARK: - 1. Passport 6-Month Travel Warning Card
    private var passportTravelWarningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Regula celor 6 Luni (Călătorii Non-UE)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("Pașaportul intră sau se află în ultimele 6 luni de valabilitate. Majoritatea țărilor din afara Uniunii Europene (Turcia, Marea Britanie, SUA, Emiratele Arabe, Asia) cer minimum 6 luni valabilitate de la data intrării.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 2. Document Card
    private var documentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                domainHeader(title: "Date Document & Emitent", icon: "person.text.rectangle.fill", color: .purple)
                
                if !isUnlocked {
                    Button {
                        authenticateVault()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vaultManager.biometrySystemImage)
                            Text("Afișează")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(spacing: 8) {
                if let serial = asset.serialOrImei, !serial.isEmpty {
                    let displaySerial = isUnlocked ? serial : vaultManager.displayValue(for: serial, in: .documents, visiblePrefix: 2, visibleSuffix: 2)
                    copyableRow(label: "Serie & Număr Document", value: displaySerial, rawCopyValue: serial, fieldKey: "doc_serial")
                }
                
                if let issuer = asset.retailerOrIssuer, !issuer.isEmpty {
                    infoRow(label: "Autoritate Emitentă", value: issuer)
                }
                
                if let issueDate = asset.purchaseOrIssueDate {
                    infoRow(label: "Data Emiterii", value: formattedDate(issueDate))
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 3. Validity Card
    private var validityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Termen Valabilitate", icon: "calendar.badge.clock", color: .blue)
            
            VStack(spacing: 8) {
                if let expDate = effectiveExpiryDate {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: expDate).day ?? 0
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Data Expirării")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formattedDate(expDate))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                        }
                        
                        Spacer()
                        
                        Text(daysLeft > 0 ? "\(daysLeft) zile rămase" : "Expirat!")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(daysLeft > 180 ? .blue : (daysLeft > 0 ? .orange : .red))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(daysLeft > 180 ? Color.blue.opacity(0.12) : (daysLeft > 0 ? Color.orange.opacity(0.12) : Color.red.opacity(0.12)))
                            )
                    }
                } else {
                    infoRow(label: "Valabilitate", value: "Permanentă / Fără dată fixă")
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 4. Romanian Bureaucratic Standards Card
    private var legalStandardsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Standarde Valabilitate Acte Oficiale România")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• Cazier Judiciar: Valabil exact 6 luni de la eliberare (Legea 290/2004)\n• Extras Carte Funciară: Acceptat standard 30 de zile\n• Viză de Flotant: Valabilitate maximum 1 an (OUG 97/2005)\n• Permis Conducere: Necesită Fișă Medicală Auto la reînnoire\n• Certificat Digital Calificat (ANAF SPV): Reînnoire la 1-3 ani")
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
    private var effectiveExpiryDate: Date? {
        if let d = asset.contractEndDate {
            return d
        }
        // Check active lifecycle events
        return asset.events.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }.first?.dueDate
    }
    
    private var shouldShowPassportNonEUWarning: Bool {
        let isPassport = asset.name.localizedCaseInsensitiveContains("pasaport") ||
                         asset.name.localizedCaseInsensitiveContains("pașaport") ||
                         (asset.subtitle?.localizedCaseInsensitiveContains("pasaport") ?? false)
        guard isPassport, let expDate = effectiveExpiryDate else { return false }
        let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: expDate).day ?? 0
        return daysLeft <= 180
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
    
    private func copyableRow(label: String, value: String, rawCopyValue: String, fieldKey: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            Button {
                UIPasteboard.general.string = rawCopyValue
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
                            .foregroundStyle(.purple)
                        Text("Copiază")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.purple)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(copiedField == fieldKey ? Color.green.opacity(0.12) : Color.purple.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
    }
    
    private func authenticateVault() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            await vaultManager.unlockCategory(.documents)
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
