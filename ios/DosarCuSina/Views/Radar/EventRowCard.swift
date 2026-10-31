import SwiftUI

public struct EventRowCard: View {
    @Bindable public var event: LifecycleEvent
    public var onToggleCompletion: (() -> Void)?
    
    public init(event: LifecycleEvent, onToggleCompletion: (() -> Void)? = nil) {
        self.event = event
        self.onToggleCompletion = onToggleCompletion
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Checkbox button with Apple tactile feedback
            Button {
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    event.isCompleted.toggle()
                    if event.isCompleted {
                        event.completedDate = Date()
                        Task {
                            await NotificationScheduler.shared.cancelReminders(for: event)
                        }
                    } else {
                        event.completedDate = nil
                        Task {
                            _ = try? await NotificationScheduler.shared.scheduleReminders(for: event)
                        }
                    }
                }
                onToggleCompletion?()
            } label: {
                Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(event.isCompleted ? .green : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            
            // Event Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(event.isCompleted ? .secondary : .primary)
                        .strikethrough(event.isCompleted, color: .secondary)
                    
                    Spacer()
                    
                    if let cost = event.cost, cost > 0 {
                        Text("\(String(format: "%.0f", cost)) \(event.currency)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                
                if let prov = event.provider, !prov.isEmpty {
                    Text(prov)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 6) {
                    if let asset = event.asset {
                        HStack(spacing: 4) {
                            Image(systemName: asset.iconName)
                                .font(.caption2)
                            Text(asset.name)
                                .font(.caption)
                        }
                        .foregroundStyle(asset.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(asset.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    Text(event.statusBadgeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                    
                    if !event.serviceItems.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "wrench.fill")
                                .font(.caption2)
                            Text("\(event.serviceItems.count) \(event.serviceItems.count == 1 ? "piesă" : "piese")")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    if !event.attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
    }
    
    private var statusColor: Color {
        if event.isCompleted {
            return .secondary
        } else if event.isOverdue {
            return .red
        } else if event.isUrgent {
            return .orange
        } else {
            return .blue
        }
    }
}
