import SwiftUI

/// Polished specifications subview for Home, Property & Utilities assets.
/// Adheres to the Apple Craftsmanship & Polish Standard with concentric geometry,
/// 1-tap copy for utility codes (POD, CLC, Water), and Romanian administrative standards.
public struct HomeDomainSectionView: View {
    public let asset: Asset
    
    @State private var copiedField: String? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. Property Details Card
            propertyCard
            
            // 2. Utility Identifiers Card (POD, CLC, Water Codes with 1-Tap Copy)
            utilityCodesCard
            
            // 3. Technical Equipment & Metrology Card (Boiler, Water Meters)
            technicalEquipmentCard
            
            // 4. Administrative Ground Truth Notice
            administrativeComplianceCard
        }
    }
    
    // MARK: - Property Details Card
    private var propertyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Date Imobil & Cadastru", icon: "house.fill", color: .indigo)
            
            VStack(spacing: 8) {
                if let addr = asset.address ?? asset.fullAddress, !addr.isEmpty {
                    infoRow(label: "Adresă", value: addr)
                }
                
                if let cad = asset.cadastralNumber, !cad.isEmpty {
                    copyableRow(label: "Număr Cadastral / CF", value: cad, fieldKey: "cadastral")
                }
                
                HStack {
                    if let area = asset.surfaceAreaSqm ?? asset.surfaceAreaM2, area > 0 {
                        infoBadge(label: "Suprafață", value: "\(Int(area)) m²", icon: "square.dashed")
                    }
                    if let year = asset.constructionYear, year > 0 {
                        infoBadge(label: "An Construcție", value: "\(year)", icon: "calendar")
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Utility Identifiers Card
    private var utilityCodesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Coduri Utilități & Facturare", icon: "bolt.fill", color: .orange)
            
            VStack(spacing: 8) {
                if let pod = asset.podCode, !pod.isEmpty {
                    copyableRow(label: "POD Energie Electrică", value: pod, fieldKey: "pod", note: "Necesar la schimbare furnizor")
                }
                
                if let clc = asset.clcCode, !clc.isEmpty {
                    copyableRow(label: "CLC Gaze Naturale", value: clc, fieldKey: "clc", note: "Cod Loc Consum gaze")
                }
                
                if let water = asset.waterClientCode, !water.isEmpty {
                    copyableRow(label: "Cod Client Apă / Canal", value: water, fieldKey: "water")
                }
                
                // Self-Read Window Banner (Days 20-25)
                if let start = asset.meterReadWindowStartDay, let end = asset.meterReadWindowEndDay {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fereastră Autocitire Index")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("Zilele \(start) – \(end) ale fiecărei luni pentru transmitere index.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                    )
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Technical Equipment & Meters Card
    private var technicalEquipmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Instalații & Contoare", icon: "flame.fill", color: .red)
            
            VStack(spacing: 8) {
                if let boiler = asset.heatingBoilerModel, !boiler.isEmpty {
                    infoRow(label: "Centrală Termică", value: boiler)
                }
                if let boilerS = asset.heatingBoilerSerial, !boilerS.isEmpty {
                    copyableRow(label: "Serie Centrală", value: boilerS, fieldKey: "boiler_serial")
                }
                if let gasS = asset.gasMeterSerial, !gasS.isEmpty {
                    copyableRow(label: "Serie Contor Gaze", value: gasS, fieldKey: "gas_meter")
                }
                if let elecS = asset.electricityMeterSerial, !elecS.isEmpty {
                    copyableRow(label: "Serie Contor Electric", value: elecS, fieldKey: "elec_meter")
                }
                if let waterS = asset.waterMeterSerial, !waterS.isEmpty {
                    copyableRow(label: "Serie Apometru", value: waterS, fieldKey: "water_meter")
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Administrative Standards Compliance Card
    private var administrativeComplianceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Standarde Legale România (Locuință)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• ISCIR VTP: Obligatoriu la 2 ani (PT A1)\n• ANRE Gaze: Verificare (VIG) la 2 ani / Revizie (RIG) la 10 ani\n• Apometre: Valabilitate 7 ani (apă rece) / 4 ani (apă caldă)\n• Certificat Energetic: Valabil 10 ani (Legea 372/2005)\n• Impozit Clădire: 31 martie (bonificație până la 10%) & 30 septembrie")
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
    
    // MARK: - Helper Views & Builders
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
