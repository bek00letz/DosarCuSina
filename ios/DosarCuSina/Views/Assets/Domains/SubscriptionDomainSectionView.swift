import SwiftUI

/// Polished specifications subview for Subscriptions, Contracts & Recurring Obligations.
/// Features normalized monthly burn rate, payment card tracking, 1-tap cancellation URL,
/// and anti-trap alerts (free trial conversion and telecom 24-month retention renegotiation).
public struct SubscriptionDomainSectionView: View {
    public let asset: Asset
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. Telecom Retention or Free Trial Alert Banner
            if isWithinRetentionRenegotiationWindow {
                retentionAlertCard
            }
            
            // 2. Subscription Details & Cost Card
            subscriptionDetailsCard
            
            // 3. Payment Method & Direct Cancellation Card
            paymentAndCancellationCard
            
            // 4. Contract Commitments Notice
            contractCommitmentsNoticeCard
        }
    }
    
    // MARK: - 1. Retention Alert Card
    private var retentionAlertCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Fereastră Renegociere Contract (24 Luni)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("Perioada contractuală minimă expiră în curând. Este momentul optim să contactezi furnizorul pentru o ofertă de fidelizare/retenție sau prelungire la preț promoțional.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 2. Subscription Details Card
    private var subscriptionDetailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Detalii Abonament & Cost", icon: "creditcard.fill", color: .indigo)
            
            VStack(spacing: 8) {
                if let prov = asset.providerName, !prov.isEmpty {
                    infoRow(label: "Furnizor / Serviciu", value: prov)
                }
                
                let cycle = asset.billingCycle ?? "Lunar"
                let curr = asset.currencyCode.isEmpty ? "RON" : asset.currencyCode
                let amt = asset.recurringAmount ?? 0.0
                
                HStack {
                    infoBadge(label: "Recurență", value: cycle, icon: "repeat")
                    if amt > 0 {
                        infoBadge(label: "Cost Recurent", value: "\(String(format: "%.2f", amt)) \(curr)", icon: "banknote")
                    }
                    Spacer()
                }
                
                // Normalized Monthly Burn Rate
                if amt > 0 {
                    let monthlyRate = calculateMonthlyRate(amount: amt, cycle: cycle)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rată Lunară Normalizată")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.2f", monthlyRate)) \(curr) / lună")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    )
                }
                
                if let end = asset.contractEndDate {
                    infoRow(label: "Sfârșit Perioadă Contractuală", value: formattedDate(end))
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 3. Payment & Cancellation Card
    private var paymentAndCancellationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            domainHeader(title: "Card Asociat & Dezabonare", icon: "arrow.triangle.2.circlepath.circle.fill", color: .orange)
            
            VStack(spacing: 8) {
                if let card = asset.paymentCardLast4, !card.isEmpty {
                    HStack {
                        Image(systemName: "creditcard")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text("Card de plată înregistrat:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("•••• \(card)")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                
                if let cancelStr = asset.cancellationUrl, !cancelStr.isEmpty, let cancelUrl = URL(string: cancelStr) {
                    Link(destination: cancelUrl) {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 16))
                            Text("Deschide Portal Dezabonare")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.red)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - 4. Notice Card
    private var contractCommitmentsNoticeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.indigo)
                Text("Protecție Împotriva Capcanelor de Abonare")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            Text("• Notificare Free Trial: Alerte automate la -72h și -24h înainte de prima taxare\n• Telecom România: Notificare la -30 de zile înainte de finalizarea celor 24 de luni\n• Reziliere Legală: Drept de denunțare unilaterală fără penalități după expirarea perioadei minime")
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
    private var isWithinRetentionRenegotiationWindow: Bool {
        guard let end = asset.contractEndDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return days > 0 && days <= 45
    }
    
    private func calculateMonthlyRate(amount: Double, cycle: String) -> Double {
        switch cycle.lowercased() {
        case "anual":
            return amount / 12.0
        case "trimestrial":
            return amount / 3.0
        case "săptămânal", "saptamanal":
            return amount * 4.33
        default:
            return amount
        }
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
