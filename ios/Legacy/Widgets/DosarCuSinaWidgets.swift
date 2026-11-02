import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Interactive AppIntent for Widget Check-off
public struct CompleteEventIntent: AppIntent {
    public static var title: LocalizedStringResource = "Rezolvă Eveniment"
    public static var description = IntentDescription("Marchează un eveniment sau o obligație ca fiind rezolvată direct din widget.")
    
    @Parameter(title: "ID Eveniment")
    public var eventId: String
    
    public init() {
        self.eventId = ""
    }
    
    public init(eventId: String) {
        self.eventId = eventId
    }
    
    public func perform() async throws -> some IntentResult {
        WidgetDataProvider.markEventCompleted(eventId: eventId)
        return .result()
    }
}

// MARK: - Lock Screen Circular Widget View
struct LockScreenCircularView: View {
    let entry: DosarWidgetEntry
    
    private var gaugeProgress: CGFloat {
        // Clamped urgency gauge: 0 days remaining -> 1.0 (full gauge), 30 days -> 0.1
        let remaining = Double(max(0, entry.daysRemaining))
        let progress = 1.0 - (remaining / 30.0)
        return CGFloat(max(0.12, min(1.0, progress)))
    }
    
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            // Circular progress gauge track (Apple Craftsmanship: 3.5pt stroke)
            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 3.5)
            
            // Active gauge progress ring
            Circle()
                .trim(from: 0, to: gaugeProgress)
                .stroke(
                    entry.isUrgent || entry.isOverdue ? Color.primary : Color.primary.opacity(0.85),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: 1) {
                Image(systemName: entry.iconName)
                    .font(.system(size: 11, weight: .semibold))
                
                Text(entry.daysRemaining <= 0 ? (entry.daysRemaining == 0 ? "Azi" : "Exp") : "\(entry.daysRemaining)z")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Lock Screen Rectangular Widget View
struct LockScreenRectangularView: View {
    let entry: DosarWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: entry.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(entry.assetName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text(entry.daysRemaining <= 0 ? "Azi" : "\(entry.daysRemaining)z")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            
            Text(entry.eventTitle)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            
            Text(entry.statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Lock Screen Inline Widget View
struct LockScreenInlineView: View {
    let entry: DosarWidgetEntry
    
    var body: some View {
        ViewThatFits {
            Label("\(entry.assetName): \(entry.eventTitle) (\(entry.daysRemaining)z)", systemImage: entry.iconName)
            Label("\(entry.eventTitle) (\(entry.daysRemaining)z)", systemImage: entry.iconName)
            Label("\(entry.daysRemaining)z: \(entry.eventTitle)", systemImage: entry.iconName)
        }
    }
}

// MARK: - Home Screen Small Widget View
struct HomeScreenSmallView: View {
    let entry: DosarWidgetEntry
    
    // Concentric geometry: Container outer R=18, Inner card R=12, Badge R=8
    private let badgeRadius: CGFloat = 8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Asset Icon Squircle Badge
                ZStack {
                    RoundedRectangle(cornerRadius: badgeRadius, style: .continuous)
                        .fill(Color(widgetHex: entry.assetColorHex)?.opacity(0.18) ?? Color.blue.opacity(0.18))
                    
                    Image(systemName: entry.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(widgetHex: entry.assetColorHex) ?? Color.blue)
                }
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: badgeRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                
                Spacer()
                
                // Urgency Pill
                Text(entry.statusText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(entry.isOverdue ? Color.red : (entry.isUrgent ? Color.orange : Color.blue))
                    )
            }
            
            Spacer(minLength: 0)
            
            Text(entry.assetName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text(entry.eventTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
            
            // Interactive Complete Action Button
            if !entry.nearestEventId.isEmpty {
                Button(intent: CompleteEventIntent(eventId: entry.nearestEventId)) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Rezolvă")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
    }
}

// MARK: - Home Screen Medium Widget View
struct HomeScreenMediumView: View {
    let entry: DosarWidgetEntry
    
    // Concentric geometry:
    // Outer widget surface padding = 12pt
    // Left radar card radius R = 14pt
    // Right event row card radius R = 10pt
    // Inner icon badge radius R = 7pt (padding = 3pt: R_inner = 10 - 3 = 7pt)
    private let radarCardRadius: CGFloat = 14
    private let rowCardRadius: CGFloat = 10
    private let rowBadgeRadius: CGFloat = 7
    
    var body: some View {
        HStack(spacing: 12) {
            // LEFT COLUMN: Radar Overview & Health Score
            VStack(alignment: .leading, spacing: 8) {
                // Brand Header
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("DOSAR CU ȘINĂ")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 0)
                
                // Health Score Circular Progress Ring
                HStack(spacing: 10) {
                    ZStack {
                        // Background track
                        Circle()
                            .stroke(Color.primary.opacity(0.10), lineWidth: 5)
                        
                        // Active compliance ring
                        Circle()
                            .trim(from: 0, to: CGFloat(entry.healthScore) / 100.0)
                            .stroke(
                                entry.healthScore >= 80 ? Color.green : (entry.healthScore >= 50 ? Color.orange : Color.red),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(entry.healthScore)%")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .frame(width: 44, height: 44)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conformitate")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text(entry.healthScore >= 80 ? "Stare optimă" : "Atenție necesară")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Active Assets and Urgency Summary Badges
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 9))
                        Text("\(entry.activeAssetsCount) active")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    
                    if entry.urgentEventsCount > 0 {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                            Text("\(entry.urgentEventsCount) urgent\(entry.urgentEventsCount > 1 ? "e" : "ă")")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
            }
            .frame(width: 122)
            
            // Hairline vertical divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5)
                .padding(.vertical, 2)
            
            // RIGHT COLUMN: Next 3 Expiring Events with Interactive Check-off
            VStack(alignment: .leading, spacing: 6) {
                Text("URMĂTOARELE TERMENE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                
                if entry.upcomingEvents.isEmpty {
                    VStack(spacing: 4) {
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.green)
                        Text("Toate obligațiile sunt la zi")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text("Niciun termen urgent în următoarele 30 de zile.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    let displayEvents = Array(entry.upcomingEvents.prefix(3))
                    ForEach(displayEvents) { event in
                        HStack(spacing: 8) {
                            // Category Icon in Concentric Squircle Badge
                            ZStack {
                                RoundedRectangle(cornerRadius: rowBadgeRadius, style: .continuous)
                                    .fill(Color(widgetHex: event.assetColorHex)?.opacity(0.16) ?? Color.blue.opacity(0.16))
                                
                                Image(systemName: event.iconName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(widgetHex: event.assetColorHex) ?? Color.blue)
                            }
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: rowBadgeRadius, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                            
                            // Event Title & Asset Name
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                
                                Text(event.assetName)
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer(minLength: 4)
                            
                            // Colored Urgency Badge
                            Text(event.badgeText)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(widgetHex: event.urgencyColorHex) ?? Color.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill((Color(widgetHex: event.urgencyColorHex) ?? Color.orange).opacity(0.15))
                                )
                            
                            // Interactive Check-off Button (Button(intent:))
                            Button(intent: CompleteEventIntent(eventId: event.id)) {
                                Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(event.isCompleted ? Color.green : Color.secondary.opacity(0.7))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 22, height: 22)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: rowCardRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: rowCardRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Root Entry View Dispatcher
struct DosarCuSinaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DosarWidgetEntry
    
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                LockScreenCircularView(entry: entry)
            case .accessoryRectangular:
                LockScreenRectangularView(entry: entry)
            case .accessoryInline:
                LockScreenInlineView(entry: entry)
            case .systemSmall:
                HomeScreenSmallView(entry: entry)
            case .systemMedium:
                HomeScreenMediumView(entry: entry)
            @unknown default:
                HomeScreenMediumView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}

// MARK: - Widget Definition
public struct DosarCuSinaWidget: Widget {
    public let kind: String = "com.dosarcusina.widgets.radar"
    
    public init() {}
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DosarWidgetTimelineProvider()) { entry in
            DosarCuSinaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Radar Dosar cu Șină")
        .description("Monitorizează termenele, documentele și obligațiile importante direct de pe ecranul principal sau Lock Screen.")
        .supportedFamilies([
            .systemMedium,
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Widget Bundle Entry Point
@main
public struct DosarCuSinaWidgetBundle: WidgetBundle {
    public init() {}
    
    public var body: some Widget {
        DosarCuSinaWidget()
    }
}
