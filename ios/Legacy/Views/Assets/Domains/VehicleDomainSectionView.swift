import SwiftUI

/// Polished specifications subview for Vehicles & Mobility assets.
/// Displays 17-char ISO 3779 VIN with 1-tap copy & validation, Romanian license plate,
/// CIV series, engine & fuel specifications, age-aware RAR ITP status, and Romanian road standards.
public struct VehicleDomainSectionView: View {
    public let asset: Asset
    
    @State private var copiedField: String? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. Romanian License Plate & Core Identity Card
            licensePlateCard
            
            // 2. Technical Specifications & Engine Card
            technicalSpecsCard
            
            // 3. Official Documents & VIN Card
            vinAndDocumentsCard
            
            // 4. Romanian Road & Administrative Standards Notice (Rovinietă 2026, Taxă Pod Eliminată)
            mobilityStandardsNoticeCard
        }
    }
    
    // MARK: - 1. License Plate Card
    private var licensePlateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Realistic Romanian License Plate Component
                romanianLicensePlateView
                
                Spacer()
                
                if let mileage = asset.currentMileageKm ?? (asset.currentMetricValue.map { Int($0) }) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Kilometraj")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(mileage) km")
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            
            if let make = asset.make, let model = asset.modelName {
                HStack(spacing: 6) {
                    Text("\(make) \(model)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    if let year = asset.manufactureYear {
                        Text("(\(year))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 2. Technical Specs Card
    private var technicalSpecsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Motorizare & Carburant", icon: "engine.combustion.fill", color: .orange)
            
            VStack(spacing: 8) {
                if let fuel = asset.fuelType, !fuel.isEmpty {
                    infoRow(label: "Tip Combustibil", value: fuel)
                }
                
                if let disp = asset.engineDisplacementCc ?? asset.engineDisplacementCm3 {
                    let kw = asset.enginePowerKw ?? asset.enginePowerHp
                    let pwrStr = kw != nil ? " • \(kw!) CP" : ""
                    infoRow(label: "Cilindree & Putere", value: "\(disp) cm³\(pwrStr)")
                }
                
                if let year = asset.manufactureYear {
                    let carAge = Calendar.current.component(.year, from: Date()) - year
                    let itpCadence = getItpCadenceDescription(ageYears: carAge)
                    infoRow(label: "Vechime & Cadență ITP", value: "\(carAge) ani (\(itpCadence))")
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 3. VIN & Documents Card
    private var vinAndDocumentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Identificare Oficială & CIV", icon: "doc.text.fill", color: .blue)
            
            VStack(spacing: 8) {
                if let vin = asset.vin ?? asset.vinNumber, !vin.isEmpty {
                    let isValid = isValidVIN(vin)
                    copyableRow(
                        label: "Serie Șasiu (VIN)",
                        value: vin,
                        fieldKey: "vin",
                        validationIcon: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        validationColor: isValid ? .green : .orange
                    )
                }
                
                if let civ = asset.civSeries, !civ.isEmpty {
                    copyableRow(label: "Serie CIV (Carte Identitate)", value: civ, fieldKey: "civ")
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 4. Romanian Road & Mobility Standards Notice
    private var mobilityStandardsNoticeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "road.lanes")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Standarde Rutiere România (Actualizate 2026)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• Rovinietă (Legea 226/2023): Durate 1 zi, 10 zile, 30 zile, 60 zile, 12 luni, diferențiată pe norme Euro/EV\n• Taxă Pod Fetești (A2): ELIMINATĂ de la 1 oct 2026 (inclusă în Rovinietă, fără SMS 8545)\n• ITP (RNTR 1): Suspendare automată a înmatriculării de drept la data expirării!\n• Impozit Auto: 31 martie (bonificație până la 10%) & 30 septembrie")
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
    
    // MARK: - Romanian License Plate Badge
    private var romanianLicensePlateView: some View {
        let plate = asset.licensePlate ?? "B-123-ABC"
        return HStack(spacing: 0) {
            // Blue European Band
            VStack(spacing: 2) {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                Text("RO")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 32)
            .background(Color.blue)
            
            // License Plate Number
            Text(plate.uppercased())
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .tracking(1.5)
                .padding(.horizontal, 10)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
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
    
    private func copyableRow(label: String, value: String, fieldKey: String, validationIcon: String? = nil, validationColor: Color = .green) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let icon = validationIcon {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundStyle(validationColor)
                    }
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
    
    private func isValidVIN(_ vin: String) -> Bool {
        let trimmed = vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 17 else { return false }
        let regex = "^[A-HJ-NPR-Z0-9]{17}$"
        return trimmed.range(of: regex, options: .regularExpression) != nil
    }
    
    private func getItpCadenceDescription(ageYears: Int) -> String {
        if ageYears < 3 {
            return "Prima inspecție la 3 ani"
        } else if ageYears <= 12 {
            return "La fiecare 2 ani"
        } else {
            return "Anual (vehicul > 12 ani)"
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
