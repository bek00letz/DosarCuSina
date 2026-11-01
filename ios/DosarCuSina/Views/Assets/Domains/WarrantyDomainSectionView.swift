import SwiftUI

/// Polished specifications subview for Warranties, Appliances & Consumer Goods.
/// Displays Serial / IMEI with 1-tap copy, standard & extended warranty months,
/// statutory warranty extension per OUG 140/2021, and the -30d Last-Chance Inspection alert.
public struct WarrantyDomainSectionView: View {
    public let asset: Asset
    
    @State private var copiedField: String? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. Last-Chance Inspection Alert Banner (if within 30 days of warranty expiration)
            if isWithinLastChanceWindow {
                lastChanceInspectionCard
            }
            
            // 2. Product Identity & Retailer Card
            productCard
            
            // 3. Warranty Status & Statutory Extension Card
            warrantyCard
            
            // 4. Romanian Consumer Protection Legal Notice (OUG 140/2021)
            consumerProtectionNoticeCard
        }
    }
    
    // MARK: - 1. Last-Chance Inspection Card
    private var lastChanceInspectionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Ultima Șansă: Verificare Înainte de Expirare")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                
                if let days = daysUntilWarrantyExpiry {
                    Text("Garanția expiră în \(days) \(days == 1 ? "zi" : "zile"). Verifică funcționarea aparatului, sănătatea bateriei sau eventuale defecte pentru a solicita reparația gratuită pe garanție.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
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
    
    // MARK: - 2. Product Card
    private var productCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Produs & Achiziție", icon: "tag.fill", color: .blue)
            
            VStack(spacing: 8) {
                if let serial = asset.serialOrImei, !serial.isEmpty {
                    copyableRow(label: "Serie / IMEI", value: serial, fieldKey: "warranty_serial")
                }
                
                if let retailer = asset.retailerOrIssuer, !retailer.isEmpty {
                    infoRow(label: "Magazin / Comerciant", value: retailer)
                }
                
                if let pdate = asset.purchaseOrIssueDate {
                    infoRow(label: "Data Achiziției", value: formattedDate(pdate))
                }
                
                if let price = asset.purchasePrice, price > 0 {
                    infoRow(label: "Preț Achiziție", value: "\(String(format: "%.2f", price)) RON")
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 3. Warranty Status Card
    private var warrantyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Acoperire Garanție & Prelungiri", icon: "shield.fill", color: .green)
            
            VStack(spacing: 8) {
                let standardMonths = asset.warrantyMonths ?? 24
                let extendedMonths = asset.extendedWarrantyMonths ?? 0
                let totalMonths = standardMonths + extendedMonths
                
                HStack {
                    infoBadge(label: "Standard", value: "\(standardMonths) luni", icon: "clock")
                    if extendedMonths > 0 {
                        infoBadge(label: "Extinsă", value: "+\(extendedMonths) luni", icon: "plus.shield.fill")
                    }
                    Spacer()
                }
                
                if let pdate = asset.purchaseOrIssueDate {
                    if let expDate = Calendar.current.date(byAdding: .month, value: totalMonths, to: pdate) {
                        let finalDate = Calendar.current.date(byAdding: .day, value: totalRmaExtensionDays, to: expDate) ?? expDate
                        infoRow(label: "Expirare Calculată", value: formattedDate(finalDate))
                    }
                }
                
                // Statutory RMA Days in Service extension
                if totalRmaExtensionDays > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                        Text("Prelungire legală: +\(totalRmaExtensionDays) zile în service autorizat (OUG 140/2021)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                    )
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 4. Consumer Protection Notice
    private var consumerProtectionNoticeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Drepturi Consumator România (OUG 140/2021)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• Garanție Legală de Conformitate: Minim 2 ani pentru bunuri noi\n• Timp Maxim de Reparație: 15 zile calendaristice\n• Prelungire Automată: Perioada în care produsul stă în service prelungește termenul de garanție\n• Înlocuire / Restituire: Dacă reparația depășește 15 zile sau viciul reapare")
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
    private var totalRmaExtensionDays: Int {
        asset.serviceItems.compactMap { $0.daysInService }.reduce(0, +)
    }
    
    private var daysUntilWarrantyExpiry: Int? {
        guard let pdate = asset.purchaseOrIssueDate else { return nil }
        let months = (asset.warrantyMonths ?? 24) + (asset.extendedWarrantyMonths ?? 0)
        guard let baseExpiry = Calendar.current.date(byAdding: .month, value: months, to: pdate) else { return nil }
        let finalExpiry = Calendar.current.date(byAdding: .day, value: totalRmaExtensionDays, to: baseExpiry) ?? baseExpiry
        let days = Calendar.current.dateComponents([.day], from: Date(), to: finalExpiry).day ?? 0
        return days
    }
    
    private var isWithinLastChanceWindow: Bool {
        guard let days = daysUntilWarrantyExpiry else { return false }
        return days > 0 && days <= 30
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
    
    private func copyableRow(label: String, value: String, fieldKey: String) -> some View {
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
